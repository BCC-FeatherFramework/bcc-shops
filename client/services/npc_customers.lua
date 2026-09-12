CreatedCustomers = {}

function waitUntilClose(ped, label, meetPoint)
    local timeout = GetGameTimer() + 60000 -- 15 seconds to reach
    local lastPos = GetEntityCoords(ped)
    local stuckCounter = 0

    while #(GetEntityCoords(ped) - vector3(meetPoint.x, meetPoint.y, meetPoint.z)) > 1.5 do
        Wait(1000)

        local currentPos = GetEntityCoords(ped)
        local distMoved = #(vector3(currentPos.x, currentPos.y, currentPos.z) - vector3(lastPos.x, lastPos.y, lastPos.z))

        if distMoved < 0.1 then
            stuckCounter = stuckCounter + 1
        else
            stuckCounter = 0
        end

        lastPos = currentPos

        if GetGameTimer() > timeout or stuckCounter >= 5 then
            devPrint("❌ " .. label .. " is stuck or timeout reached")
            return false
        end
    end

    devPrint("✅ " .. label .. " reached meeting point")
    return true
end

-- Client NPC spawning is disabled: do not create any models
function SpawnConfiguredPed(model, position)
    devPrint("[NPC Customers] Client-side NPC spawning disabled. Skipping ped creation.")
    return nil
end

-- Entire NPC meet flow disabled on client
function SpawnNPCMeetFromShop(shop, modelA, modelB, deleteDelay)
    devPrint("[NPC Customers] Client-side NPC meet/tasking disabled. Skipping.")
    return
end

RegisterCommand("npcbuyrandomweapon", function()
    local shopName = "Arme si Munitie"
    local quantity = 1

    exports['feather-core']:CallRPC("bcc-shops:FetchShopItems", { shopName = shopName }, function(result)
        if not result or not result.weapons then
            devPrint("Failed to fetch weapons from shop: " .. shopName)
            return
        end

        -- Flatten the category-grouped weapons table
        local allWeapons = {}
        for _, group in pairs(result.weapons) do
            for _, weapon in ipairs(group) do
                if weapon.buy_quantity and tonumber(weapon.buy_quantity) >= quantity then
                    table.insert(allWeapons, weapon)
                end
            end
        end

        if #allWeapons < 2 then
            devPrint("Not enough weapon stock available to perform test.")
            return
        end

        -- Pick two different weapons
        math.randomseed(GetGameTimer())
        local first = allWeapons[math.random(#allWeapons)]
        local second
        repeat
            second = allWeapons[math.random(#allWeapons)]
        until second.name ~= first.name

        local function purchase(weapon)
            local totalCost = (tonumber(weapon.price) or 0) * quantity
            local payload = {
                shopName = shopName,
                weaponName = weapon.name,
                quantity = quantity,
                total = totalCost
            }

            devPrint("Attempting NPC weapon purchase: " .. json.encode(payload))

            exports['feather-core']:CallRPC("bcc-shops:PurchaseWeaponNPC", payload, function(success)
                if success then
                    devPrint("NPC successfully bought: " .. weapon.label)
                else
                    devPrint("NPC failed to buy: " .. weapon.label)
                end
            end)
        end

        purchase(first)
        Wait(1000)
        purchase(second)
    end)
end)

-- Remove debug command that spawned/handled NPC meetings
RegisterCommand("npcmeetbuy", function()
    devPrint("[NPC Customers] npcmeetbuy disabled: client-side NPC spawning is turned off.")
end)
