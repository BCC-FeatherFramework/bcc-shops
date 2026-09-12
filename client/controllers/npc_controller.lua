local playerStores = {}
local npcLoopStarted = false

-- 🔁 Cache player stores when the resource starts
CreateThread(function()
    devPrint("📡 Fetching all player-owned shops to cache...")
    local result = exports['feather-core']:CallRPCAsync("bcc-shops:GetAllPlayerShops", {})
    if result and #result > 0 then
        playerStores = result
        devPrint("Cached " .. #playerStores .. " player-owned shops.")
    else
        devPrint("Failed to cache player shops or none found.")
    end
end)

-- Client-side NPC meet/purchase loop disabled.
-- Keep behind devMode so it never runs in production.
if Config.devMode then
    CreateThread(function()
        Wait(3000)
        devPrint("🚀 Requesting to start NPC purchase loop from client (dev mode)...")
        local started = exports['feather-core']:CallRPCAsync("bcc-shops:StartNpcPurchases", {})
        if started then
            devPrint("NPC purchase loop approved. Starting loop (dev mode).")
            StartNpcPurchaseLoop()
        else
            devPrint("NPC loop already running or disabled by server.")
        end
    end)
end

-- Main NPC Purchase Logic Loop
function StartNpcPurchaseLoop()
    local delay = Config.NPC.purchaseInterval or 10000 -- Default: 10 minutes

    CreateThread(function()
        while true do
            devPrint("⏳ Waiting " .. tostring(delay) .. "ms before next NPC tick...")
            Wait(delay)

            if not playerStores or #playerStores == 0 then
                devPrint("No cached player stores found. Skipping tick.")
                goto continue
            end

            -- Pick a random shop
            local shop = playerStores[math.random(#playerStores)]
            shop.pos_x = tonumber(shop.pos_x)
            shop.pos_y = tonumber(shop.pos_y)
            shop.pos_z = tonumber(shop.pos_z)

            if not shop.pos_x or not shop.pos_y or not shop.pos_z then
                devPrint("Invalid shop coordinates for: " .. (shop.shop_name or "unknown"))
                goto continue
            end

            shop.coords = vector3(shop.pos_x, shop.pos_y, shop.pos_z)
            devPrint(("Selected shop '%s' at coords (%.2f, %.2f, %.2f)"):format(
                shop.shop_name, shop.coords.x, shop.coords.y, shop.coords.z
            ))

            -- Fetch shop items
            devPrint("Fetching items for shop: " .. shop.shop_name)
            local result = exports['feather-core']:CallRPCAsync("bcc-shops:FetchShopItems", { shopName = shop.shop_name })
            if not result or not result.items then
                devPrint("Failed to fetch items for shop: " .. shop.shop_name)
                goto continue
            end

            -- Flatten and filter items and weapons
            local allItems = {}

            for _, group in pairs(result.items or {}) do
                for _, item in ipairs(group) do
                    if item.buy_quantity and tonumber(item.buy_quantity) > 0 then
                        table.insert(allItems, item)
                    end
                end
            end

            for _, group in pairs(result.weapons or {}) do
                for _, item in ipairs(group) do
                    if item.buy_quantity and tonumber(item.buy_quantity) > 0 then
                        item.is_weapon = 1 -- mark it for purchase as weapon
                        table.insert(allItems, item)
                    end
                end
            end

            if #allItems == 0 then
                devPrint("No items with stock found in shop: " .. shop.shop_name)
                goto continue
            end
            
            shop.items = allItems
            devPrint("Found " .. #allItems .. " items for sale in shop.")

            -- Select two different models
            local modelA = Config.NPC.npcModels[math.random(#Config.NPC.npcModels)]
            local modelB = Config.NPC.npcModels[math.random(#Config.NPC.npcModels)]
            while modelB == modelA do
                modelB = Config.NPC.npcModels[math.random(#Config.NPC.npcModels)]
            end

            devPrint("👤 Selected NPC models: A = " .. modelA .. ", B = " .. modelB)

            -- Spawn and simulate NPC
            devPrint("🎬 Spawning NPCs for shop: " .. shop.shop_name)
            SpawnNPCMeetFromShop(shop, modelA, modelB, 50000)

            ::continue::
        end
    end)
end
