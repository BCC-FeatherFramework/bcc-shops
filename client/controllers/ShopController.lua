RegisterNetEvent('Feather:Character:Spawned')
AddEventHandler('Feather:Character:Spawned', function()
    exports['feather-core']:CallRPC("bcc-shops:CheckAdmin", {}, function(isAdmin)
        AdminAllowed = isAdmin
        npcStores = exports['feather-core']:CallRPCAsync('bcc-shops:FetchNPCShops') or {}
        playerStores = exports['feather-core']:CallRPCAsync('bcc-shops:FetchPlayerShops') or {}
        storesFetched = true
        CreateBlips()
        CreateNPCs()
        devPrint("[RPC] Admin check result: " .. tostring(isAdmin))
    end)
end)

CreateThread(function()
    devPrint("Prompts initialized")
    local BCCShopsMenuPrompt = ShopsToolkit.Prompts:SetupPromptGroup()
    local shopprompt = BCCShopsMenuPrompt:RegisterPrompt(_U('PromptName'), Config.keys.access, 1, 1, true, 'hold', { timedeventhash = 'MEDIUM_TIMED_EVENT' })

    -- Await admin check
    AdminAllowed = exports['feather-core']:CallRPCAsync("bcc-shops:CheckAdmin")
    devPrint("[RPC] Admin check result: " .. tostring(AdminAllowed))

    -- Await NPC shops
    npcStores = exports['feather-core']:CallRPCAsync("bcc-shops:FetchNPCShops") or {}

    if currentAction == "deleteNPCStores" then
        OpenDeleteNPCStoresMenu()
    end

    -- Await Player shops
    playerStores = exports['feather-core']:CallRPCAsync("bcc-shops:FetchPlayerShops") or {}
    storesFetched = true
    CreateBlips()
    CreateNPCs()
    -- Start main loop
    while true do
        Wait(0)

        local playerPed = PlayerPedId()
        if IsEntityDead(playerPed) then
            Wait(1000)
            goto continue_loop
        end

        local playerCoords = GetEntityCoords(playerPed)
        local nearbyShops = {}
        local addedShopIds = {}

        -- NPC shops
        for _, shop in ipairs(npcStores) do
            local dist = #(playerCoords - vector3(shop.pos_x, shop.pos_y, shop.pos_z))
            if dist < 3.0 and shop.is_npc_shop then
                if not addedShopIds[shop.shop_id] then
                    table.insert(nearbyShops, { type = "npc", name = shop.shop_name, details = shop })
                    addedShopIds[shop.shop_id] = true
                end
            end
        end

        -- Player shops
        for _, store in ipairs(playerStores) do
            if store.pos_x and store.pos_y and store.pos_z and not store.is_npc_shop then
                local dist = #(playerCoords - vector3(store.pos_x, store.pos_y, store.pos_z))
                if dist < 3.0 then
                    if not addedShopIds[store.shop_id] then
                        local storeName = store.shop_name or "Unnamed Store"
                        table.insert(nearbyShops, { type = "player", name = storeName, details = store })
                        addedShopIds[store.shop_id] = true
                    end
                end
            end
        end

        -- Prompt and menu handling
        if #nearbyShops > 0 then
            if not isPlayerNearStore then isPlayerNearStore = true end
            globalNearbyShops = nearbyShops

            local promptText = _U('PromptName')
            for _, shop in ipairs(nearbyShops) do
                if shop.type == "player" then
                    promptText = shop.name
                    break
                elseif shop.type == "npc" then
                    promptText = shop.name
                end
            end

            BCCShopsMenuPrompt:ShowGroup(promptText)

            if shopprompt:HasCompleted() then
                local opened = false
                for _, shop in ipairs(nearbyShops) do
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
        else
            if isPlayerNearStore then isPlayerNearStore = false end
        end

        ::continue_loop::
    end
end)

exports['feather-core']:RegisterRPC("bcc-shops:OpenManageStoresUI", function(data)
    OpenInitialManageMenu(data.shops, data.players)
end)

RegisterNetEvent('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, npc in ipairs(CreatedNPC) do
            npc:Remove()
        end

        for _, blip in ipairs(CreatedBlip) do
            blip:Remove()
        end

        for _, customer in ipairs(CreatedCustomers) do
            customer:Remove()
        end

        BCCShopsMainMenu:Close()
        devPrint("♻️ All NPCs, blips, and customer peds cleaned up on resource stop.")
    end
end)