exports['feather-core']:RegisterRPC("bcc-shops:PurchaseItem", function(params, cb, src)
    local _U = ShopTranslator(src)
    local Character = ShopsCore.GetCharacterContext(src).character
    local isWeapon = params.isWeapon

    local itemDetails
    if isWeapon then
        itemDetails = MySQL.query.await('SELECT * FROM bcc_shop_weapon_items WHERE item_name = ?', { params.itemName })
    else
        itemDetails = MySQL.query.await('SELECT * FROM bcc_shop_items WHERE item_name = ?', { params.itemName })
    end

    itemDetails = itemDetails and itemDetails[1]

    if not itemDetails then
        devPrint("Item not found: " .. tostring(params.itemName))
        NotifyClient(src, _U("shop_item_not_found"), "error")
        return cb(false)
    end

    devPrint("Fetched item details: " .. json.encode(itemDetails))

    local level = getLevelFromXP(Character.xp)
    if level < (itemDetails.level_required or 0) then
        NotifyClient(src, _U("shop_level_required", { level = itemDetails.level_required }), "warning")
        return cb(false)
    end

    local query = [[
        SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND is_npc_shop = 1)
          AND item_name = @itemName
        UNION
        SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL)
          AND item_name = @itemName
    ]]

    local results = MySQL.query.await(query, {
        ['@shopName'] = params.shopName,
        ['@itemName'] = params.itemName
    })

    if not results or #results == 0 then
        NotifyClient(src, _U("shop_item_not_found"), "error")
        return cb(false)
    end

    local data = results[1]
    local shopId = data.shop_id
    local shopType = data.shop_type
    local buyQuantity = data.buy_quantity or 0

    devPrint("Shop Type:", shopType, "| Shop ID:", shopId, "| Buy Quantity:", buyQuantity)

    if buyQuantity < params.quantity then
        NotifyClient(src, _U("shop_not_enough_stock"), "warning")
        return cb(false)
    end

    if Character.money < params.total then
        NotifyClient(src, _U("shop_not_enough_money"), "error")
        return cb(false)
    end

    local canCarryItems = ShopsInventory:canCarryItems(src, params.quantity, nil)
    local canCarry = ShopsInventory:canCarryItem(src, params.itemName, params.quantity, nil)

    if canCarry and canCarryItems then
        Character.DebitWallet(0, params.total)
        local granted, failure = pcall(function() ShopsInventory:addItem(src, params.itemName, params.quantity) end)
        if not granted then
            Character.CreditWallet(0, params.total)
            devPrint('Inventory grant failed:', failure)
            return cb(false)
        end

        devPrint("Transaction processed. Removed currency and added item:", params.itemName, "x" .. params.quantity)

        MySQL.update.await(
            'UPDATE bcc_shop_items SET buy_quantity = buy_quantity - ? WHERE shop_id = ? AND item_name = ?',
            { params.quantity, shopId, params.itemName }
        )

        MySQL.update.await(
            'UPDATE bcc_shops SET ledger = ledger + ? WHERE shop_id = ?',
            { params.total, shopId }
        )

        NotifyClient(src,
            _U("shop_bought_item") .. params.quantity .. "x " .. itemDetails.item_label .. _U("formoney") .. params
            .total,
            "success")

        local shopResult = MySQL.query.await(
            'SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?',
            { shopId }
        )
        local shopInfo = shopResult and shopResult[1] or nil

        if not shopInfo then
            devPrint("shopInfo is nil for shopId:", shopId)
            return cb(true)
        end

        local webhook = shopInfo.webhook_link or Config.Webhook
        local shopName = shopInfo.shop_name or "Unknown"

        local embed = { {
            color = 3145631,
            title = "Item Purchased",
            description = table.concat({
                "**Character Name:** `" .. Character.firstName .. " " .. Character.lastName .. "`",
                "**Character ID:** `" .. Character.characterId .. "`",
                "**Item Name:** `" .. itemDetails.item_label .. "`",
                "**Item ID:** `" .. params.itemName .. "`",
                "**Quantity:** `" .. params.quantity .. "`",
                "**Total Cost:** `" .. params.total .. "`",
                "**Shop Name:** `" .. shopName .. "`"
            }, "\n")
        } }

        if shopInfo.webhook_link then
            devPrint("Sending to shop-specific webhook:", shopInfo.webhook_link)
            ShopsToolkit.Discord.sendMessage(
                shopInfo.webhook_link,
                Config.WebhookTitle,
                Config.WebhookAvatar,
                "Item Purchased",
                nil,
                embed
            )
        else
            devPrint("No shop-specific webhook defined.")
        end

        devPrint("Sending to global webhook:", Config.Webhook)
        ShopsToolkit.Discord.sendMessage(
            Config.Webhook,
            Config.WebhookTitle,
            Config.WebhookAvatar,
            "Item Purchased",
            nil,
            embed
        )

        cb(true)
    else
        devPrint("Player cannot carry item:", params.itemName, "x" .. params.quantity)
        NotifyClient(src, _U("shop_cannot_carry"), "warning")
        return cb(false)
    end
end)

exports['feather-core']:RegisterRPC("bcc-shops:PurchaseItemNPC", function(params, cb)
    local Character = {
        firstname = "Shop",
        lastname = "Visitor",
        characterId = "NPC"
    }

    if not params.itemName then
        devPrint("[NPC Purchase] itemName is nil")
        return cb(false)
    end

    local itemResult = MySQL.query.await('SELECT * FROM bcc_shop_items WHERE item_name = ?', { params.itemName })
    local itemDetails = itemResult and itemResult[1] or nil

    if not itemDetails then
        devPrint("[NPC Purchase] itemDetails not found for: " .. tostring(params.itemName))
        return cb(false)
    end

    local query = [[
        SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND is_npc_shop = 1)
          AND item_name = @itemName
        UNION
        SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL)
          AND item_name = @itemName
    ]]

    local results = MySQL.query.await(query, {
        ['@shopName'] = params.shopName,
        ['@itemName'] = params.itemName
    })

    if not results or #results == 0 then
        devPrint("[NPC Purchase] item not found in shop: " .. tostring(params.shopName))
        return cb(false)
    end

    local data = results[1]
    local shopId = data.shop_id
    local buyQuantity = data.buy_quantity or 0

    if buyQuantity < params.quantity then
        devPrint("[NPC Purchase] Not enough stock for " .. params.itemName)
        return cb(false)
    end

    MySQL.update.await('UPDATE bcc_shop_items SET buy_quantity = buy_quantity - ? WHERE shop_id = ? AND item_name = ?', {
        params.quantity, shopId, params.itemName
    })

    MySQL.update.await('UPDATE bcc_shops SET ledger = ledger + ? WHERE shop_id = ?', {
        params.total, shopId
    })

    local shopResult = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })
    local shopInfo = shopResult and shopResult[1] or nil

    if not shopInfo then
        devPrint("[NPC Purchase] shopInfo is nil for shopId: " .. tostring(shopId))
        return cb(true)
    end

    local webhook = shopInfo.webhook_link or Config.Webhook
    local shopName = shopInfo.shop_name or params.shopName or "Unknown"

    local embed = { {
        color = 3145631,
        title = "Item Purchased",
        description = table.concat({
            "**Character Name:** `NPC`",
            "**Character ID:** `NPC`",
            "**Item Name:** `" .. itemDetails.item_label .. "`",
            "**Item ID:** `" .. params.itemName .. "`",
            "**Quantity:** `" .. params.quantity .. "`",
            "**Total Cost:** `" .. params.total .. "`",
            "**Shop Name:** `" .. shopName .. "`"
        }, "\n")
    } }

    -- Send to shop-specific webhook if available
    if shopInfo.webhook_link then
        devPrint("[NPC Purchase] Sending to shop-specific webhook: " .. shopInfo.webhook_link)
        ShopsToolkit.Discord.sendMessage(
            shopInfo.webhook_link,
            Config.WebhookTitle,
            Config.WebhookAvatar,
            "Item Purchased",
            nil,
            embed
        )
    else
        devPrint("[NPC Purchase] No shop-specific webhook. Using global only.")
    end

    -- Always send to global webhook
    devPrint("[NPC Purchase] Sending to global webhook: " .. Config.Webhook)
    ShopsToolkit.Discord.sendMessage(
        Config.Webhook,
        Config.WebhookTitle,
        Config.WebhookAvatar,
        "Item Purchased",
        nil,
        embed
    )

    cb(true)
