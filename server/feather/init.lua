-- Management authority comes from the active character's Feather role.
function CanManageShops(src)
    local result = exports['feather-roles']:GetActorRole(tonumber(src))
    if type(result) ~= 'table' or result.ok ~= true or type(result.value) ~= 'table'
        or type(result.value.role) ~= 'table' then return false end
    for _, key in ipairs(Config.ManagementRoles or { 'admin', 'owner', 'moderator' }) do
        if result.value.role.key == key then return true end
    end
    return false
end

function GetShopCharacterProfile(src)
    local session = exports['feather-core']:GetSessionContext(tonumber(src))
    if type(session) ~= 'table' or session.ok ~= true or type(session.value) ~= 'table' then return nil end
    local provider = exports['feather-core']:GetProvider('character-profile', nil, 1)
    if type(provider) ~= 'table' or provider.ok ~= true or type(provider.value) ~= 'table'
        or not provider.value.implementation then return nil end
    local profile = provider.value.implementation.GetProfile(session.value.characterId)
    if type(profile) ~= 'table' or profile.ok ~= true or type(profile.value) ~= 'table' then return nil end
    return profile.value
end

-- BCC gameplay compatibility over Feather's local service contracts.
ShopsCore = {}
function ShopsCore.GetCharacterContext(src)
    local session = exports['feather-core']:GetSessionContext(tonumber(src))
    if type(session) ~= 'table' or session.ok ~= true or type(session.value) ~= 'table' then return nil end
    local profile = GetShopCharacterProfile(src)
    if not profile then return nil end
    local current = exports['feather-core']:GetSessionContext(tonumber(src))
    if not current or not current.ok or current.value.sessionId ~= session.value.sessionId
        or current.value.characterId ~= session.value.characterId then return nil end
    return { character = {
        source = tonumber(src), accountId = session.value.accountId,
        sessionId = session.value.sessionId, characterId = session.value.characterId,
        firstName = profile.firstName, lastName = profile.lastName,
        xp = tonumber(Config.DefaultPlayerXP) or 0
    } }
end
function ShopsCore.Notify(src, message, duration)
    return exports['feather-core']:SendNotification({ source = tonumber(src), message = message, duration = duration, style = 'right' })
end
ShopsToolkit = { Discord = {} }
function ShopsToolkit.Discord.setup() return {} end
function ShopsToolkit.Discord.sendMessage(url, title, avatar, content, _, embeds)
    if type(url) ~= 'string' or not url:match('^https://discord.com/api/webhooks/') then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = title, avatar_url = avatar, content = content, embeds = embeds }), { ['Content-Type'] = 'application/json' })
end
local function api() return exports['feather-inventory']:initiate() end
local function identity(src)
    local r = exports['feather-core']:GetSessionContext(tonumber(src))
    return r and r.ok and r.value.characterId
end
local function rows(src, weapons)
    local id = identity(src)
    local inv = id and exports['feather-inventory']:GetCharacterInventory(id)
    if not inv or not inv.ok then return {} end
    local result = api().Inventory.GetInventoryItems(inv.value.id)
    local out, grouped = {}, {}
    for _, row in ipairs(result and result.ok and result.value or {}) do
        local weapon = row.name:lower():match('^weapon_') ~= nil
        if weapon == weapons then
            if weapon then
                row.count, row.label = 1, row.display_name
                out[#out + 1] = row
            else
                local entry = grouped[row.name]
                if not entry then
                    entry = { name = row.name, label = row.display_name, count = 0, metadata = row.metadata }
                    grouped[row.name], out[#out + 1] = entry, entry
                end
                entry.count = entry.count + 1
            end
        end
    end
    return out
end
ShopsInventory = {}
function ShopsInventory:GetCharacterItems(src, cb)
    local value = rows(src, false); if cb then cb(value) end; return value
end
function ShopsInventory:GetCharacterWeapons(src, cb)
    local value = rows(src, true); if cb then cb(value) end; return value
end
function ShopsInventory:getItem(src, name, cb)
    local found
    for _, row in ipairs(rows(src, false)) do if row.name == name then found = row; break end end
    if cb then cb(found) end; return found
end
function ShopsInventory:getItemCount(src, cb, name)
    local r = api().Items.GetItemCount(name, tonumber(src))
    local n = r and r.ok and r.value or 0; if cb then cb(n) end; return n
end
function ShopsInventory:canCarryItems() return true end -- Specific acceptance follows at every call site.
function ShopsInventory:canCarryItem(src, name, quantity)
    local r = api().Inventory.InventoryCanHold({ { item = name:lower(), quantity = quantity } }, tonumber(src))
    return r and r.ok and r.value.accepted == true
end
function ShopsInventory:canCarryWeapons(src, quantity, _, name) return self:canCarryItem(src, name, quantity) end
function ShopsInventory:addItem(src, name, quantity, characterId)
    local r = exports['feather-inventory']:GrantCharacterItem(characterId or identity(src), name, quantity, 'shops.purchase')
    if not r or not r.ok then error(r and r.code or 'inventory_grant_failed') end
    return true
end
function ShopsInventory:subItem(src, name, quantity, _, cb)
    local r = api().Items.RemoveItemByName(name:lower(), quantity, tonumber(src))
    local ok = r and r.ok == true; if cb then cb(ok) end; return ok
end
function ShopsInventory:subWeapon(src, instanceId, cb)
    local r = exports['feather-inventory']:RemoveCharacterInventoryInstance(identity(src), instanceId, 'shops.stock')
    local ok = r and r.ok == true; if cb then cb(ok) end; return ok
end
function ShopsInventory:createWeapon(src, name, characterId, requestId)
    local definitions = exports['feather-weapons']:initiate().Definitions.List('weapon')
    local definitionId
    for _, def in pairs(definitions and definitions.ok and definitions.value or {}) do
        if def.itemName:lower() == name:lower() then definitionId = def.id; break end
    end
    -- Weapons accepts cross-resource issuance only for an allow-listed purpose and
    -- requires a stable requestId (its idempotency key), so a replayed order
    -- returns the weapon already issued instead of creating another one.
    local r = exports['feather-weapons']:IssueWeapon({ characterId = characterId or identity(src), definitionId = definitionId,
        purpose = 'purchase', requestId = requestId,
        provenance = { type = 'shop_purchase', reference = requestId } },
        { reason = 'shops.purchase', actorSource = tonumber(src) })
    if not r or not r.ok then error(r and r.code or 'weapon_issuance_failed') end
    return r.value.itemInstanceId
end
