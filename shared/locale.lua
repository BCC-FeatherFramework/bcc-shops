-- Feather Core owns locale registration and account locale preferences.
Feather = Feather or {}
Feather.Locale = Feather.Locale or {}
local fallbackTranslations
local namespace = 'bcc-shops.'

function Feather.Locale.register(locale, translations)
    local registered = {}
    for key, value in pairs(translations) do
        registered[namespace .. key] = value
    end
    local result = exports['feather-core']:RegisterLocale(locale, registered)
    if type(result) ~= 'table' or result.ok ~= true then
        error('Shop locale registration failed: ' .. tostring(locale))
    end
    if locale == Config.defaultlang then fallbackTranslations = translations end
end

function TranslateShopLocale(actorSource, key, ...)
    local result = exports['feather-core']:TranslateLocale(actorSource or 0, namespace .. key, ...)
    if type(result) == 'table' and result.ok == true and type(result.value) == 'string'
        and not result.value:match('^Translation %[') and not result.value:match('^Locale %[') then
        return result.value
    end
    local fallback = fallbackTranslations and fallbackTranslations[key]
    if fallback then return string.format(fallback, ...) end
    return 'Missing shop translation: ' .. tostring(key)
end

function _(key, ...)
    return TranslateShopLocale(IsDuplicityVersion() and tonumber(source) or 0, key, ...)
end

function ShopTranslator(actorSource)
    return function(key, ...)
        local translation = TranslateShopLocale(actorSource, key, ...)
        return translation:sub(1, 1):upper() .. translation:sub(2)
    end
end

function _U(key, ...)
    local translation = _(key, ...)
    return translation:sub(1, 1):upper() .. translation:sub(2)
end