end)

exports['feather-core']:RegisterRPC("bcc-shops:SellItem", function(params, cb, src)
    local _U = ShopTranslator(src)
    devPrint("SellItem called by src:", src)

    if not params or not params.itemName or not params.shopName or not params.quantity or not params.total then
        devPrint("Invalid params received:", json.encode(params))
        NotifyClient(src, _U("shop_item_not_found"), "error")
        return cb(false)
    end

    local user = ShopsCore.GetCharacterContext(src)
    if not user then
        devPrint("No user found for src:", src)
        return cb(false)
    end

    local Character = user.character
    if not Character then
        devPrint("No character found for src:", src)
        return cb(false)
    end

    devPrint("Character:", Character.firstName, Character.lastName, "XP:", Character.xp)

    local itemResult = MySQL.query.await('SELECT * FROM bcc_shop_items WHERE item_name = ?', { params.itemName })
    local itemDetails = itemResult and itemResult[1] or nil

    if not itemDetails then
        devPrint("Item not found in database:", params.itemName)
        NotifyClient(src, _U("shop_item_not_found"), "error")
        return cb(false)
    end

    local level = getLevelFromXP(Character.xp)
    if level < (itemDetails.level_required or 0) then
        devPrint("Character level too low: required", itemDetails.level_required, "got", level)
        NotifyClient(src, _U("shop_level_required", { level = itemDetails.level_required }), "warning")
        return cb(false)
    end

    local shopData = MySQL.query.await([[
        SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = ? AND is_npc_shop = 1)
          AND item_name = ?
        UNION
        SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = ? AND owner_id IS NOT NULL)
          AND item_name = ?
    ]], {
        params.shopName, params.itemName,
        params.shopName, params.itemName
    })

    if not shopData or #shopData == 0 then
        devPrint("Shop item not found in shop:", params.shopName)
        NotifyClient(src, _U("shop_item_not_found"), "error")
        return cb(false)
    end

    local data = shopData[1]
    local shopId, shopType = data.shop_id, data.shop_type
    local sellQuantity = data.sell_quantity or 0

    devPrint("🏪 Shop Type:", shopType, "| Shop ID:", shopId, "| Sell Quantity:", sellQuantity)

    if sellQuantity < params.quantity then
        devPrint("Not enough sell quantity. Requested:", params.quantity, "Available:", sellQuantity)
        NotifyClient(src, _U("shop_not_enough_stock_to_sell"), "warning")
        return cb(false)
    end

    local removed = ShopsInventory:subItem(src, params.itemName, params.quantity, {})
    if removed then
        devPrint("Removed item from inventory. Proceeding with sale.")

        if shopType == "player" then
            local ledger = MySQL.scalar.await("SELECT ledger FROM bcc_shops WHERE shop_id = ?", { shopId })
            if not ledger or ledger < params.total then
                devPrint("Not enough money in shop ledger. Ledger:", ledger, "Needed:", params.total)
                NotifyClient(src, _U("shop_not_enough_ledger_money"), "error")
                return cb(false)
            end

            Character.CreditWallet(0, params.total)
            devPrint("Gave player money (ledger deducted):", params.total)

            -- move stock: sell_quantity -= qty, buy_quantity += qty
            MySQL.update.await(
                "UPDATE bcc_shop_items " ..
                "SET sell_quantity = GREATEST(sell_quantity - ?, 0), " ..
                "    buy_quantity  = buy_quantity + ? " ..
                "WHERE shop_id = ? AND item_name = ?",
                { params.quantity, params.quantity, shopId, params.itemName }
            )

            MySQL.update.await("UPDATE bcc_shops SET ledger = ledger - ? WHERE shop_id = ?", { params.total, shopId })
        else
            Character.CreditWallet(0, params.total)
            devPrint("Gave player money (npc shop):", params.total)

            MySQL.update.await(
                "UPDATE bcc_shop_items " ..
                "SET sell_quantity = GREATEST(sell_quantity - ?, 0), " ..
                "    buy_quantity  = buy_quantity + ? " ..
                "WHERE shop_id = ? AND item_name = ?",
                { params.quantity, params.quantity, shopId, params.itemName }
            )
        end

        NotifyClient(src,
            _U("shop_sold_item") .. params.quantity .. "x " .. itemDetails.item_label .. _U("formoney") .. params.total,
            "success")

        -- Webhook logging
        local webhookData = MySQL.query.await("SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?",
            { shopId })
        local shopInfo = webhookData and webhookData[1] or nil
        local webhook = (shopInfo and shopInfo.webhook_link) or Config.Webhook
        local shopName = (shopInfo and shopInfo.shop_name) or params.shopName

        devPrint("📤 Sending webhook log. Webhook:", webhook)

        local embed = { {
            color = 3145631,
            title = "🛒 Item Sold",
            description = table.concat({
                "**Character Name:** `" .. Character.firstName .. " " .. Character.lastName .. "`",
                "**Character ID:** `" .. Character.characterId .. "`",
                "**Item Name:** `" .. itemDetails.item_label .. "`",
                "**Item ID:** `" .. params.itemName .. "`",
                "**Quantity:** `" .. params.quantity .. "`",
                "**Total Cost:** `" .. params.total .. "`",
                "**Shop Name:** `" .. shopName .. "`"
            }, "\n")
        } }

        -- Send to shop-specific webhook if present
        if shopInfo and shopInfo.webhook_link then
            devPrint("📤 Sending to shop-specific webhook:", shopInfo.webhook_link)
            ShopsToolkit.Discord.sendMessage(
                shopInfo.webhook_link,
                Config.WebhookTitle,
                Config.WebhookAvatar,
                "🛒 Item Sold",
                nil,
                embed
            )
        else
            devPrint("No shop-specific webhook, defaulting only to global.")
        end

        -- Always send to global webhook (Config.Webhook)
        devPrint("📤 Sending to global webhook:", Config.Webhook)
        ShopsToolkit.Discord.sendMessage(
            Config.Webhook,
            Config.WebhookTitle,
            Config.WebhookAvatar,
            "🛒 Item Sold",
            nil,
            embed
        )

        cb(true)
    else
        devPrint("Failed to remove item:", params.itemName)
        NotifyClient(src, _U("shop_failed_remove_item"), "error")
        return cb(false)
    end
