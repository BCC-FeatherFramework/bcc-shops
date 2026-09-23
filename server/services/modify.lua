-- Existing BCC RPC names and presentation; payment state is owned by ShopsPayments.
exports['feather-core']:RegisterRPC("bcc-shops:PurchaseItem", function(params, cb, src)
    local _U = ShopTranslator(src)
    local paid = ShopsPayments.Purchase(params, src, false)
    if not paid.ok then
        ShopsPayments.NotifyFailure(src, paid)
        return cb(false, { code = paid.code })
    end
    if paid.value.replayed then return cb(true, paid.value) end
    local context = ShopsCore.GetCharacterContext(src)
    if not context then return cb(true, paid.value) end
    local Character = context.character
    local shopId = paid.value.shopId
    local itemDetails = { item_label = paid.value.label }
    params = { itemName = paid.value.itemName, quantity = paid.value.quantity, total = paid.value.total }
    NotifyClient(src,
        _U("shop_bought_item") .. params.quantity .. "x " .. itemDetails.item_label .. _U(paid.value.currency == "gold" and "forgold" or "formoney") .. params
        .total,
        "success")

    local shopResult = MySQL.query.await(
        'SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?',
        { shopId }
    )
    local shopInfo = shopResult and shopResult[1] or nil

    if not shopInfo then
        devPrint("shopInfo is nil for shopId:", shopId)
        return cb(true, paid.value)
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
            "**Total Cost:** `" .. params.total .. " " .. paid.value.currency .. "`",
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

    cb(true, paid.value)
end)

exports['feather-core']:RegisterRPC("bcc-shops:PurchaseWeapon", function(params, cb, src)
    local _U = ShopTranslator(src)
    local paid = ShopsPayments.Purchase(params, src, true)
    if not paid.ok then
        ShopsPayments.NotifyFailure(src, paid)
        return cb(false, { code = paid.code })
    end
    if paid.value.replayed then return cb(true, paid.value) end
    local context = ShopsCore.GetCharacterContext(src)
    if not context then return cb(true, paid.value) end
    local Character = context.character
    local shopId, weaponName = paid.value.shopId, paid.value.itemName
    local shopName = params.shopName
    local weaponDetails = { label = paid.value.label }
    params = { quantity = paid.value.quantity, total = paid.value.total }
    NotifyClient(src,
        _U("shop_bought_weapon") .. params.quantity .. "x " .. weaponDetails.label .. _U(paid.value.currency == "gold" and "forgold" or "formoney") .. params.total,
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
            "**Total Cost:** `" .. params.total .. " " .. paid.value.currency .. "`",
            "**Shop Name:** `" .. finalShopName .. "`"
        }, "\n")
    }

    devPrint("[PurchaseWeapon] Sending to shop-specific webhook:", webhook)
    ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, message.title, nil, { message })

    devPrint("[PurchaseWeapon] Sending to global webhook:", Config.Webhook)
    ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, message.title, nil,
        { message })

    cb(true, paid.value)
end)

-- Economy currently cannot fund merchant payouts or independent shop accounts.
-- Reject before removing inventory/stock. Client-triggered NPC purchases must
-- never mint shop funds; only a future funded server workflow can perform them.
local function unavailableShopFunds(_, cb, src)
    local result = ShopsPayments.ShopFundsUnavailable()
    ShopsPayments.NotifyFailure(src, result)
    cb(false, { code = result.code })
end
exports['feather-core']:RegisterRPC("bcc-shops:SellItem", unavailableShopFunds)
exports['feather-core']:RegisterRPC("bcc-shops:SellWeapon", unavailableShopFunds)
exports['feather-core']:RegisterRPC("bcc-shops:PurchaseItemNPC", unavailableShopFunds)
exports['feather-core']:RegisterRPC("bcc-shops:PurchaseWeaponNPC", unavailableShopFunds)

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
          WHERE buy_quantity = 0 AND sell_quantity = 0
            AND NOT EXISTS (SELECT 1 FROM bcc_shop_payments p
                WHERE p.stock_id = bcc_shop_items.item_id AND p.is_weapon = 0
                  AND p.state NOT IN ('fulfilled', 'rejected'))]])

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
              WHERE buy_quantity = 0 AND sell_quantity = 0
            AND NOT EXISTS (SELECT 1 FROM bcc_shop_payments p
                WHERE p.stock_id = bcc_shop_items.item_id AND p.is_weapon = 0
                  AND p.state NOT IN ('fulfilled', 'rejected'))]])

        if deleted and deleted > 0 then
            devPrint("[AutoCleanup] Deleted " .. deleted .. " empty shop item(s).")
        end
    end
end)
