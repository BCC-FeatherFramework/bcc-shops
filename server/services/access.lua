exports['feather-core']:RegisterRPC("bcc-shops:GiveAccess", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopId = params.shopId
    local characterId = tostring(params.characterId)

    if not shopId or not characterId then
        devPrint("Missing shopId or characterId")
        return cb(false)
    end

    -- Check if access already exists
    local existingAccess = MySQL.query.await(
        'SELECT 1 FROM bcc_shop_access WHERE shop_id = ? AND character_id = ? LIMIT 1',
        { shopId, characterId }
    )

    if existingAccess and #existingAccess > 0 then
        devPrint("Character ID " .. characterId .. " already has access to shop ID " .. shopId)
        NotifyClient(source, _U('accessAlreadyExists'), "warning", 4000)
        return cb(false)
    end

    -- Insert new access
    local result = MySQL.insert.await(
        'INSERT INTO bcc_shop_access (shop_id, character_id) VALUES (?, ?)',
        { shopId, characterId }
    )

    local success = result ~= nil
    devPrint("Access granted to character " .. characterId .. " for shop ID " .. shopId .. ": " .. tostring(success))

    -- Get shop info (webhook + name)
    local shopResult = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })
    local shopInfo = shopResult and shopResult[1] or nil

    if not shopInfo then
        devPrint("shopInfo is nil for shopId: " .. tostring(shopId))
        return cb(success)
    end

    local webhook = shopInfo.webhook_link or Config.Webhook
    local shopName = shopInfo.shop_name or "Unknown"

    -- Fetch character name from DB
    local charResult = MySQL.query.await('SELECT first_name AS firstname, last_name AS lastname FROM character_profiles WHERE character_id = ?',
        { characterId })
    local character = charResult and charResult[1] or { firstname = "Unknown", lastname = "Unknown" }

    -- Send to shop-specific webhook
    if webhook then
        devPrint("Sending to shop-specific webhook: " .. webhook)
        ShopsToolkit.Discord.sendMessage(webhook,
            Config.WebhookTitle,
            Config.WebhookAvatar,
            "🔐 Access Granted",
            nil,
            {
                {
                    color = 3145631,
                    title = "🔓 New Access Granted",
                    description = table.concat({
                        "**Character ID:** `" .. characterId .. "`",
                        "**Character Name:** `" .. character.firstName .. " " .. character.lastName .. "`",
                        "**Shop Name:** `" .. shopName .. "`",
                        "**Shop ID:** `" .. shopId .. "`"
                    }, "\n")
                }
            }
        )
    end

    -- Also send to global webhook
    devPrint("Sending to global webhook: " .. Config.Webhook)
    ShopsToolkit.Discord.sendMessage(
        Config.Webhook,
        Config.WebhookTitle,
        Config.WebhookAvatar,
        "🔐 Access Granted",
        nil,
        {
            {
                color = 11342935,
                title = "🔓 New Access Granted",
                description = table.concat({
                    "**Character ID:** `" .. characterId .. "`",
                    "**Character Name:** `" .. character.firstName .. " " .. character.lastName .. "`",
                    "**Shop Name:** `" .. shopName .. "`",
                    "**Shop ID:** `" .. shopId .. "`"
                }, "\n")
            }
        }
    )

    cb(success)
end)