end)

exports['feather-core']:RegisterRPC("bcc-shops:PurchaseWeapon", function(params, cb, src)
    local _U = ShopTranslator(src)
    local Character = ShopsCore.GetCharacterContext(src).character
    local weaponName = params.weaponName
    local shopName = params.shopName

    if not weaponName then
        devPrint("weaponName is nil")
        return cb(false)
    end

    local weaponResult = MySQL.query.await('SELECT * FROM bcc_shop_weapon_items WHERE weapon_name = ?', { weaponName })
    if not weaponResult or #weaponResult == 0 then
        devPrint("[PurchaseWeapon] Weapon not found: " .. tostring(weaponName))
        NotifyClient(src, _U("shop_weapon_not_found"), "error")
        return cb(false)
    end

    local weaponDetails = weaponResult[1]
    weaponDetails.level = weaponDetails.level_required or 0
    weaponDetails.label = weaponDetails.weapon_label or weaponName

    local playerLevel = getLevelFromXP(Character.xp)
    if playerLevel < weaponDetails.level then
        NotifyClient(src, _U("shop_level_required", { level = weaponDetails.level }), "warning")
        return cb(false)
    end

    local query = [[
        SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = ? AND is_npc_shop = 1)
          AND weapon_name = ?
        UNION
        SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = ? AND owner_id IS NOT NULL)
          AND weapon_name = ?
    ]]

    local results = MySQL.query.await(query, { shopName, weaponName, shopName, weaponName })
    if not results or #results == 0 then
        NotifyClient(src, _U("shop_weapon_not_found"), "error")
        return cb(false)
    end

    local data = results[1]
    local shopId = data.shop_id
    local buyQuantity = data.buy_quantity or 0

    if buyQuantity < params.quantity then
        NotifyClient(src, _U("shop_not_enough_stock"), "warning")
        return cb(false)
    end

    if Character.money < params.total then
        NotifyClient(src, _U("shop_not_enough_money"), "error")
        return cb(false)
    end

    local canCarry = ShopsInventory:canCarryWeapons(src, params.quantity, nil, weaponName)
    if not canCarry then
        NotifyClient(src, _U("shop_cannot_carry_weapon"), "error")
        return cb(false)
    end

    local issuedInstances = {}
    for i = 1, params.quantity do
        local ok, instance = pcall(function() return ShopsInventory:createWeapon(src, weaponName) end)
        if not ok then
            for _, instanceId in ipairs(issuedInstances) do ShopsInventory:subWeapon(src, instanceId) end
            devPrint('Weapon issuance failed:', instance)
            return cb(false)
        end
        issuedInstances[#issuedInstances + 1] = instance
    end

    Character.DebitWallet(0, params.total)

    MySQL.update.await(
        'UPDATE bcc_shop_weapon_items SET buy_quantity = buy_quantity - ? WHERE shop_id = ? AND weapon_name = ?',
        { params.quantity, shopId, weaponName }
    )

    MySQL.update.await('UPDATE bcc_shops SET ledger = ledger + ? WHERE shop_id = ?', {
        params.total, shopId
    })

    NotifyClient(src,
        _U("shop_bought_weapon") .. params.quantity .. "x " .. weaponDetails.label .. _U("formoney") .. params.total,
        "success")

    local shopResult = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })
    local shopInfo = shopResult and shopResult[1] or {}
    local webhook = (shopInfo.webhook_link and shopInfo.webhook_link ~= "none") and shopInfo.webhook_link or
    Config.Webhook
    local finalShopName = shopInfo.shop_name or shopName

    local message = {
        color = 3145631,
        title = "Item Purchased",
        description = table.concat({
            "**Character Name:** `" .. Character.firstName .. " " .. Character.lastName .. "`",
            "**Character ID:** `" .. Character.characterId .. "`",
            "**Weapon Name:** `" .. weaponDetails.label .. "`",
            "**Weapon ID:** `" .. weaponName .. "`",
            "**Quantity:** `" .. params.quantity .. "`",
            "**Total Cost:** `$" .. params.total .. "`",
            "**Shop Name:** `" .. finalShopName .. "`"
        }, "\n")
    }

    devPrint("[PurchaseWeapon] Sending to shop-specific webhook:", webhook)
    ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, message.title, nil, { message })

    devPrint("[PurchaseWeapon] Sending to global webhook:", Config.Webhook)
    ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, message.title, nil,
        { message })

    cb(true)
end)

