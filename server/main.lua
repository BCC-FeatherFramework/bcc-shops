

discord = ShopsToolkit.Discord.setup(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar)


exports['feather-core']:RegisterRPC("bcc-shops:GetPlayerLevel", function(_, cb, src)
    local _U = ShopTranslator(src)
    local user = ShopsCore.GetCharacterContext(src)
    local character = user and user.character

    if character and character.xp then
        local level = getLevelFromXP(character.xp)
        devPrint("[RPC] Player level for src " .. src .. " is: " .. level)
        cb(level)
    else
        devPrint("[RPC] Character or XP not found for src: " .. src)
        cb(nil)
    end
end)


