function BackToMainMenu(shopName)
    local opened = false
    for _, shop in ipairs(globalNearbyShops or {}) do
        if shop.name == shopName then
            if shop.type == "player" then
                OpenPlayerBuySellMenu(shop.name)
                opened = true
                break
            elseif shop.type == "npc" and not opened then
                OpenNPCBuySellMenu(shop.name)
                break
            end
        end
    end
end

function OpenStoreMenu(nearbyShops, filterType)
    if not nearbyShops then
        devPrint("Error: nearbyShops is nil")
        Notify(_U("noNearbyShopsFound"), 4000)
        return
    end

    devPrint("Opening store menu with shops: " .. json.encode(nearbyShops))

    local storePage = BCCShopsMainMenu:RegisterPage('store:main')
    storePage:RegisterElement('header', {
        value = 'Store Menu',
        slot = "header"
    })

    for _, shop in ipairs(nearbyShops) do
        if not filterType or shop.type == filterType then
            storePage:RegisterElement('button', {
                label = shop.name,
                slot = "content"
            }, function()
                if shop.type == "npc" then
                    OpenNPCBuySellMenu(shop.name)
                else
                    OpenPlayerBuySellMenu(shop.name)
                end
            end)
        end
    end

    storePage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })
    storePage:RegisterElement('button', {
        label = _U('storeClose'),
        slot = "footer"
    }, function()
        BCCShopsMainMenu:Close()
    end)
    storePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = storePage })
end

