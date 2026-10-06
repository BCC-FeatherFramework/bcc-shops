-- Server-side NPC auto-purchase loop
-- Runs periodically and simulates NPCs buying from player-owned shops.

local function getAllPlayerShops()
    if type(FetchAllPlayerShops) == "function" then
        return FetchAllPlayerShops() or {}
    end
    local result = DB.query('SELECT shop_id, shop_name, pos_x, pos_y, pos_z FROM bcc_shops WHERE owner_id IS NOT NULL')
    return result or {}
end

local function pickRandom(list)
    if not list or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

local function fetchAvailableStock(shopId)
    local items = {}

    local itemRows = DB.query([[
        SELECT item_name AS name, item_label AS label, buy_price, buy_quantity
        FROM bcc_shop_items
        WHERE shop_id = ? AND buy_quantity > 0
    ]], shopId) or {}

    for _, row in ipairs(itemRows) do
        table.insert(items, {
            is_weapon   = false,
            name        = row.name,
            label       = row.label or row.name,
            buy_price   = tonumber(row.buy_price) or 0,
            buy_quantity= tonumber(row.buy_quantity) or 0,
        })
    end

    local weaponRows = DB.query([[
        SELECT weapon_name AS name, weapon_label AS label, buy_price, buy_quantity
        FROM bcc_shop_weapon_items
        WHERE shop_id = ? AND buy_quantity > 0
    ]], shopId) or {}

    for _, row in ipairs(weaponRows) do
        table.insert(items, {
            is_weapon   = true,
            name        = row.name,
            label       = row.label or row.name,
            buy_price   = tonumber(row.buy_price) or 0,
            buy_quantity= tonumber(row.buy_quantity) or 0,
        })
    end

    return items
end

local function sendWebhook(shopId, shopName, label, name, qty, total, isWeapon)
    local shopInfo = DB.query('SELECT webhook_link, shop_name FROM bcc_shops WHERE shop_id = ?', shopId)
    local info = (shopInfo and shopInfo[1]) or {}
    local webhook = info.webhook_link -- may be nil
    local finalName = info.shop_name or shopName or "Unknown"

    local title = isWeapon and "🛒 Weapon Purchased" or "Item Purchased"
    local embed = { 
        {
            color = 3145631,
            title = title,
            description = table.concat({
                "**Character Name:** `NPC`",
                "**Character ID:** `NPC`",
                (isWeapon and "**Weapon Name:** `" .. label .. "`" or "**Item Name:** `" .. label .. "`"),
                (isWeapon and "**Weapon ID:** `" .. name .. "`" or "**Item ID:** `" .. name .. "`"),
                "**Quantity:** `" .. tostring(qty) .. "`",
                "**Total Cost:** `$" .. tostring(total) .. "`",
                "**Shop Name:** `" .. finalName .. "`"
            }, "\n")
        }
    }

    if webhook and webhook ~= "none" then
        ShopsToolkit.Discord.sendMessage(webhook, Config.WebhookTitle, Config.WebhookAvatar, title, nil, embed)
    end
    ShopsToolkit.Discord.sendMessage(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar, title, nil, embed)
end

local function performNpcPurchase(shopId, shopName, item)
    -- Requires a funded merchant account in Economy. Never credit a local ledger.
    local result = ShopsPayments.ShopFundsUnavailable()
    devPrint('[NPC AutoBuy] Purchase blocked:', result.code)
    return false
end

CreateThread(function()
    -- small delay to let other services init
    Wait(2500)
    devPrint("[NPC AutoBuy] Server loop initializing...")

    while true do
        local interval = (Config and Config.NPC and tonumber(Config.NPC.purchaseInterval)) or 900000

        if not (Config and Config.NPC and Config.NPC.npcBuyFromPlayerShop) then
            -- loop disabled, check again in one minute
            Wait(60000)
        else
            local shops = getAllPlayerShops()
            if not shops or #shops == 0 then
                devPrint("[NPC AutoBuy] No player shops found. Skipping.")
                Wait(60000)
            else
                local shop = pickRandom(shops)
                local shopName = shop.shop_name
                local shopId = shop.shop_id or DB.value('SELECT shop_id FROM bcc_shops WHERE shop_name = ? AND owner_id IS NOT NULL', shopName)

                if not shopId then
                    devPrint("[NPC AutoBuy] Could not resolve shop_id for " .. tostring(shopName))
                    Wait(interval)
                else
                    local stock = fetchAvailableStock(shopId)
                    if not stock or #stock == 0 then
                        devPrint("[NPC AutoBuy] No available stock for shop: " .. tostring(shopName))
                        Wait(interval)
                    else
                        local item = pickRandom(stock)
                        devPrint(string.format("[NPC AutoBuy] Purchasing %s '%s' x%d from '%s' for $%d",
                            item.is_weapon and "weapon" or "item",
                            item.label,
                            math.min(item.buy_quantity, 1), -- log preview, actual qty decided inside perform
                            shopName,
                            (tonumber(item.buy_price) or 0)
                        ))

                        local ok = performNpcPurchase(shopId, shopName, item)
                        if not ok then
                            devPrint("[NPC AutoBuy] Purchase skipped due to invalid data.")
                        end
                        Wait(interval)
                    end
                end
            end
        end
    end
end)