exports['feather-core']:RegisterRPC("bcc-shops:PurchaseWeaponNPC", function(params, cb)
    local Character = {
        firstname = "Shop",
        lastname = "Visitor",
        characterId = "NPC"
    }

    local weaponName = params.weaponName
    local shopName = params.shopName

    if not weaponName or not shopName then
        devPrint("[NPC Purchase] Missing weaponName or shopName")
        return cb(false)
    end

    local query = [[
        SELECT weapon_label, buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND is_npc_shop = 1)
          AND weapon_name = @weaponName
        UNION
        SELECT weapon_label, buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL)
          AND weapon_name = @weaponName
    ]]

    MySQL.Async.fetchAll(query, {
        ['@shopName'] = shopName,
        ['@weaponName'] = weaponName
    }, function(results)
        if not results or #results == 0 then
            devPrint("[NPC Purchase]  Weapon not found in shop: " .. tostring(shopName))
            return cb(false)
        end

        local data = results[1]
        local shopId = data.shop_id
        local buyQuantity = data.buy_quantity or 0
        local weaponLabel = data.weapon_label or weaponName

        if buyQuantity < params.quantity then
            devPrint("[NPC Purchase] Not enough stock for weapon: " .. weaponName)
            return cb(false)
        end

        -- Update stock and ledger
        MySQL.Async.execute(
            'UPDATE bcc_shop_weapon_items SET buy_quantity = buy_quantity - ? WHERE shop_id = ? AND weapon_name = ?',
            { params.quantity, shopId, weaponName }
        )
        MySQL.Async.execute('UPDATE bcc_shops SET ledger = ledger + ? WHERE shop_id = ?', {
            params.total, shopId
        })

        -- Get shop info for webhook
        local shopResult = MySQL.query.await('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', { shopId })
        local shopInfo = shopResult and shopResult[1] or {}

        local webhook = shopInfo.webhook_link or Config.Webhook
        local shopDisplayName = shopInfo.shop_name or shopName

        local embed = {
            color = 3145631,
            title = "🛒 Weapon Purchased",
            description = table.concat({
                "**Character Name:** `NPC`",
                "**Character ID:** `NPC`",
                "**Weapon Name:** `" .. weaponLabel .. "`",
                "**Weapon ID:** `" .. weaponName .. "`",
                "**Quantity:** `" .. params.quantity .. "`",
                "**Total Cost:** `$" .. params.total .. "`",
                "**Shop Name:** `" .. shopDisplayName .. "`"
            }, "\n")
        }

        -- Send to shop-specific webhook
        if webhook then
            devPrint("📤 Sending to shop-specific webhook: " .. webhook)
            ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, embed.title, nil, { embed })
        end

        -- Send to global fallback webhook
        ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, embed.title, nil, { embed })

        cb(true)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:SellWeapon", function(params, cb, src)
    local _U = ShopTranslator(src)
    local Character = ShopsCore.GetCharacterContext(src).character

    if not params.weaponName then
        devPrint("[SellWeapon] weaponName is nil")
        NotifyClient(src, _U("shop_weapon_not_found"), "error")
        return cb(false)
    end

    local weaponResult = MySQL.query.await('SELECT * FROM bcc_shop_items WHERE item_name = ?', { params.weaponName })
    if not weaponResult or #weaponResult == 0 then
        devPrint("item_name not found: " .. tostring(params.weaponName))
        NotifyClient(src, _U("shop_weapon_not_found"), "error")
        return cb(false)
    end

    local weaponDetails = weaponResult[1]
    devPrint("Fetched details: " .. json.encode(weaponDetails))

    local level = getLevelFromXP(Character.xp)
    if level < (weaponDetails.level_required or 0) then
        NotifyClient(src, _U("shop_level_required", { level = weaponDetails.level_required }), "warning")
        return cb(false)
    end

    local query = [[
        SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND is_npc_shop = 1)
          AND weapon_name = @weaponName
        UNION
        SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type
        FROM bcc_shop_weapon_items
        WHERE shop_id = (SELECT shop_id FROM bcc_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL)
          AND weapon_name = @weaponName
    ]]

    local results = MySQL.query.await(query, {
        ['@shopName'] = params.shopName,
        ['@weaponName'] = params.weaponName
    })

    if not results or #results == 0 then
        NotifyClient(src, _U("shop_weapon_not_found"), "error")
        return cb(false)
    end

    local data = results[1]
    local sellQuantity = data.sell_quantity or 0
    local shopId = data.shop_id
    local shopType = data.shop_type

    if sellQuantity < params.quantity then
        NotifyClient(src, _U("shop_not_enough_stock_to_sell"), "warning")
        return cb(false)
    end

    ShopsInventory:subItem(src, params.weaponName, params.quantity, {}, function(success)
        if not success then
            NotifyClient(src, _U("shop_failed_remove_item"), "error")
            return cb(false)
        end

        if shopType == 'player' then
            MySQL.Async.fetchScalar('SELECT ledger FROM bcc_shops WHERE shop_id = ?', { shopId },
                function(ledger)
                    if not ledger or ledger < params.total then
                        NotifyClient(src, _U("shop_not_enough_ledger_money"), "error")
                        return cb(false)
                    end

                    Character.CreditWallet(0, params.total)
                    MySQL.Async.execute(
                        'UPDATE bcc_shop_weapon_items SET sell_quantity = sell_quantity - ? WHERE shop_id = ? AND weapon_name = ?',
                        {
                            params.quantity, shopId, params.weaponName
                        })
                    MySQL.Async.execute('UPDATE bcc_shops SET ledger = ledger - ? WHERE shop_id = ?', {
                        params.total, shopId
                    })

                    NotifyClient(src,
                        _U("shop_sold_weapon") ..
                        params.quantity .. "x " .. weaponDetails.weapon_label .. _U("formoney") .. params.total,
                        "success")

                    -- Get shop info (webhook + name)
                    local shopResult = MySQL.query.await(
                        'SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?',
                        { shopId })
                    local shopInfo = shopResult and shopResult[1] or nil

                    if not shopInfo then
                        devPrint("shopInfo is nil for shopId: " .. tostring(shopId))
                        return cb(true)
                    end

                    local webhook = shopInfo.webhook_link or Config.Webhook
                    local shopName = shopInfo.shop_name or "Unknown"

                    -- Send to shop-specific webhook
                    if webhook then
                        devPrint("Sending to shop-specific webhook: " .. webhook)
                        ShopsToolkit.Discord.sendMessage(webhook,
                            Config.WebhookTitle,
                            Config.WebhookAvatar,
                            "🛒 Weapon sold",
                            nil,
                            {
                                {
                                    color = 3145631,
                                    title = "🛒 Weapon sold",
                                    description = table.concat({
                                        "**Character Name:** `" ..
                                        Character.firstName .. " " .. Character.lastName .. "`",
                                        "**Character ID:** `" .. Character.characterId .. "`",
                                        "**Weapon Name:** `" .. weaponDetails.weapon_label .. "`",
                                        "**Weapon ID:** `" .. params.weaponName .. "`",
                                        "**Quantity:** `" .. params.quantity .. "`",
                                        "**Total Cost:** `" .. params.total .. "`",
                                        "**Shop Name:** `" .. shopName .. "`"
                                    }, "\n")
                                }
                            }
                        )
                    end

                    devPrint("Sending to global webhook: " .. Config.Webhook)
                    ShopsToolkit.Discord.sendMessage(
                        Config.Webhook,
                        Config.WebhookTitle,
                        Config.WebhookAvatar,
                        "🛒 Weapon Sold",
                        nil,
                        {
                            {
                                color = 3145631,
                                title = "🛒 Weapon Sold",
                                description = table.concat({
                                    "**Character Name:** `" ..
                                    Character.firstName .. " " .. Character.lastName .. "`",
                                    "**Character ID:** `" .. Character.characterId .. "`",
                                    "**Weapon Name:** `" .. weaponDetails.weapon_label .. "`",
                                    "**Weapon ID:** `" .. params.weaponName .. "`",
                                    "**Quantity:** `" .. params.quantity .. "`",
                                    "**Total Cost:** `" .. params.total .. "`",
                                    "**Shop Name:** `" .. shopName .. "`"
                                }, "\n")
                            }
                        }
                    )
                end)
        else
            Character.CreditWallet(0, params.total)
            MySQL.Async.execute(
                'UPDATE bcc_shop_weapon_items SET sell_quantity = sell_quantity - ? WHERE shop_id = ? AND weapon_name = ?',
                {
                    params.quantity, shopId, params.weaponName
                })

            NotifyClient(src,
                _U("shop_sold_weapon") ..
                params.quantity .. "x " .. weaponDetails.weapon_label .. _U("formoney") .. params.total,
                "success")

            devPrint("Sending to global webhook: " .. Config.Webhook)
            ShopsToolkit.Discord.sendMessage(
                Config.Webhook,
                Config.WebhookTitle,
                Config.WebhookAvatar,
                "🛒 Weapon Sold",
                nil,
                {
                    {
                        color = 3145631,
                        title = "🛒 Weapon Sold",
                        description = table.concat({
                            "**Character Name:** `" .. Character.firstName .. " " .. Character.lastName .. "`",
                            "**Character ID:** `" .. Character.characterId .. "`",
                            "**Weapon Name:** `" .. weaponDetails.weapon_label .. "`",
                            "**Weapon ID:** `" .. params.weaponName .. "`",
                            "**Quantity:** `" .. params.quantity .. "`",
                            "**Total Cost:** `" .. params.total .. "`",
                            "**Shop Name:** `" .. shopName .. "`"
                        }, "\n")
                    }
                }
            )
        end

        cb(true)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:AddItemNPCShop", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName      = params.shopName
    local itemLabel     = params.itemLabel
    local itemName      = params.itemName
    local quantity      = params.quantity
    local buyPrice      = params.buyPrice
    local sellPrice     = params.sellPrice
    local categoryId    = tonumber(params.category_id)
    local levelRequired = params.levelRequired

    if not categoryId or categoryId <= 0 then
        devPrint("[ERROR] Invalid category_id: " .. tostring(params.category_id))
        NotifyClient(src, _U('categoryRequired') or "Please select a category", "error")
        return cb(false)
    end

    -- Optional: Validate if category exists
    local catCheck = MySQL.scalar.await(
        'SELECT 1 FROM bcc_shop_categories WHERE id = ?',
        { categoryId }
    )

    if not catCheck then
        devPrint("[ERROR] Category ID not found in database: " .. categoryId)
        NotifyClient(src, _U('categoryRequired') or "Please select a category", "error")
        return cb(false)
    end

    local shopResult = MySQL.query.await(
        'SELECT shop_id FROM bcc_shops WHERE shop_name = ?',
        { shopName }
    )
    if not shopResult or #shopResult == 0 then
        devPrint("[ERROR] Shop not found: " .. tostring(shopName))
        return cb(false)
    end

    local shop_id = shopResult[1].shop_id

    local existingItem = MySQL.query.await(
        'SELECT item_id FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?',
        { shop_id, itemName }
    )

    if existingItem and #existingItem > 0 then
        local item_id = existingItem[1].item_id

        local rows = MySQL.update.await(
            'UPDATE bcc_shop_items SET buy_quantity = buy_quantity + ?, sell_quantity = sell_quantity + ? WHERE item_id = ?',
            { quantity, quantity, item_id }
        )

        if rows > 0 then
            devPrint("[UPDATE] Updated item '" .. itemName .. "' in shop_id " .. shop_id .. " (+" .. quantity .. ")")
            return cb(true)
        else
            devPrint("[ERROR] Failed to update item quantity for item_id: " .. item_id)
            return cb(false)
        end
    else
        local insertId = MySQL.insert.await([[
            INSERT INTO bcc_shop_items
                (shop_id, item_label, item_name, currency_type, buy_price, sell_price, category_id, level_required, is_weapon, buy_quantity, sell_quantity)
            VALUES
                (?, ?, ?, 'cash', ?, ?, ?, ?, 0, ?, ?)
        ]], {
            shop_id, itemLabel, itemName, buyPrice, sellPrice, categoryId, levelRequired, quantity, quantity
        })

        if insertId then
            local catLog = categoryId or "NULL"
            devPrint("[INSERT] Added item '" .. itemName .. "' to shop_id " .. shop_id .. " with category_id " .. catLog)
            return cb(true)
        else
            devPrint("[ERROR] Failed to insert new item: " .. itemName)
            return cb(false)
        end
    end
end)

