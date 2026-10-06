exports['feather-core']:RegisterRPC("bcc-shops:FetchNPCInventory", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName = params.shopName
    devPrint("[RPC:Server] FetchInventory called by source " .. tostring(src) .. " for shop: " .. tostring(shopName))

    local inventory = ShopsInventory:GetCharacterItems(src)
    devPrint("[RPC:Server] Retrieved inventory with " .. tostring(#inventory or 0) .. " items.")

    cb({
        inventory = inventory,
        shopName = shopName
    })
end)

function FetchAllPlayerShops()
    local result = DB.query('SELECT shop_name, pos_x, pos_y, pos_z FROM bcc_shops WHERE is_npc_shop = 0')
    return result or {}
end

exports['feather-core']:RegisterRPC("bcc-shops:GetAllPlayerShops", function(_, cb)
    devPrint("📡 RPC called: bcc-shops:GetAllPlayerShops")
    local shops = FetchAllPlayerShops()

    if #shops > 0 then
        devPrint("Found " .. #shops .. " player-owned shops in database")
        for i, shop in ipairs(shops) do
            devPrint(("🏪 [%d] %s at (%.2f, %.2f, %.2f)"):format(i, shop.shop_name, shop.pos_x, shop.pos_y, shop.pos_z))
        end
    else
        devPrint(" No player-owned shops found in database")
    end

    cb(shops)
end)

exports['feather-core']:RegisterRPC("bcc-shops:fetchPlayerInventory", function(params, cb, source)
    local _U = ShopTranslator(source)
    local result = {
        inventory = {},
        weapons = {},
        shopName = params.shopName
    }

    devPrint("[fetchPlayerInventory] Fetching inventory for source: " .. tostring(source))

    ShopsInventory:GetCharacterItems(source, function(inventory)
        devPrint("[fetchPlayerInventory] Inventory items fetched: " .. json.encode(inventory))

        for _, item in ipairs(inventory) do
            item.item_name = item.name -- Normalize
        end

        result.inventory = inventory

        ShopsInventory:GetCharacterWeapons(source, function(weapons)
            devPrint("[fetchPlayerInventory] Inventory weapons fetched: " .. json.encode(weapons))

            for _, weapon in ipairs(weapons) do
                weapon.item_name = weapon.name -- Normalize
            end

            result.weapons = weapons

            devPrint("[fetchPlayerInventory] Final result: " .. json.encode(result))
            cb(result)
        end)
    end)
end)

exports['feather-core']:RegisterRPC("bcc-shops:fetchPlayerStoreInfo", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName = params.shopName
    local user = ShopsCore.GetCharacterContext(src)
    local character = user and user.character

    if not character then
        devPrint("Character not found for source " .. tostring(src))
        return cb(false)
    end

    local charId = character.characterId

    local storeResult = DB.query(
        'SELECT shop_id, inv_limit, ledger, owner_id FROM bcc_shops WHERE shop_name = ?',
            shopName
        )

    if not storeResult or #storeResult == 0 then
        devPrint("No store found with shop name: " .. tostring(shopName))
        NotifyClient(src, 'Shop not found', "warning", 4000)
        return cb(false)
    end

    local storeInfo = storeResult[1]
    local shopId = storeInfo.shop_id
    local isOwner = storeInfo.owner_id == charId

    devPrint("Store info fetched: " .. json.encode(storeInfo))
    devPrint("Is player owner: " .. tostring(isOwner))

    if isOwner then
        return cb({
            shopId = shopId,
            shopName = shopName,
            invLimit = storeInfo.inv_limit,
            ledger = storeInfo.ledger,
            isOwner = true,
            hasAccess = true
        })
    end

    local accessResult = DB.query('SELECT 1 FROM bcc_shop_access WHERE shop_id = ? AND character_id = ?',
        shopId, tostring(charId)
    )

    local hasAccess = accessResult and #accessResult > 0
    devPrint("Access check result for charId " .. tostring(charId) .. ": " .. tostring(hasAccess))

    cb({
        shopId = shopId,
        shopName = shopName,
        invLimit = storeInfo.inv_limit,
        ledger = storeInfo.ledger,
        isOwner = false,
        hasAccess = hasAccess
    })
end)

exports['feather-core']:RegisterRPC("bcc-shops:FetchShopItems", function(params, cb, source)
    local _U = ShopTranslator(source)
    if not params or not params.shopName then
        devPrint("Missing shopName param")
        return cb({ items = {}, weapons = {}, shopName = "unknown" })
    end

    local shopName = params.shopName

    -- Step 1: Fetch Shop ID
    local shopId = DB.value('SELECT shop_id FROM bcc_shops WHERE shop_name = ?', shopName)
    if not shopId then
        devPrint("Shop not found: " .. tostring(shopName))
        return cb({ items = {}, weapons = {}, shopName = shopName })
    end

    local result = {
        shopName = shopName,
        items = {},
        weapons = {}
    }

    -- Step 2: Fetch Items with category name from join
    local itemRows = DB.query([[
        SELECT i.item_id, i.item_label, i.item_name, i.currency_type,
               i.buy_price, i.sell_price, i.level_required,
               i.item_quantity, i.buy_quantity, i.sell_quantity,
               c.name AS category_name, c.label AS category_label
        FROM bcc_shop_items i
        LEFT JOIN bcc_shop_categories c ON i.category_id = c.id
        WHERE i.shop_id = ?
    ]], shopId)

    for _, item in ipairs(itemRows or {}) do
        local category = item.category_name or "uncategorized"
        result.items[category] = result.items[category] or {}
        table.insert(result.items[category], {
            id            = item.item_id,
            label         = item.item_label,
            name          = item.item_name,
            category      = category,
            category_label = item.category_label or category,
            currency_type = item.currency_type,
            price         = item.buy_price,
            sell_price    = item.sell_price,
            level         = item.level_required,
            item_quantity = item.item_quantity,
            buy_quantity  = item.buy_quantity,
            sell_quantity = item.sell_quantity
        })
    end

    -- Step 3: Fetch Weapons with category name from join
    local weaponRows = DB.query([[
        SELECT w.weapon_id, w.weapon_label, w.weapon_name, w.currency_type,
               w.buy_price, w.sell_price, w.level_required,
               w.item_quantity, w.buy_quantity, w.sell_quantity,
               w.custom_desc, w.weapon_info,
               c.name AS category_name, c.label AS category_label
        FROM bcc_shop_weapon_items w
        LEFT JOIN bcc_shop_categories c ON w.category_id = c.id
        WHERE w.shop_id = ?
    ]], shopId)

    for _, weapon in ipairs(weaponRows or {}) do
        local category = weapon.category_name or "uncategorized"
        result.weapons[category] = result.weapons[category] or {}
        table.insert(result.weapons[category], {
            id            = weapon.weapon_id,
            label         = weapon.weapon_label,
            name          = weapon.weapon_name,
            category      = category,
            category_label = weapon.category_label or category,
            currency_type = weapon.currency_type,
            price         = weapon.buy_price,
            sell_price    = weapon.sell_price,
            level         = weapon.level_required,
            item_quantity = weapon.item_quantity,
            buy_quantity  = weapon.buy_quantity,
            sell_quantity = weapon.sell_quantity,
            description   = weapon.custom_desc,
            weapon_info   = weapon.weapon_info
        })
    end

    devPrint(string.format("%d items and %d weapons fetched for shop '%s'", #itemRows, #weaponRows, shopName))

    cb(result)
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetShopCategories", function(_, cb)
    local result = DB.query([[
        SELECT id, name, label FROM bcc_shop_categories ORDER BY label ASC
    ]])

    local categories = {}
    for _, row in ipairs(result or {}) do
        local display = (row.label and row.label ~= "" and row.label) or row.name
        table.insert(categories, {
            text = display,
            value = tostring(row.id) -- send id as string for dropdown consistency
        })
    end

    cb(categories)
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetShopItems", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName = params.shopName

    local rows = DB.query('SELECT shop_id FROM bcc_shops WHERE shop_name = ?', shopName)
    if not rows or not rows[1] then
        devPrint("Shop not found: " .. tostring(shopName))
        return cb({ items = {}, weapons = {} })
    end

    local shopId = rows[1].shop_id
    local result = {
        items = {},
        weapons = {}
    }

    -- Fetch Items
    local itemRows = DB.query([[
        SELECT i.item_id, i.item_label, i.item_name, i.currency_type,
               i.buy_price, i.sell_price, i.level_required,
               i.item_quantity, i.buy_quantity, i.sell_quantity,
               i.category_id, c.label AS category_label
        FROM bcc_shop_items i
        LEFT JOIN bcc_shop_categories c ON i.category_id = c.id
        WHERE i.shop_id = ?
    ]], shopId)

    for _, row in ipairs(itemRows or {}) do
        local categoryId = row.category_id or 0
        local catLabel = (row.category_label and row.category_label ~= "" and row.category_label) or row.category_name or _U("shop_no_category")
        result.items[categoryId] = result.items[categoryId] or { _label = catLabel }
        table.insert(result.items[categoryId], {
            id            = row.item_id,
            label         = row.item_label,
            name          = row.item_name,
            currency_type = row.currency_type,
            price         = row.buy_price,
            sell_price    = row.sell_price,
            level         = row.level_required,
            item_quantity = row.item_quantity,
            buy_quantity  = row.buy_quantity,
            sell_quantity = row.sell_quantity,
        })
    end

    -- Fetch Weapons
    local weaponRows = DB.query([[
        SELECT w.weapon_id, w.weapon_label, w.weapon_name, w.currency_type,
               w.buy_price, w.sell_price, w.level_required,
               w.item_quantity, w.buy_quantity, w.sell_quantity,
               w.custom_desc, w.weapon_info,
               w.category_id, c.label AS category_label
        FROM bcc_shop_weapon_items w
        LEFT JOIN bcc_shop_categories c ON w.category_id = c.id
        WHERE w.shop_id = ?
    ]], shopId)

    for _, row in ipairs(weaponRows or {}) do
        local categoryId = row.category_id or 0
        local catLabel = (row.category_label and row.category_label ~= "" and row.category_label) or row.category_name or _U("shop_no_category")
        result.weapons[categoryId] = result.weapons[categoryId] or { _label = catLabel }
        table.insert(result.weapons[categoryId], {
            id            = row.weapon_id,
            label         = row.weapon_label,
            name          = row.weapon_name,
            currency_type = row.currency_type,
            price         = row.buy_price,
            sell_price    = row.sell_price,
            level         = row.level_required,
            item_quantity = row.item_quantity,
            buy_quantity  = row.buy_quantity,
            sell_quantity = row.sell_quantity,
            description   = row.custom_desc,
            weapon_info   = row.weapon_info,
        })
    end

    cb(result)
end)

exports['feather-core']:RegisterRPC("bcc-shops:FetchPlayerShops", function(_, cb, src)
    local _U = ShopTranslator(src)
    local query = 'SELECT * FROM bcc_shops WHERE owner_id IS NOT NULL'
    local result = DB.query(query)

    if result and #result > 0 then
        for _, store in ipairs(result) do
            -- devPrint("['DEBUG'] - Fetched Player Store: " .. json.encode(store, { indent = true }))
        end
    else
        devPrint("No player-owned stores found.")
    end

    cb(result or {})
end)

exports['feather-core']:RegisterRPC("bcc-shops:FetchNPCShops", function(_, cb, src)
    local _U = ShopTranslator(src)
    local query = 'SELECT * FROM bcc_shops WHERE is_npc_shop = 1'
    local result = DB.query(query)

    if result and #result > 0 then
        for _, shop in ipairs(result) do
            -- devPrint("['DEBUG'] - Fetched NPC Store: " .. json.encode(shop, { indent = true }))
        end
    else
        devPrint("No NPC shops found.")
    end

    cb(result or {})
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetAccessList", function(params, cb, source)
    local _U = ShopTranslator(source)
    local shopName = params.shopName
    if not shopName then return cb(nil) end

    local shopResult = DB.query("SELECT shop_id FROM bcc_shops WHERE shop_name = ?", shopName)
    if not shopResult or not shopResult[1] then
        return cb(nil)
    end

    local shopId = shopResult[1].shop_id
    local accessList = DB.query("SELECT character_id FROM bcc_shop_access WHERE shop_id = ?", shopId)

    local results = {}

    for _, entry in pairs(accessList) do
        for _, playerSrc in ipairs(GetPlayers()) do
            local user = ShopsCore.GetCharacterContext(tonumber(playerSrc))
            if user then
                local character = user.character
                if character and tostring(character.characterId) == tostring(entry.character_id) then
                    table.insert(results, {
                        character_id = character.characterId,
                        firstname = character.firstName,
                        lastname = character.lastName
                    })
                end
            end
        end
    end

    cb(results)
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetItemCount", function(params, cb, src)
    local _U = ShopTranslator(src)
    local itemName = params.item
    local percentage = params.percentage or 100
    local metadata = params.metadata or {}

    if not itemName then
        devPrint("Missing item name from client request.")
        return cb(0)
    end

    devPrint("Checking item count for player " ..
        src .. " | Item: " .. itemName .. " | Percentage ≥ " .. percentage)

    ShopsInventory:getItemCount(src, function(count)
        devPrint("Player has " .. (count or 0) .. " of item '" .. itemName .. "'")
        cb(count or 0)
    end, itemName, metadata, percentage)
end)

exports['feather-core']:RegisterRPC("bcc-shops:GetItemsForShop", function(data, cb, src)
    local _U = ShopTranslator(src)
    local shopName = data and data.shopName
    if not shopName then
        return cb(false, "[ERROR] Shop name is required.")
    end

    local shopResults = DB.query("SELECT shop_id FROM bcc_shops WHERE shop_name = ?", shopName)
    if not shopResults or #shopResults == 0 then
        return cb(false, "Shop not found.")
    end

    local shopId = shopResults[1].shop_id

    -- Fetch items
    local itemResults = DB.query("SELECT * FROM bcc_shop_items WHERE shop_id = ?", shopId) or {}

    -- Fetch weapons
    local weaponResults = DB.query("SELECT * FROM bcc_shop_weapon_items WHERE shop_id = ?", shopId) or {}

    local combined = {}

                -- Push items as-is + is_weapon = 0
                for _, it in ipairs(itemResults) do
                    it.is_weapon = 0
                    -- ensure item_* fields exist (some schemas use different names)
                    it.item_name       = it.item_name or it.name
                    it.item_label      = it.item_label or it.label
                    it.category        = it.category or it.category_id  -- keep both for legacy code
                    it.category_id     = it.category_id or it.category
                    it.level_required  = it.level_required or it.level
                    it.buy_quantity    = it.buy_quantity or 0
                    it.sell_quantity   = it.sell_quantity or 0
                    table.insert(combined, it)
                end

                -- Map weapons to item-like fields + is_weapon = 1
                for _, w in ipairs(weaponResults) do
                    table.insert(combined, {
                        -- normalized (so client code that expects item_* works)
                        is_weapon      = 1,
                        item_name      = w.weapon_name,
                        item_label     = w.weapon_label,
                        buy_price      = w.buy_price,
                        sell_price     = w.sell_price,
                        category       = w.category or w.category_id,
                        category_id    = w.category_id or w.category,
                        level_required = w.level_required,
                        buy_quantity   = w.buy_quantity or 0,
                        sell_quantity  = w.sell_quantity or 0,

                        -- keep original weapon fields too (for edit weapon page)
                        weapon_name    = w.weapon_name,
                        weapon_label   = w.weapon_label,
                        custom_desc    = w.custom_desc,
                        weapon_info    = w.weapon_info,
                        weapon_id      = w.weapon_id,

                        -- optional: for debugging
                        _source_table  = "bcc_shop_weapon_items",
                    })
                end

    if #combined == 0 then
        NotifyClient(src, _U("shop_no_items_found"), "warning", 4000)
        return cb(false, "No items or weapons found.")
    end

    cb(true, combined)
end)

exports['feather-core']:RegisterRPC("bcc-shops:FetchWeaponItems", function(params, cb, src)
    local _U = ShopTranslator(src)
    local shopName = params.shopName

    if not shopName then
        cb(false, "Shop name is missing")
        return
    end

    local shopResults = DB.query('SELECT shop_id FROM bcc_shops WHERE shop_name = ?', shopName)
    if not shopResults or #shopResults == 0 then
        cb(false, "Shop not found.")
        return
    end

    local shopId = shopResults[1].shop_id

    local weaponResults = DB.query('SELECT * FROM bcc_shop_weapon_items WHERE shop_id = ?', shopId)
    if not weaponResults or #weaponResults == 0 then
        cb({})
        return
    end

    cb(weaponResults)
end)
