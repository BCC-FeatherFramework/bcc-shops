


FeatherMenu = FeatherMenuV2Compat

CreatedBlip, CreatedNPC, playerStores, npcStores, globalNearbyShops, currentPlayers, ownedShops = {}, {}, {}, {}, {}, {},{}
isPlayerNearStore, storesFetched = false, false
AdminAllowed, OwnerAllowed, currentAction = nil, nil, nil
playerLevel = 0
Pages = {}
function devPrint(...)
    if Config.devMode then
        local message = "[DEBUG] "
        for i, v in ipairs({...}) do
            message = message .. tostring(v) .. " "
        end
        print(message)
    end
end

BCCShopsMainMenu = FeatherMenu:RegisterMenu('bcc-shops:mainmenu',     {
        top = '3%',
        left = '3%',
        ['720width'] = '400px',
        ['1080width'] = '500px',
        ['2kwidth'] = '600px',
        ['4kwidth'] = '800px',
        style = {
            --['background-image'] = 'url("nui://bcc-shops/images/background.png")',
            --['background-size'] = 'cover',  
            --['background-repeat'] = 'no-repeat',
                --['background-position'] = 'center',
                --['background-color'] = 'rgba(55, 33, 14, 0.7)', -- A leather-like brown
                --['border'] = '1px solid #654321', 
                --['font-family'] = 'Times New Roman, serif', 
                --['font-size'] = '38px',
                --['color'] = '#ffffff', 
                --['padding'] = '10px 20px',
                --['margin-top'] = '5px',
                --['cursor'] = 'pointer', 
                --['box-shadow'] = '3px 3px #333333', 
                --['text-transform'] = 'uppercase', 
        },
        contentslot = {
            style = {
                ['height'] = '450px',
                ['min-height'] = '300px'
            }
        },
    draggable = true
  }, {
    opened = function()
        DisplayRadar(false)
    end,
    closed = function()
        DisplayRadar(true)
    end,
})

function HandlePlayerDeathAndCloseMenu()
    local playerPed = PlayerPedId()

    -- Check if the player is already dead
    if IsEntityDead(playerPed) then
        devPrint("Player is dead, closing the shop menu.")
        BCCShopsMainMenu:Close() -- Close the menu if the player is dead
        return true             -- Return true to indicate the player is dead and the menu was closed
    end

    -- If the player is not dead, start monitoring for death while the menu is open
    CreateThread(function()
        while true do
            if IsEntityDead(playerPed) then
                devPrint("Player died while in the menu, closing the shop menu.")
                BCCShopsMainMenu:Close() -- Close the menu if the player dies while in the menu
                break                   -- Stop the loop since the player is dead and the menu is closed
            end
            Wait(1000)                  -- Check every second
        end
    end)

    devPrint("Player is alive, shop menu can be opened.")
    return false -- Return false to indicate the player is alive and the menu can open
end

-- Function to check if the player is an admin
function IsPlayerAdmin()
    return AdminAllowed
end

function GetShopByName(name)
    for _, shop in ipairs(playerStores) do
        if shop.shop_name == name then
            return shop
        end
    end
    for _, shop in ipairs(npcStores) do
        if shop.shop_name == name then
            return shop
        end
    end
    return nil
end

function OpenPlayerBuySellMenu(shopName)
    devPrint("Opening Buy/Sell Menu for Player store: " .. shopName)

    exports['feather-core']:CallRPC("bcc-shops:fetchPlayerStoreInfo", { shopName = shopName }, function(data, err)
        if not data then
            devPrint("Failed to fetch store: " .. (err or "Unknown error"))
            return
        end

        -- Call the reusable menu function directly
        OpenPlayerStoreMenu(data.shopId, data.shopName, data.invLimit, data.ledger, data.isOwner, data.hasAccess)
    end)
end

function OpenAddPlayerItemMenu(storeName)
    devPrint("Checking store ownership/access for: " .. storeName)

    local ownershipData = exports['feather-core']:CallRPCAsync("bcc-shops:CheckStoreOwnership", { storeName = storeName })

    if not ownershipData or not ownershipData.storeName then
        devPrint("Ownership check failed.")
        return
    end

    devPrint("Ownership/access result: isOwner=" ..
    tostring(ownershipData.isOwner) .. ", hasAccess=" .. tostring(ownershipData.hasAccess))

    if ownershipData.isOwner or ownershipData.hasAccess then
        devPrint("Player has permission to add items to store: " .. ownershipData.storeName)

        local result = exports['feather-core']:CallRPCAsync("bcc-shops:fetchPlayerInventory", { shopName = ownershipData.storeName })
        if not result then
            devPrint("Failed to fetch inventory.")
            return
        end
        OpenPlayerInventoryMenu(result.shopName, result.inventory, result.weapons)
    else
        devPrint("Player does NOT have permission for store: " .. ownershipData.storeName)
        Notify(_U("noPermissionToAddItems"), "error", 4000)
    end
end

function OpenBuyMenu(shopName, storeType)
    devPrint("Opening Buy Menu for " .. storeType .. " store: " .. shopName)
    if HandlePlayerDeathAndCloseMenu() then
        devPrint("Player is dead, closing the menu")
        return
    end
    BuyMenu(shopName)
end

function OpenSellMenu(shopName, storeType)
    devPrint("Opening Sell Menu for " .. storeType .. " store: " .. shopName)
    SellMenu(shopName)
end