function OpenEditItemMenu(shopName)
    devPrint("Opening Edit Item Menu for store: " .. tostring(shopName))

    exports['feather-core']:CallRPC("bcc-shops:GetItemsForShop", { shopName = shopName }, function(success, result)
        if not success or type(result) ~= "table" then
            Notify(_U("failedToFetchItems"), "error", 4000)
            return
        end

        -- fresh page each time (avoid stale registrations)
        local uniqueId = "playeredit-" .. math.random(1000, 9999)
        local editPage = BCCShopsMainMenu:RegisterPage('bcc-shops:player:edititems:' .. shopName .. ":" .. uniqueId)

        editPage:RegisterElement('header', {
            value = _U('selectItemToEdit'),
            slot = "header"
        })
        editPage:RegisterElement('line', {
            slot = "header",
            style = {}
        })

        local imageBoxItems = {}
        local combinedRows  = {}
        local idx           = 0

        for _, row in ipairs(result or {}) do
            -- Expecting rows to contain either item_* or weapon_* fields plus pricing/stock
            local displayName = row.item_label or row.weapon_label or row.item_name or row.weapon_name or _U('unknown')
            local internal    = (row.item_name or row.weapon_name or "unknown")
            local imgPath     = "nui://feather-inventory/ui/images/items/" .. internal .. ".png"

            idx               = idx + 1
            combinedRows[idx] = row

            table.insert(imageBoxItems, {
                type  = "imagebox",
                index = idx,
                data  = {
                    img      = imgPath,
                    tooltip  = displayName,
                    style    = {
                        margin = "5px"
                    },
                    disabled = false,
                    sound    = {
                        action = "SELECT",
                        soundset = "RDRO_Character_Creator_Sounds"
                    }
                }
            })
        end

        if #imageBoxItems == 0 then
            TextDisplay = editPage:RegisterElement('textdisplay', {
                value = _U('shop_no_items_found'),
                style = {
                    fontSize = "16px",
                    color = "#bbb",
                    textAlign = "center",
                    marginTop = "10px"
                },
                slot  = "content"
            })
        else
            editPage:RegisterElement('imageboxcontainer', {
                slot  = "content",
                items = imageBoxItems
            }, function(data)
                local chosen = combinedRows[data.child.index]
                if not chosen then return end

                if chosen.is_weapon == 1 then
                    if OpenEditPlayerWeaponMenu then
                        OpenEditPlayerWeaponMenu(shopName, chosen)
                    else
                        devPrint("^3[WARN]^7 OpenEditPlayerWeaponMenu not implemented")
                    end
                else
                    if OpenEditPlayerItemMenu then
                        OpenEditPlayerItemMenu(shopName, chosen)
                    else
                        devPrint("^3[WARN]^7 OpenEditPlayerItemMenu not implemented")
                    end
                end
            end)
        end

        editPage:RegisterElement('line', {
            slot = "footer", style = {}
        })
        editPage:RegisterElement('button', {
            label = _U('backButton'),
            slot  = "footer",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            -- Go back to your player store main (adjust as needed)
            OpenPlayerBuySellMenu(shopName)
        end)
        editPage:RegisterElement('bottomline', {
            slot = "footer",
            style = {}
        })

        BCCShopsMainMenu:Open({ startupPage = editPage })
        editPage:RouteTo()
    end)
end

function OpenEditPlayerItemMenu(shopName, item)
    devPrint("Opening Player Edit Item Menu for: " .. (item.item_name or "unknown"))

    local editPage = BCCShopsMainMenu:RegisterPage('bcc-shops:player:edititem:page')

    editPage:RegisterElement('header', {
        value = _U('editItemHeader') .. ' ' .. (item.item_label or item.item_name or _U('unknown')),
        slot  = "header"
    })
    editPage:RegisterElement('line', { slot = "header", style = {} })

    local itemLabel                           = item.item_label
    local itemBuyPrice                        = tonumber(item.buy_price or 0) or 0
    local itemSellPrice                       = tonumber(item.sell_price or 0) or 0
    local itemBuyStock                        = tonumber(item.buy_quantity or 0) or 0 -- display-only
    local itemSellStock                       = tonumber(item.sell_quantity or 0) or 0
    local itemLevel                           = tonumber(item.level_required or 0) or 0
    local currentCategory                     = tonumber(item.category_id or item.category) or nil

    -- Fetch categories (reuse same source as NPC edits)
    local categories                          = exports['feather-core']:CallRPCAsync("bcc-shops:GetShopCategories")
    local categoryOptions, selectedCategoryId = {}, currentCategory

    if categories and #categories > 0 then
        for _, cat in ipairs(categories) do
            local id = tonumber(cat.value) or tonumber(cat.id)
            if id then
                categoryOptions[#categoryOptions + 1] = {
                    text  = cat.text or cat.label or ("Category " .. tostring(id)),
                    value = tostring(id)
                }
                if not selectedCategoryId then selectedCategoryId = id end
            end
        end
    else
        Notify(_U("noCategoriesFound"), "error", 4000)
        return
    end

    editPage:RegisterElement('input', {
        label       = _U('itemLabel'),
        placeholder = itemLabel,
        slot        = "content"
    }, function(data) itemLabel = data.value end)

    -- Buy price input
    editPage:RegisterElement('input', {
        label       = _U('buyPrice'),
        placeholder = tostring(itemBuyPrice),
        slot        = "content"
    }, function(data)
        itemBuyPrice = tonumber(data.value) or itemBuyPrice
    end)

    -- Show max buy price from config
    local maxBuy = ConfigItems.MaxBuyPrice and ConfigItems.MaxBuyPrice[item.item_name]
    if maxBuy then
        TextDisplay = editPage:RegisterElement('textdisplay', {
            value = _U('maxBuyPrice') .. ": " .. tostring(maxBuy),
            slot  = "content",
            style = { color = "#888", fontSize = "14px", marginBottom = "5px" }
        })
    end

    -- Sell price input
    editPage:RegisterElement('input', {
        label       = _U('sellPrice'),
        placeholder = tostring(itemSellPrice),
        slot        = "content"
    }, function(data)
        itemSellPrice = tonumber(data.value) or itemSellPrice
    end)

    -- Show max sell price from config
    local maxSell = ConfigItems.MaxSellPrice and ConfigItems.MaxSellPrice[item.item_name]
    if maxSell then
        TextDisplay = editPage:RegisterElement('textdisplay', {
            value = _U('maxSellPrice') .. ": " .. tostring(maxSell),
            slot  = "content",
            style = { color = "#888", fontSize = "14px", marginBottom = "5px" }
        })
    end

    TextDisplay = editPage:RegisterElement('textdisplay', {
        value = _U('buyStock') .. ": " .. tostring(itemBuyStock),
        slot  = "content",
        style = {
            fontSize = "15px",
            color = "#bbb",
            marginTop = "5px"
        }
    })

    editPage:RegisterElement('input', {
        label       = _U('sellStock'),
        placeholder = tostring(itemSellStock),
        slot        = "content"
    }, function(data) itemSellStock = math.max(0, math.floor(tonumber(data.value) or itemSellStock)) end)

    editPage:RegisterElement('dropdown', {
        label   = _U('category'),
        slot    = "content",
        options = categoryOptions,
        default = tostring(selectedCategoryId or categoryOptions[1].value)
    }, function(data)
        local v = tonumber(data.value)
        if v then selectedCategoryId = v end
        devPrint("Selected category_id (player edit item): " .. tostring(selectedCategoryId))
    end)

    editPage:RegisterElement('input', {
        label       = _U('RequiredLevel'),
        placeholder = tostring(itemLevel),
        slot        = "content"
    }, function(data) itemLevel = tonumber(data.value) or itemLevel end)

    editPage:RegisterElement('line', { slot = "footer" })

    editPage:RegisterElement('button', {
        label = _U('submitChanges'),
        slot  = "footer",
        style = {},
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        if not selectedCategoryId then
            return Notify(_U('missingFields') or "Missing category", "error", 4000)
        end

        -- sanitize inputs
        itemBuyPrice       = tonumber(itemBuyPrice) or 0
        itemSellPrice      = tonumber(itemSellPrice) or 0
        
        local key          = (item.item_name or "")

        local maxBuyPrice  = ConfigItems.MaxBuyPrice and ConfigItems.MaxBuyPrice[key] or nil
        local maxSellPrice = ConfigItems.MaxSellPrice and ConfigItems.MaxSellPrice[key] or nil

        if maxBuyPrice and itemBuyPrice > maxBuyPrice then
            devPrint(("Buy price %s exceeds max for %s (%s)"):format(itemBuyPrice, key, maxBuyPrice))
            Notify(_U('price_limit_exceeded'), "error", 4000)
            return
        end

        if maxSellPrice and itemSellPrice > maxSellPrice then
            devPrint(("Sell price %s exceeds max for %s (%s)"):format(itemSellPrice, key, maxSellPrice))
            Notify(_U('price_limit_exceeded'), "error", 4000)
            return
        end

        local payload = {
            shopName      = shopName,
            itemName      = item.item_name,
            itemLabel     = itemLabel,
            buyPrice      = itemBuyPrice,
            sellPrice     = itemSellPrice,
            category      = selectedCategoryId,
            levelRequired = itemLevel,
            -- buy_quantity omitted on purpose (read-only)
            sell_quantity = itemSellStock,
        }

        devPrint("[Player Edit Item] Payload: " .. json.encode(payload))

        exports['feather-core']:CallRPC("bcc-shops:EditItemPlayerShop", payload, function(success, err)
            if success then
                Notify(_U('itemUpdated'), "success", 4000)
                OpenEditItemMenu(shopName)
            else
                Notify(err or _U('itemUpdateFailed'), "error", 4000)
            end
        end)
    end)

    editPage:RegisterElement('button', {
        label = _U('backButton'),
        slot  = "footer",
        style = {},
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        OpenEditItemMenu(shopName)
    end)

    editPage:RegisterElement('bottomline', { slot = "footer" })
    BCCShopsMainMenu:Open({ startupPage = editPage })
end

function OpenEditPlayerWeaponMenu(shopName, weapon)
    devPrint("Opening Player Edit Weapon Menu for: " ..
        (weapon.weapon_name or weapon.item_name or weapon.name or "unknown_weapon"))

    local editPage  = BCCShopsMainMenu:RegisterPage('bcc-shops:player:editweapon:page:' .. tostring(shopName))

    local wName     = weapon.weapon_name or weapon.item_name or weapon.name or "unknown_weapon"
    local wLabel    = weapon.weapon_label or weapon.item_label or weapon.label or wName
    local buyPrice  = tonumber(weapon.buy_price or 0) or 0
    local sellPrice = tonumber(weapon.sell_price or 0) or 0
    local category  = weapon.category or weapon.category_id or "default"
    local levelReq  = tonumber(weapon.level_required or 0) or 0
    local buyQty    = tonumber(weapon.buy_quantity or 0) or 0 -- display-only
    local sellQty   = tonumber(weapon.sell_quantity or 0) or 0

    editPage:RegisterElement('header', {
        value = (_U('editItemHeader') or "Edit") .. ' ' .. wLabel,
        slot  = "header"
    })
    editPage:RegisterElement('line', { slot = "header", style = {} })

    editPage:RegisterElement('input', {
        label       = _U('itemLabel'),
        slot        = "content",
        type        = "text",
        default     = wLabel,
        placeholder = wLabel
    }, function(data) wLabel = data.value or wLabel end)

    editPage:RegisterElement('input', {
        label       = _U('buyPrice'),
        slot        = "content",
        type        = "number",
        default     = buyPrice,
        min         = 0,
        placeholder = tostring(buyPrice)
    }, function(data) buyPrice = tonumber(data.value) or buyPrice end)

    editPage:RegisterElement('input', {
        label       = _U('sellPrice'),
        slot        = "content",
        type        = "number",
        default     = sellPrice,
        min         = 0,
        placeholder = tostring(sellPrice)
    }, function(data) sellPrice = tonumber(data.value) or sellPrice end)

    -- Category input (kept text to mirror NPC weapon editor)
    editPage:RegisterElement('input', {
        label       = _U('category'),
        slot        = "content",
        type        = "text",
        default     = tostring(category),
        placeholder = tostring(category)
    }, function(data) category = data.value or category end)

    editPage:RegisterElement('input', {
        label       = _U('RequiredLevel'),
        slot        = "content",
        type        = "number",
        default     = levelReq,
        min         = 0,
        placeholder = tostring(levelReq)
    }, function(data) levelReq = tonumber(data.value) or levelReq end)

    TextDisplay = editPage:RegisterElement('textdisplay', {
        value = _U('buyStock') .. ": " .. tostring(buyQty),
        slot  = "content",
        style = { fontSize = "15px", color = "#bbb", marginTop = "5px" }
    })

    editPage:RegisterElement('input', {
        label       = _U('sellStock'),
        slot        = "content",
        type        = "number",
        default     = sellQty,
        min         = 0,
        placeholder = tostring(sellQty)
    }, function(data) sellQty = math.max(0, math.floor(tonumber(data.value) or sellQty)) end)

    editPage:RegisterElement('line', { slot = "footer" })

    editPage:RegisterElement('button', {
        label = _U('submitChanges'),
        slot  = "footer",
        style = {},
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        local payload = {
            shopName      = shopName,
            weaponName    = wName,
            weaponLabel   = wLabel,
            buyPrice      = buyPrice,
            sellPrice     = sellPrice,
            category      = category,
            levelRequired = levelReq,
            -- buy_quantity omitted on purpose (read-only)
            sell_quantity = sellQty
        }

        devPrint("[Player Edit Weapon] Payload: " .. json.encode(payload))

        exports['feather-core']:CallRPC("bcc-shops:EditWeaponPlayerShop", payload, function(success, err)
            if success then
                Notify(_U('itemUpdated'), "success", 4000)
                OpenEditItemMenu(shopName)
            else
                Notify(err or _U('itemUpdateFailed'), "error", 4000)
            end
        end)
    end)

    editPage:RegisterElement('button', {
        label = _U('backButton'),
        slot  = "footer",
        style = {},
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        OpenEditItemMenu(shopName)
    end)

    editPage:RegisterElement('bottomline', { slot = "footer" })
    BCCShopsMainMenu:Open({ startupPage = editPage })
end