exports['feather-core']:RegisterRPC("bcc-shops:RemoveAccess", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopId = params.shopId
    local characterId = tostring(params.characterId)

    if not shopId or not characterId then
        devPrint("Missing shopId or characterId")
        return cb(false)
    end

    -- Get character info directly from DB (in case they're offline)
    local charResult = MySQL.query.await('SELECT first_name AS firstname, last_name AS lastname FROM character_profiles WHERE character_id = ?',
        { characterId })
    local firstname = "Unknown"
    local lastname = ""

    if charResult and charResult[1] then
        firstname = charResult[1].firstName
        lastname = charResult[1].lastName
    else
        devPrint("Character not found for ID: " .. characterId)
    end

    -- Get shop info for webhook
    local result = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })
    local shopInfo = result and result[1] or nil

    if not shopInfo then
        devPrint("shopInfo is nil for shopId: " .. tostring(shopId))
        return cb(false)
    end

    local webhook = shopInfo.webhook_link or Config.Webhook
    local shopName = shopInfo.shop_name or "Unknown"

    -- Perform deletion
    local rowsChanged = MySQL.update.await('DELETE FROM bcc_shop_access WHERE shop_id = ? AND character_id = ?', {
        shopId, characterId
    })

    local success = rowsChanged and rowsChanged > 0
    devPrint("Access removed for character " .. characterId .. " from shop ID " .. shopId .. ": " .. tostring(success))

    if success then
        local embed = {
            {
                color = 16711680,
                title = "🚫 Access Revoked",
                description = table.concat({
                    "**Character ID:** `" .. characterId .. "`",
                    "**Character Name:** `" .. firstname .. " " .. lastname .. "`",
                    "**Shop Name:** `" .. shopName .. "`",
                    "**Shop ID:** `" .. shopId .. "`"
                }, "\n")
            }
        }

        -- Shop webhook
        if webhook then
            devPrint("Sending to shop-specific webhook: " .. webhook)
            ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, "Access Removed", nil,
                embed)
        end

        -- Global webhook
        devPrint("Sending to global webhook: " .. Config.Webhook)
        ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, "Access Removed", nil,
            embed)
    else
        devPrint(" No access entry removed.")
    end

    cb(success)
end)

exports['feather-core']:RegisterRPC("bcc-shops:HasAccess", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopId = params.shopId
    local characterId = tostring(params.characterId)

    if not shopId or not characterId then return cb(false) end

    MySQL.query('SELECT * FROM bcc_shop_access WHERE shop_id = ? AND character_id = ? LIMIT 1', {
        shopId, characterId
    }, function(result)
        cb(result and #result > 0)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:CheckStoreOwnership", function(params, cb, source)
    local _U = ShopTranslator(source)
    if not params or not params.storeName then
        devPrint("Error: storeName is nil")
        return cb({ isOwner = false, hasAccess = false, storeName = params and params.storeName or "unknown" })
    end

    local user = ShopsCore.GetCharacterContext(source)
    if not user then return cb({ isOwner = false, hasAccess = false, storeName = params.storeName }) end

    local character = user.character
    if not character then return cb({ isOwner = false, hasAccess = false, storeName = params.storeName }) end

    local characterId = character.characterId
    local storeName = params.storeName

    devPrint("Checking ownership for store: " .. storeName .. ", Character ID: " .. tostring(characterId))

    MySQL.query('SELECT shop_id, owner_id FROM bcc_shops WHERE shop_name = ?', { storeName }, function(results)
        if results and #results > 0 then
            local shop = results[1]
            local isOwner = shop.owner_id == characterId
            local shopId = shop.shop_id

            if isOwner then
                devPrint("Player is the owner of store: " .. storeName)
                return cb({
                    isOwner = true,
                    hasAccess = true,
                    storeName = storeName
                })
            end

            -- Not owner, check access table
            MySQL.query('SELECT 1 FROM bcc_shop_access WHERE shop_id = ? AND character_id = ? LIMIT 1', {
                shopId, tostring(characterId)
            }, function(access)
                local hasAccess = access and #access > 0
                devPrint("Player has access to store: " .. tostring(hasAccess))

                cb({
                    isOwner = false,
                    hasAccess = hasAccess,
                    storeName = storeName
                })
            end)
        else
            devPrint("Store not found: " .. storeName)
            cb({ isOwner = false, hasAccess = false, storeName = storeName })
        end
    end)
end)


exports['feather-core']:RegisterRPC("bcc-shops:CheckAdmin", function(_, cb, src)
    local _U = ShopTranslator(src)
    cb(CanManageShops(src))
end)