exports['feather-core']:RegisterRPC("bcc-shops:AddBuyItem", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopName = params.shopName
    local itemLabel = params.itemLabel
    local itemName = params.itemName
    local quantity = tonumber(params.quantity)
    local buyPrice = tonumber(params.buyPrice)
    local categoryId = tonumber(params.category_id)
    if not categoryId or categoryId <= 0 then
        NotifyClient(source, _U('categoryRequired') or "Please select a category", "error")
        return cb(false)
    end
    local levelRequired = tonumber(params.levelRequired) or 0
    local currencyType = "cash"
    local sellPrice = 0
    local isWeapon = 0

    devPrint("Request to add item to player store: " .. tostring(shopName))
    if not itemName or itemName == "" or quantity <= 0 then
        devPrint("Invalid itemName or quantity")
        return cb(false)
    end

    local shopResult = MySQL.query.await(
        'SELECT shop_id, webhook_link FROM bcc_shops WHERE shop_name = ? AND owner_id IS NOT NULL', { shopName })
    if not shopResult or not shopResult[1] then
        NotifyClient(source, "Player shop not found", "warning")
        return cb(false)
    end

    local shopId = shopResult[1].shop_id
    local webhook = shopResult[1].webhook_link

    local user = ShopsCore.GetCharacterContext(source)
    local character = user.character
    local charId = character.characterId
    local firstName = character.firstName

    ShopsInventory:getItem(source, itemName, function(playerItem)
        if playerItem and playerItem.count >= quantity then
            local hasDurability = playerItem.usages
                or playerItem.durability
                or (playerItem.metadata and (playerItem.metadata.usages or playerItem.metadata.durability))
            if hasDurability then
                NotifyClient(source, "Cannot add items with durability/usages to shops", "error")
                return cb(false)
            end

            devPrint("Player has enough items")

            isWeapon = playerItem.is_weapon or 0

            local existingItem = MySQL.query.await(
                'SELECT item_id FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?', {
                    shopId, itemName
                })

            if existingItem and existingItem[1] then
                local rowsChanged = MySQL.update.await(
                    'UPDATE bcc_shop_items SET buy_quantity = buy_quantity + ?, buy_price = ?, category_id = ?, level_required = ? WHERE item_id = ?',
                    {
                        quantity, buyPrice, categoryId, levelRequired, existingItem[1].item_id
                    })

                if rowsChanged and rowsChanged > 0 then
                    ShopsInventory:subItem(source, itemName, quantity, {}, function(success)
                        if success then
                devPrint("Item quantity updated and removed from inventory")
                NotifyClient(source, "Item quantity updated in shop", "success")

                            -- Send Discord webhook notifications
                            local message = {
                                {
                                    color = 3145631,
                                    title = "🛠️ Item Updated",
                                    description = table.concat({
                                        "**Shop Name:** `" .. shopName .. "`",
                                        "**Item Name:** `" .. itemName .. "`",
                                        "**Quantity Added:** `" .. quantity .. "`",
                                        "**Buy Price:** `" .. buyPrice .. "`",
                                        "**Character ID:** `" .. charId .. "`",
                                        "**Character Name:** `" .. firstName .. "`"
                                    }, "\n")
                                }
                            }

                            if webhook then
                                ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar,
                                    "🛒 Item Updated in Shop", nil, message)
                            end

                            ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar,
                                "🛒 Item Updated in Shop", nil, message)

                            cb(true)
                        else
                            NotifyClient(source, "Failed to remove item from inventory", "error")
                            cb(false)
                        end
                    end)
                else
                    NotifyClient(source, "DB update failed", "error")
                    cb(false)
                end
            else
                local insertSuccess = MySQL.insert.await([[
                    INSERT INTO bcc_shop_items
                    (shop_id, item_label, item_name, buy_price, sell_price, currency_type, category_id, level_required, is_weapon, buy_quantity, sell_quantity)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]], {
                    shopId, itemLabel, itemName, buyPrice, sellPrice, currencyType, categoryId, levelRequired, isWeapon,
                    quantity, 0
                })

                if insertSuccess then
                    ShopsInventory:subItem(source, itemName, quantity, {}, function(success)
                        if success then
                            devPrint("New item added to shop and removed from inventory")
                            NotifyClient(source, "Item added to shop", "success")

                            -- Send Discord webhook notifications
                            local message = {
                                {
                                    color = 3145631,
                                    title = "🆕 New Item Added",
                                    description = table.concat({
                                        "**Shop Name:** `" .. shopName .. "`",
                                        "**Item Name:** `" .. itemName .. "`",
                                        "**Quantity:** `" .. quantity .. "`",
                                        "**Buy Price:** `" .. buyPrice .. "`",
                                        "**Character ID:** `" .. charId .. "`",
                                        "**Character Name:** `" .. firstName .. "`"
                                    }, "\n")
                                }
                            }

                            if webhook then
                                ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar,
                                    "🛒 New Item Added to Shop", nil, message)
                            end

                            ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar,
                                "🛒 New Item Added to Shop", nil, message)

                            cb(true)
                        else
                            MySQL.update.await('DELETE FROM bcc_shop_items WHERE shop_id = ? AND item_name = ? LIMIT 1',
                                { shopId, itemName })
                            NotifyClient(source, "Failed to remove item from inventory", "error")
                            cb(false)
                        end
                    end)
                else
                    NotifyClient(source, "Failed to add item to shop", "error")
                    cb(false)
                end
            end
        else
            NotifyClient(source, "You don't have enough of this item", "warning")
            cb(false)
        end
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:AddWeaponItem", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName = params.shopName
    local weaponName = params.weaponName
    local weaponLabel = params.weaponLabel
    local buyPrice = tonumber(params.buyPrice)
    local sellPrice = tonumber(params.sellPrice)
    local categoryId = tonumber(params.category)
    local levelRequired = tonumber(params.levelRequired)
    local currencyType = params.currencyType or 'cash'
    local customDesc = params.customDesc or ''
    local weaponInfo = params.weaponInfo or '{}'
    local weaponId = params.weaponId
    local quantity = tonumber(params.quantity) or 1

    if not shopName or not weaponName or not weaponId then
        devPrint("Missing required parameters")
        cb(false)
        return
    end

    if not categoryId or categoryId <= 0 then
        NotifyClient(src, _U('categoryRequired') or "Please select a category", "error")
        cb(false)
        return
    end

    local shopResult = MySQL.query.await('SELECT shop_id, webhook_link, shop_name FROM bcc_shops WHERE shop_name = ?', { shopName })
    if not shopResult or not shopResult[1] then
        devPrint("Shop not found: " .. tostring(shopName))
        cb(false)
        return
    end

    local shopId = shopResult[1].shop_id
    local webhook = shopResult[1].webhook_link or Config.Webhook
    local shopDisplayName = shopResult[1].shop_name or "Unknown"

    -- Check if weapon already exists
    local existing = MySQL.query.await('SELECT weapon_id FROM bcc_shop_weapon_items WHERE shop_id = ? AND weapon_name = ?', {
        shopId, weaponName
    })

    local dbOperationSuccess = false

    if existing and existing[1] then
        -- Update existing quantity
        local rows = MySQL.update.await([[
            UPDATE bcc_shop_weapon_items
            SET buy_quantity = buy_quantity + ?, buy_price = ?, sell_price = ?, category_id = ?, level_required = ?, custom_desc = ?, weapon_info = ?
            WHERE shop_id = ? AND weapon_name = ?
        ]], {
            quantity, buyPrice, sellPrice, categoryId, levelRequired, customDesc, weaponInfo, shopId, weaponName
        })
        dbOperationSuccess = rows and rows > 0
    else
        -- Insert new weapon row
        local insertId = MySQL.insert.await([[
            INSERT INTO bcc_shop_weapon_items
            (shop_id, weapon_name, weapon_label, buy_price, sell_price, category_id, currency_type, level_required, custom_desc, weapon_info, buy_quantity)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            shopId, weaponName, weaponLabel, buyPrice, sellPrice, categoryId, currencyType, levelRequired, customDesc, weaponInfo, quantity
        })
        dbOperationSuccess = insertId and insertId > 0
    end

    if not dbOperationSuccess then
        devPrint("Database insert/update failed.")
        cb(false)
        return
    end

    -- Remove weapon from inventory
    ShopsInventory:subWeapon(src, weaponId, function(success)
        if not success then
            devPrint("Failed to remove weapon from player inventory.")
            cb(false)
            return
        end

        -- Character info for logs
        local user = ShopsCore.GetCharacterContext(src)
        local Character = user and user.character or {}
        local charId = Character.characterId or "unknown"
        local firstName = Character.firstName or "unknown"
        local lastName = Character.lastName or "unknown"

        -- Webhook embed
        local embed = {{
            color = 3145631,
            title = "🔫 Weapon Added/Updated in Shop",
            description = table.concat({
                "**Character Name:** `" .. firstName .. " " .. lastName .. "`",
                "**Character ID:** `" .. charId .. "`",
                "**Weapon:** `" .. weaponLabel .. "` (`" .. weaponName .. "`)",
                "**Buy Price:** `" .. tostring(buyPrice) .. "`",
                "**Sell Price:** `" .. tostring(sellPrice) .. "`",
                "**Quantity:** `" .. quantity .. "`",
                "**Shop:** `" .. shopDisplayName .. "`"
            }, "\n")
        }}

        if webhook then
            ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, "Shop Weapon Update", nil, embed)
        end
        ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, "Shop Weapon Update", nil, embed)

        cb(true)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:AddSellItem", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopName = params.shopName
    local itemLabel = params.itemLabel
    local itemName = params.itemName
    local quantity = tonumber(params.quantity)
    local sellPrice = tonumber(params.sellPrice)
    local categoryId = tonumber(params.category_id)
    if not categoryId or categoryId <= 0 then
        NotifyClient(source, _U('categoryRequired') or "Please select a category", "error")
        return cb(false)
    end
    local levelRequired = tonumber(params.levelRequired) or 0
    local currencyType = "cash"
    local buyPrice = 0
    local isWeapon = 0

    devPrint("Request to add sell item to store: " .. tostring(shopName))
    if not itemName or itemName == "" or quantity <= 0 then
        return cb(false)
    end

    local shopResult = MySQL.query.await(
        'SELECT shop_id, webhook_link FROM bcc_shops WHERE shop_name = ? AND owner_id IS NOT NULL',
        { shopName })

    if not shopResult or not shopResult[1] then
        NotifyClient(source, "Player shop not found", "warning")
        return cb(false)
    end

    local shopId = shopResult[1].shop_id
    local webhook = shopResult[1].webhook_link

    local user = ShopsCore.GetCharacterContext(source)
    local character = user.character
    local charId = character.characterId
    local firstName = character.firstName

    ShopsInventory:getItem(source, itemName, function(playerItem)
        if playerItem then
            local hasDurability = playerItem.usages
                or playerItem.durability
                or (playerItem.metadata and (playerItem.metadata.usages or playerItem.metadata.durability))
            if hasDurability then
                NotifyClient(source, "Cannot add items with durability/usages to shops", "error")
                return cb(false)
            end

            isWeapon = playerItem.is_weapon or 0

            local existingItem = MySQL.query.await(
                'SELECT item_id FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?', {
                    shopId, itemName
                })

            if existingItem and existingItem[1] then
                local rowsChanged = MySQL.update.await([[
                    UPDATE bcc_shop_items
                    SET sell_quantity = sell_quantity + ?, sell_price = ?, category_id = ?, level_required = ?
                    WHERE item_id = ?
                ]], {
                    quantity, sellPrice, categoryId, levelRequired, existingItem[1].item_id
                })

                if rowsChanged and rowsChanged > 0 then
                    NotifyClient(source, "Item updated in store", "success")

                    -- Send Discord webhook notifications
                    local message = {
                        {
                            color = 3145631,
                            title = "🛠️ Item Updated",
                            description = table.concat({
                                "**Shop Name:** `" .. shopName .. "`",
                                "**Item Name:** `" .. itemName .. "`",
                                "**Quantity Added:** `" .. quantity .. "`",
                                "**Sell Price:** `" .. sellPrice .. "`",
                                "**Character ID:** `" .. charId .. "`",
                                "**Character Name:** `" .. firstName .. "`"
                            }, "\n")
                        }
                    }

                    if webhook then
                        ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar,
                            "🛒 Item Updated in Shop", nil, message)
                    end

                    ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar,
                        "🛒 Item Updated in Shop", nil, message)

                    cb(true)
                else
                    NotifyClient(source, "Failed to update item", "error")
                    cb(false)
                end
            else
                local insertSuccess = MySQL.insert.await([[
                    INSERT INTO bcc_shop_items
                    (shop_id, item_label, item_name, buy_price, sell_price, currency_type, category_id, level_required, is_weapon, buy_quantity, sell_quantity)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]], {
                    shopId, itemLabel, itemName, buyPrice, sellPrice, currencyType, categoryId, levelRequired, isWeapon, 0,
                    quantity
                })

                if insertSuccess then
                    NotifyClient(source, "Item added to shop", "success")

                    -- Send Discord webhook notifications
                    local message = {
                        {
                            color = 3145631,
                            title = "🆕 New Item Added",
                            description = table.concat({
                                "**Shop Name:** `" .. shopName .. "`",
                                "**Item Name:** `" .. itemName .. "`",
                                "**Quantity:** `" .. quantity .. "`",
                                "**Sell Price:** `" .. sellPrice .. "`",
                                "**Character ID:** `" .. charId .. "`",
                                "**Character Name:** `" .. firstName .. "`"
                            }, "\n")
                        }
                    }

                    if webhook then
                        ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar,
                            "🛒 New Item Added to Shop", nil, message)
                    end

                    ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar,
                        "🛒 New Item Added to Shop", nil, message)

                    cb(true)
                else
                    NotifyClient(source, "Failed to insert item", "error")
                    cb(false)
                end
            end
        else
            NotifyClient(source, "Item not found in inventory", "warning")
            cb(false)
        end
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:EditItemNPCShop", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName      = params.shopName
    local itemName      = params.itemName
    local itemLabel     = params.itemLabel
    local buyPrice      = params.buyPrice
    local sellPrice     = params.sellPrice
    local category      = params.category
    local levelRequired = params.levelRequired
    local buyQuantity   = params.buy_quantity
    local sellQuantity  = params.sell_quantity

    if not shopName or not itemName then
        devPrint("Missing required parameters")
        cb(false)
        return
    end

    MySQL.query("SELECT shop_id FROM bcc_shops WHERE shop_name = ?", { shopName }, function(shopResults)
        if not shopResults or #shopResults == 0 then
            devPrint("Shop not found: " .. tostring(shopName))
            cb(false)
            return
        end

        local shopId = shopResults[1].shop_id

        MySQL.update([[
            UPDATE bcc_shop_items
            SET item_label = ?, buy_price = ?, sell_price = ?, category_id = ?,
                level_required = ?, buy_quantity = ?, sell_quantity = ?
            WHERE shop_id = ? AND item_name = ?
        ]], {
            itemLabel,
            buyPrice,
            sellPrice,
            category,
            levelRequired,
            buyQuantity,
            sellQuantity,
            shopId,
            itemName
        }, function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                cb(true)
            else
                devPrint("No rows updated for item: " .. tostring(itemName))
                cb(false)
            end
        end)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:EditItemNPCWeapon", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName      = params.shopName
    local weaponName    = params.weaponName
    local weaponLabel   = params.weaponLabel
    local buyPrice      = params.buyPrice
    local sellPrice     = params.sellPrice
    local category      = params.category
    local levelRequired = params.levelRequired
    local buyQty  = tonumber(params.buy_quantity)
    local sellQty = tonumber(params.sell_quantity)

    if not shopName or not weaponName then
        devPrint("Missing required parameters")
        cb(false)
        return
    end

    MySQL.query('SELECT shop_id FROM bcc_shops WHERE shop_name = ?', { shopName }, function(shopResults)
        if not shopResults or #shopResults == 0 then
            devPrint("Shop not found: " .. tostring(shopName))
            cb(false)
            return
        end

        local shopId = shopResults[1].shop_id

        MySQL.update([[
            UPDATE bcc_shop_weapon_items
            SET
                weapon_label   = ?,
                buy_price      = ?,
                sell_price     = ?,
                category       = ?,
                level_required = ?,
                buy_quantity   = COALESCE(?, buy_quantity),
                sell_quantity  = COALESCE(?, sell_quantity)
            WHERE shop_id = ? AND weapon_name = ?
        ]], {
            weaponLabel,
            buyPrice,
            sellPrice,
            category,
            levelRequired,
            buyQty,
            sellQty,
            shopId,
            weaponName
        }, function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                cb(true)
            else
                devPrint("Failed to update weapon item.")
                cb(false)
            end
        end)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:EditItemPlayerShop", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName      = params.shopName
    local itemName      = params.itemName
    local itemLabel     = params.itemLabel
    local buyPrice      = params.buyPrice
    local sellPrice     = params.sellPrice
    local category      = params.category
    local levelRequired = params.levelRequired
    local sellQuantity  = tonumber(params.sell_quantity)

    if not shopName or not itemName then
        devPrint("[ERROR] shopName or itemName missing")
        cb(false)
        return
    end

    MySQL.query("SELECT shop_id FROM bcc_shops WHERE shop_name = ?", { shopName }, function(shopResults)
        if not shopResults or #shopResults == 0 then
            devPrint("[ERROR] Shop not found.")
            cb(false)
            return
        end

        local shopId = shopResults[1].shop_id

        -- Ensure item exists; only update (no insert, no buy_quantity changes)
        MySQL.query("SELECT item_id FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?", {
            shopId, itemName
        }, function(itemResults)
            if not itemResults or not itemResults[1] then
                cb(false, "Item not found in this shop.")
                return
            end

            local itemId = itemResults[1].item_id

            MySQL.update([[
                UPDATE bcc_shop_items
                SET item_label = ?, buy_price = ?, sell_price = ?, category_id = ?,
                    level_required = ?, sell_quantity = ?
                WHERE item_id = ?
            ]], {
                itemLabel,
                buyPrice,
                sellPrice,
                category,
                levelRequired,
                sellQuantity,
                itemId
            }, function(rowsChanged)
                if rowsChanged and rowsChanged > 0 then
                    cb(true)
                else
                    devPrint("[ERROR] Item not updated.")
                    cb(false)
                end
            end)
        end)
    end)
end)

-- Edit ITEM in a player shop (no buy_quantity updates)
exports['feather-core']:RegisterRPC("bcc-shops:EditItemPlayerShop", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName      = params.shopName
    local itemName      = params.itemName
    local itemLabel     = params.itemLabel
    local buyPrice      = params.buyPrice
    local sellPrice     = params.sellPrice
    local category      = params.category
    local levelRequired = params.levelRequired
    local sellQuantity  = tonumber(params.sell_quantity)

    if not shopName or not itemName then
        devPrint("[ERROR] shopName or itemName missing")
        cb(false)
        return
    end

    MySQL.query("SELECT shop_id FROM bcc_shops WHERE shop_name = ?", { shopName }, function(shopResults)
        if not shopResults or #shopResults == 0 then
            devPrint("[ERROR] Shop not found.")
            cb(false)
            return
        end

        local shopId = shopResults[1].shop_id

        -- Ensure item exists; only update (no insert, no buy_quantity changes)
        MySQL.query("SELECT item_id FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?", {
            shopId, itemName
        }, function(itemResults)
            if not itemResults or not itemResults[1] then
                cb(false, "Item not found in this shop.")
                return
            end

            local itemId = itemResults[1].item_id

            MySQL.update([[
                UPDATE bcc_shop_items
                SET item_label = ?, buy_price = ?, sell_price = ?, category_id = ?,
                    level_required = ?, sell_quantity = ?
                WHERE item_id = ?
            ]], {
                itemLabel,
                buyPrice,
                sellPrice,
                category,
                levelRequired,
                sellQuantity,
                itemId
            }, function(rowsChanged)
                if rowsChanged and rowsChanged > 0 then
                    cb(true)
                else
                    devPrint("[ERROR] Item not updated.")
                    cb(false)
                end
            end)
        end)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:RemoveShopItem", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopName = params.shopName
    local itemName = params.itemName
    local quantity = params.quantity
    local isBuy = params.isBuy

    devPrint("[RemoveShopItem] Request from source " ..
        source ..
        ": shop=" .. shopName .. ", item=" .. itemName .. ", quantity=" .. quantity .. ", isBuy=" .. tostring(isBuy))

    local user = ShopsCore.GetCharacterContext(source)
    if not user then
        devPrint("[RemoveShopItem] Invalid user")
        NotifyClient(source, "Invalid user.", "error")
        return cb(nil)
    end

    local shopQuery = MySQL.query.await('SELECT shop_id FROM bcc_shops WHERE shop_name = ?', { shopName })
    if not shopQuery or #shopQuery == 0 then
        devPrint("[RemoveShopItem] Shop not found: " .. shopName)
        NotifyClient(source, "Shop not found.", "error")
        return cb(nil)
    end

    local shop_id = shopQuery[1].shop_id
    local quantityColumn = isBuy and 'buy_quantity' or 'sell_quantity'
    devPrint("[RemoveShopItem] Found shop_id=" .. shop_id .. ", using column=" .. quantityColumn)

    local quantityQuery = MySQL.query.await(
        'SELECT ' .. quantityColumn .. ' FROM bcc_shop_items WHERE shop_id = ? AND item_name = ?',
        { shop_id, itemName }
    )

    if not quantityQuery or #quantityQuery == 0 then
        devPrint("[RemoveShopItem] Item not found in shop: " .. itemName)
        NotifyClient(source, "Item not found in shop.", "error")
        return cb(nil)
    end

    local currentQty = quantityQuery[1][quantityColumn]
    devPrint("[RemoveShopItem] Current quantity in shop: " .. currentQty)

    if currentQty < quantity then
        devPrint("[RemoveShopItem] Not enough items. Requested: " .. quantity .. ", Available: " .. currentQty)
        NotifyClient(source, "Not enough items in shop.", "warning")
        return cb(nil)
    end

    -- Check canCarry BEFORE updating database
    if isBuy then
        devPrint("[RemoveShopItem] Checking if player can carry: " .. itemName .. " x" .. quantity)
        local canCarry = ShopsInventory:canCarryItem(source, itemName, quantity)
        if not canCarry then
            devPrint("[RemoveShopItem] Cannot carry item: " .. itemName)
            NotifyClient(source, _U('StackFull') .. ": " .. itemName, "warning")
            return cb(nil)
        end
    end

    -- Now proceed with the update
    local updateResult = MySQL.update.await(
        'UPDATE bcc_shop_items SET ' ..
        quantityColumn .. ' = ' .. quantityColumn .. ' - ? WHERE shop_id = ? AND item_name = ?',
        { quantity, shop_id, itemName }
    )

    if updateResult and updateResult > 0 then
        devPrint("[RemoveShopItem] Updated quantity in DB")

        if isBuy then
            ShopsInventory:addItem(source, itemName, quantity)
            devPrint("[RemoveShopItem] Item added to inventory: " .. itemName .. " x" .. quantity)
        end

        return cb(true)
    else
        devPrint("[RemoveShopItem] Failed to update item quantity in DB")
        return cb(nil)
    end
end)

exports['feather-core']:RegisterRPC("bcc-shops:CleanupEmptyItems", function(_, cb, source)
    local _U = ShopTranslator(source)
    local deleted = MySQL.update.await(
        [[DELETE FROM bcc_shop_items
          WHERE buy_quantity = 0 AND sell_quantity = 0]])

    if deleted and deleted > 0 then
        devPrint(" Deleted " .. deleted .. " item(s) from shop_items table.")
        NotifyClient(source, "Cleaned up " .. deleted .. " empty item(s)", "success")
        return cb(true)
    else
        devPrint("No empty items found for deletion.")
        NotifyClient(source, "No items needed deletion.", "info")
        return cb(false)
    end
end)

-- Background thread that runs every 60 seconds
CreateThread(function()
    while true do
        Wait(120000) -- 2 min
        
        local deleted = MySQL.update.await(
            [[DELETE FROM bcc_shop_items
              WHERE buy_quantity = 0 AND sell_quantity = 0]])

        if deleted and deleted > 0 then
            devPrint("[AutoCleanup] Deleted " .. deleted .. " empty shop item(s).")
        end
    end
end)
