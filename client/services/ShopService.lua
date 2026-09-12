function CreateBlips()
    for _, blip in ipairs(CreatedBlip) do blip:Remove() end
    CreatedBlip = {}
    for _, shop in ipairs(npcStores) do
        if shop.show_blip == true or tonumber(shop.show_blip) == 1 then
            local hash = tonumber(shop.blip_hash)
            local blip = ShopsToolkit.Blips:SetBlip(shop.shop_name, hash, 1, shop.pos_x, shop.pos_y, shop.pos_z)
            CreatedBlip[#CreatedBlip + 1] = blip
        end
    end

    for _, shop in ipairs(playerStores) do
        if shop.show_blip == true or tonumber(shop.show_blip) == 1 then
            local hash = tonumber(shop.blip_hash)
            local blip = ShopsToolkit.Blips:SetBlip(shop.shop_name, hash, 1, shop.pos_x, shop.pos_y, shop.pos_z)
            CreatedBlip[#CreatedBlip + 1] = blip
        end
    end
end

function CreateNPCs()
    for _, ped in ipairs(CreatedNPC) do ped:Remove() end
    CreatedNPC = {}
    for _, shop in ipairs(npcStores) do
        shopPed = ShopsToolkit.Ped:Create(shop.npc_model, shop.pos_x, shop.pos_y, shop.pos_z - 1, 0, 'world', false)
        CreatedNPC[#CreatedNPC + 1] = shopPed
        shopPed:Freeze()
        shopPed:SetHeading(shop.pos_heading)
        shopPed:Invincible()
        shopPed:SetBlockingOfNonTemporaryEvents(true)
    end

    for _, shop in ipairs(playerStores) do
        shopPed = ShopsToolkit.Ped:Create(shop.npc_model, shop.pos_x, shop.pos_y, shop.pos_z - 1, 0, 'world', false)
        CreatedNPC[#CreatedNPC + 1] = shopPed
        shopPed:Freeze()
        shopPed:SetHeading(shop.pos_heading)
        shopPed:Invincible()
        shopPed:SetBlockingOfNonTemporaryEvents(true)
    end
end

function FetchPlayersForOwnerSelection()
    exports['feather-core']:CallRPC("bcc-shops:FetchPlayersForOwnerSelection", {}, function(players)
        if players then
            -- Replace this with your menu or logic handler
            SelectOwner(players)
        else
            Notify(_U("failedToFetchPlayers"), "error", 4000)
        end
    end)
end

exports['feather-core']:RegisterRPC("bcc-shops:clientCleanup", function()
    for _, npc in ipairs(CreatedNPC) do
        if npc and npc.Remove then
            npc:Remove()
        elseif DoesEntityExist(npc) then
            DeleteEntity(npc)
        end
    end
    CreatedNPC = {}

    for _, blip in ipairs(CreatedBlip) do
        if blip and blip.Remove then
            blip:Remove()
        else
            RemoveBlip(blip)
        end
    end
    CreatedBlip = {}

    for _, customer in ipairs(CreatedCustomers or {}) do
        if customer and customer.Remove then
            customer:Remove()
        elseif DoesEntityExist(customer) then
            DeleteEntity(customer)
        end
    end
    CreatedCustomers = {}

    BCCShopsMainMenu:Close()

    devPrint("[ClientCleanup] All NPCs, blips, and customers cleaned up.")
end)

exports['feather-core']:RegisterRPC("bcc-shops:RefreshStoreData", function(_, cb)
    -- Fetch NPC shops
    npcStores = exports['feather-core']:CallRPCAsync("bcc-shops:FetchNPCShops") or {}
    devPrint("NPC shops refreshed: " .. tostring(#npcStores))

    -- Fetch player shops (ensure assignment always happens)
    playerStores = exports['feather-core']:CallRPCAsync("bcc-shops:FetchPlayerShops") or {}
    storesFetched = true
    devPrint("Player stores refreshed: " .. tostring(#playerStores))

    -- Recreate world data
    CreateBlips()
    CreateNPCs()

    if cb then cb(true) end
end)
