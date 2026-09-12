exports['feather-core']:RegisterRPC("bcc-shops:SetWebhook", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopId = params.shopId
    local webhook = params.webhook
    local user = ShopsCore.GetCharacterContext(source)
    if not user then return cb(false) end

    local character = user.character
    if not character then return cb(false) end

    local characterId = character.characterId

    if not shopId or not webhook then
        devPrint("Missing shopId or webhook")
        return cb(false)
    end

    -- Confirm ownership
    MySQL.query('SELECT owner_id FROM bcc_shops WHERE shop_id = ?', { shopId }, function(results)
        if not results or #results == 0 then
            devPrint("Shop not found with ID: " .. tostring(shopId))
            return cb(false)
        end

        if results[1].owner_id ~= characterId then
            devPrint("Unauthorized attempt to set webhook. Char: " .. characterId .. ", Owner: " .. results[1].owner_id)
            return cb(false)
        end

        MySQL.update('UPDATE bcc_shops SET webhook_link = ? WHERE shop_id = ?', { webhook, shopId },
            function(rowsChanged)
                cb(rowsChanged > 0)
            end)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetShopWebhook", function(params, cb, source)
    local _U = ShopTranslator(source)
    devPrint("GetShopWebhook RPC triggered for shopId: " .. tostring(params.shopId))
    local shopId = params.shopId
    if not shopId then return cb(nil) end

    local result = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })

    if result and result[1] then
        return cb({
            webhook = result[1].webhook_link,
            shopName = result[1].shop_name
        })
    else
        return cb(nil)
    end
end)