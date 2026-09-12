function OpenInitialManageMenu(stores, players)
    Pages.initialManagePage = BCCShopsMainMenu:RegisterPage('bcc-shops:initialmanage')
    Pages.initialManagePage:RegisterElement('header', {
        value = _U('manageStores'),
        slot = "header"
    })

    Pages.initialManagePage:RegisterElement('button', {
        label = _U('createStore'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenCreateStoreMenu()
    end)

    Pages.initialManagePage:RegisterElement('button', {
        label = _U('manageStores'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        Pages.initialManageStores = BCCShopsMainMenu:RegisterPage('bcc-shops:managestores')

        Pages.initialManageStores:RegisterElement('header', {
            value = _U('manageStores'),
            slot = "header"
        })

        Pages.initialManageStores:RegisterElement('button', {
            label = _U('npcStores'),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            exports['feather-core']:CallRPC("bcc-shops:FetchNPCShops", {}, function(npcShops)
                if npcShops then
                    npcStores = npcShops
                    devPrint("✅ NPC shops refreshed: " .. #npcShops)

                    -- Open NPC List Page
                    Pages.npcListPage = BCCShopsMainMenu:RegisterPage("bcc-shops:listnpcstores")
                    Pages.npcListPage:RegisterElement("header", { 
                        value = _U("npcStores"), 
                        slot = "header" 
                    })

                    for _, shop in ipairs(npcShops) do
                        local label = (shop.shop_label or shop.shop_name)
                        Pages.npcListPage:RegisterElement("button", {
                            label = label,
                            slot = "content",
                            style = {},
                            sound = {
                                action = "SELECT",
                                soundset = "RDRO_Character_Creator_Sounds"
                            }
                        }, function()
                            OpenEditNPCShopPage(shop)
                        end)
                    end

                    Pages.npcListPage:RegisterElement("line", {
                        slot = "footer",
                        style = {}
                    })

                    Pages.npcListPage:RegisterElement("button", {
                        label = _U("backButton"),
                        slot = "footer",
                        style = {},
                        sound = {
                            action = "SELECT",
                            soundset = "RDRO_Character_Creator_Sounds"
                        }
                    }, function()
                        Pages.initialManageStores:RouteTo()
                    end)

                    Pages.npcListPage:RegisterElement("bottomline", {
                        slot = "footer",
                        style = {}
                    })

                    BCCShopsMainMenu:Open({ startupPage = Pages.npcListPage })
                else
                    devPrint("⚠️ No NPC shops returned.")
                end
            end)
        end)

        Pages.initialManageStores:RegisterElement('button', {
            label = _U('playerStores'),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            exports['feather-core']:CallRPC("bcc-shops:FetchPlayerShops", {}, function(playerShops)
                if playerShops then
                    playerStores = playerShops
                    devPrint("✅ Player shops refreshed: " .. #playerShops)

                    -- Open Player List Page
                    Pages.playerListPage = BCCShopsMainMenu:RegisterPage("bcc-shops:listplayerstores")
                    Pages.playerListPage:RegisterElement("header", { 
                        value = _U("playerStores"),
                        slot = "header"
                    })

                    for _, shop in ipairs(playerShops) do
                        local label = (shop.shop_label or shop.shop_name)
                        Pages.playerListPage:RegisterElement("button", {
                            label = label,
                            slot = "content",
                            style = {},
                            sound = {
                                action = "SELECT",
                                soundset = "RDRO_Character_Creator_Sounds"
                            }
                        }, function()
                            OpenEditPlayerShopPage(shop)
                        end)
                    end

                    Pages.playerListPage:RegisterElement("line", {
                        slot = "footer",
                        style = {}
                    })

                    Pages.playerListPage:RegisterElement("button", {
                        label = _U("backButton"),
                        slot = "footer",
                        style = {},
                        sound = {
                            action = "SELECT",
                            soundset = "RDRO_Character_Creator_Sounds"
                        }
                    }, function()
                        Pages.initialManageStores:RouteTo()
                    end)

                    Pages.playerListPage:RegisterElement("bottomline", {
                        slot = "footer",
                        style = {}
                    })

                    BCCShopsMainMenu:Open({ startupPage = Pages.playerListPage })
                else
                    devPrint("⚠️ No player shops returned.")
                end
            end)
        end)

        -- Line separator
        Pages.initialManageStores:RegisterElement('line', {
            slot = "footer",
            style = {}
        })

        -- Back button
        Pages.initialManageStores:RegisterElement('button', {
            label = _U('backButton'),
            slot = "footer",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            Pages.initialManagePage:RouteTo()
        end)

        -- Bottom line
        Pages.initialManageStores:RegisterElement('bottomline', {
            slot = "footer",
            style = {}
        })

        -- Open the page
        BCCShopsMainMenu:Open({ startupPage = Pages.initialManageStores })
    end)

    Pages.initialManagePage:RegisterElement('button', {
        label = _U('deleteStores'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenDeleteStoresMenu()
    end)

    Pages.initialManagePage:RegisterElement('button', {
        label = _U('CategoriesHeader'),
        slot = "content"
    }, function()
        Pages.CategoryPage = BCCShopsMainMenu:RegisterPage('bcc-shops:category:page')
        Pages.CategoryPage:RegisterElement('header', {
            value = _U('CategoriesHeader'),
            slot = "header"
        })

        Pages.CategoryPage:RegisterElement('button', {
            label = _U('createCategory'),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            OpenCreateCategoryMenu()
        end)

        Pages.CategoryPage:RegisterElement('button', {
            label = _U('editCategory'),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            OpenEditCategoryMenu()
        end)

        Pages.CategoryPage:RegisterElement('button', {
            label = _U('deleteCategory'),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            OpenDeleteCategoryMenu()
        end)

        Pages.CategoryPage:RegisterElement('line', {
            slot = "footer",
            style = {}
        })
        Pages.CategoryPage:RegisterElement('button', {
            label = _U('backButton'),
            slot = "footer",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            Pages.initialManagePage:RouteTo()
        end)
        Pages.CategoryPage:RegisterElement('bottomline', {
            slot = "footer",
            style = {}
        })
        BCCShopsMainMenu:Open({ startupPage = Pages.CategoryPage })
    end)

    Pages.initialManagePage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })
    Pages.initialManagePage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        BCCShopsMainMenu:Close()
    end)
    Pages.initialManagePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })
    BCCShopsMainMenu:Open({ startupPage = Pages.initialManagePage })
end

function OpenCreateStoreMenu()
    local createStorePage = BCCShopsMainMenu:RegisterPage('player:store:createstore')
    createStorePage:RegisterElement('header', {
        value = _U('createStore'),
        slot = "header"
    })

    createStorePage:RegisterElement('button', {
        label = _U('createNPCStore'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenCreateNPCStoreMenu()
    end)

    createStorePage:RegisterElement('button', {
        label = _U('createPlayerStore'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        FetchPlayersForOwnerSelection()
    end)

    createStorePage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    createStorePage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenInitialManageMenu()
    end)

    createStorePage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = createStorePage })
end

function OpenDeleteStoresMenu()
    local deleteStoresPage = BCCShopsMainMenu:RegisterPage('bcc-shops:deletestores')
    deleteStoresPage:RegisterElement('header', {
        value = _U('deleteStores'),
        slot = "header"
    })

    deleteStoresPage:RegisterElement('button', {
        label = _U('npcStores'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        currentAction = "deleteNPCStores"
        devPrint("Pressed NPC Stores button — sending RPC")
        exports['feather-core']:CallRPC("bcc-shops:FetchNPCShops", {}, function(npcShops)
            if npcShops then
                npcStores = npcShops
                devPrint("NPC shops refreshed: " .. #npcShops)
                OpenDeleteNPCStoresMenu()
            else
                devPrint("No NPC shops returned.")
                Notify(_U('noNPCShopFound'), "warning", 4000)
            end
        end)
    end)

    deleteStoresPage:RegisterElement('button', {
        label = _U('playerStores'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        currentAction = "deletePlayerStores"

        local playerShops = exports['feather-core']:CallRPCAsync("bcc-shops:FetchPlayerShops", {})
        if playerShops and #playerShops > 0 then
            playerStores = playerShops
            devPrint("Player shops refreshed: " .. tostring(#playerShops))
            OpenDeletePlayerStoresMenu()
        else
            devPrint("No player shops returned.")
            FeatherMenu:Notify(_U('noPlayerShopFound'), "warning", 4000)
        end
    end)

    deleteStoresPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    deleteStoresPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenInitialManageMenu()
    end)

    deleteStoresPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = deleteStoresPage })
end

function OpenDeletePlayerStoresMenu()
    local deletePlayerStoresPage = BCCShopsMainMenu:RegisterPage('bcc-shops:deleteplayerstores')
    deletePlayerStoresPage:RegisterElement('header', {
        value = _U('deletePlayerStore'),
        slot = "header"
    })

    for _, store in ipairs(playerStores) do
        deletePlayerStoresPage:RegisterElement('button', {
            label = store.shop_name,
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            OpenDeleteConfirmationMenu(store.shop_id, store.shop_name, "player")
        end)
    end

    deletePlayerStoresPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    deletePlayerStoresPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        OpenDeleteStoresMenu()
    end)

    deletePlayerStoresPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = deletePlayerStoresPage })
end

function OpenDeleteConfirmationMenu(storeId, shopName, storeType)
    local confirmationPage = BCCShopsMainMenu:RegisterPage('bcc-shops:confirmdelete')
    confirmationPage:RegisterElement('header', {
        value = _U('confirmDeletion'),
        slot = "header"
    })
    confirmationPage:RegisterElement('subheader', {
        value = _U('areYouSure') .. shopName,
        slot = "content"
    })

    confirmationPage:RegisterElement('button', {
        label = _U('yes'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        if storeType == "npc" then
            exports['feather-core']:CallRPC("bcc-shops:deleteNPCShop", { shopId = storeId })
        else
            exports['feather-core']:CallRPC("bcc-shops:deletePlayerShop", { shopId = storeId })
        end
        BCCShopsMainMenu:Close()
    end)

    confirmationPage:RegisterElement('button', {
        label = _U('no'),
        slot = "content",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        if storeType == "npc" then
            OpenDeleteNPCStoresMenu()
        else
            OpenDeletePlayerStoresMenu()
        end
    end)

    confirmationPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    confirmationPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer"
    }, function()
        if storeType == "npc" then
            OpenDeleteNPCStoresMenu()
        else
            OpenDeletePlayerStoresMenu()
        end
    end)

    confirmationPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = confirmationPage })
end

function OpenCreateCategoryMenu()
    Pages.createCatPage = BCCShopsMainMenu:RegisterPage("bcc-shops:createCategory")

    Pages.createCatPage:RegisterElement('header', {
        value = _U('createCategory'),
        slot = "header"
    })

    local newName   = ""
    local newLabel  = ""

    Pages.createCatPage:RegisterElement('input', {
        label = _U('categoryName'),
        slot = "content",
        type = "text",
        placeholder = "Enter category name..."
    }, function(data)
        newName = data.value
    end)

    Pages.createCatPage:RegisterElement('input', {
        label = _U('categoryLabel'),
        slot = "content",
        type = "text",
        placeholder = "Enter category label..."
    }, function(data)
        newLabel = data.value
    end)

    Pages.createCatPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    Pages.createCatPage:RegisterElement('button', {
        label = _U("submitChanges"),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        if newName and newName:len() > 0 then
            local labelToSave = (newLabel and newLabel:match("%S")) and newLabel or newName
            exports['feather-core']:CallRPC("bcc-shops:CreateCategory", { name = newName, label = labelToSave }, function(success)
                if success then
                    Notify(_U("categoryCreatedSuccess"), "success", 4000)
                    Pages.CategoryPage:RouteTo()
                else
                    Notify(_U("categoryCreatedFail"), "error", 4000)
                end
            end)
        end
    end)

    Pages.createCatPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        Pages.CategoryPage:RouteTo()
    end)

    Pages.createCatPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = Pages.createCatPage })
end

function OpenEditCategoryMenu()
    Pages.editCatPage = BCCShopsMainMenu:RegisterPage("bcc-shops:editCategory")
    Pages.editCatPage:RegisterElement('header', {
        value = _U('editCategory'),
        slot = "header"
    })

    local categories = exports['feather-core']:CallRPCAsync("bcc-shops:GetAllCategories", {})

    for _, cat in ipairs(categories) do
        local displayLabel = (cat.label and cat.label ~= "" and cat.label) or cat.name or _U("unknownCategory")
        Pages.editCatPage:RegisterElement('button', {
            label = displayLabel,
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            local renamePage = BCCShopsMainMenu:RegisterPage("bcc-shops:renameCategory")
            renamePage:RegisterElement('header', {
                value = _U('renameCategory'),
                slot = "header"
            })
            local newName  = cat.name
            local newLabel = (cat.label and cat.label ~= "" and cat.label) or cat.name

            renamePage:RegisterElement('input', {
                label = _U('categoryName'),
                slot = "content",
                type = "text",
                default = cat.name
            }, function(data)
                newName = data.value
            end)

            renamePage:RegisterElement('input', {
                label = _U('categoryLabel'),
                slot = "content",
                type = "text",
                default = (cat.label and cat.label ~= "" and cat.label) or cat.name
            }, function(data)
                newLabel = data.value
            end)
            renamePage:RegisterElement('line', {
                slot = "footer",
                style = {}
            })
            renamePage:RegisterElement('button', {
                label = _U("submitChanges"),
                slot = "footer",
                style = {},
                sound = {
                    action = "SELECT",
                    soundset = "RDRO_Character_Creator_Sounds"
                }
            }, function()
                exports['feather-core']:CallRPC("bcc-shops:EditCategory", {
                    id = cat.id,
                    name = newName,
                    label = (newLabel and newLabel:match("%S")) and newLabel or newName
                }, function(success)
                    if success then
                        Pages.editCatPage:RouteTo()
                        Notify(_U("categoryUpdatedSuccess"), "success", 4000)
                    else
                        Notify(_U("categoryUpdatedFail"), "error", 4000)
                    end
                end)
            end)

            renamePage:RegisterElement('button', {
                label = _U('backButton'),
                slot = "footer",
                style = {},
                sound = {
                    action = "SELECT",
                    soundset = "RDRO_Character_Creator_Sounds"
                }
            }, function()
                Pages.editCatPage:RouteTo()
            end)

            renamePage:RegisterElement('bottomline', {
                slot = "footer",
                style = {}
            })

            BCCShopsMainMenu:Open({ startupPage = renamePage })
        end)
    end

    Pages.editCatPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    Pages.editCatPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        Pages.CategoryPage:RouteTo()
    end)

    Pages.editCatPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = Pages.editCatPage })
end

function OpenEditNPCShopPage(shop)
    Pages.editPage = BCCShopsMainMenu:RegisterPage("bcc-shops:editnpcshop_" .. shop.shop_id)
    Pages.editPage:RegisterElement("header", {
        value = _U("editShopHeader"),
        slot = "header"
    })

    local fields = {
        { key = "shop_name",     label = _U("editShopName") },
        { key = "shop_location", label = _U("editShopLocation") },
        { key = "inv_limit",     label = _U("editInventoryLimit") },
        { key = "webhook_link",  label = _U("editWebhookLink") },
        { key = "ledger",        label = _U("editLedgerAmount") },
        { key = "blip_hash",     label = _U("editBlipHash") },
        { key = "npc_model",     label = _U("editNPCModel") },
        { key = "show_blip",     label = _U("editShowBlip") },
    }

    local edits = {}

    for _, field in ipairs(fields) do
        Pages.editPage:RegisterElement("input", {
            label = field.label,
            placeholder = tostring(shop[field.key] or ""),
            default = tostring(shop[field.key] or ""),
            slot = "content"
        }, function(value)
            edits[field.key] = value.value or value
        end)
    end

    Pages.editPage:RegisterElement("line", { slot = "footer" })

    Pages.editPage:RegisterElement("button", {
        label = _U("submitChanges"),
        slot = "footer",
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        edits.shopId   = shop.shop_id
        edits.shop_type = shop.shop_type

        exports['feather-core']:CallRPC("bcc-shops:EditShop", edits, function(success)
            if success then
                Notify(_U("itemUpdated"), "success", 4000)
                Pages.npcListPage:RouteTo()
            else
                Notify(_U("itemUpdatedFail"), "error", 4000)
            end
        end)
    end)

    Pages.editPage:RegisterElement("button", {
        label = _U("backButton"),
        slot = "footer",
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        Pages.npcListPage:RouteTo()
    end)

    Pages.editPage:RegisterElement("bottomline", { slot = "footer" })
    BCCShopsMainMenu:Open({ startupPage = Pages.editPage })
end

function OpenEditPlayerShopPage(shop)
    Pages.editPage = BCCShopsMainMenu:RegisterPage("bcc-shops:editplayershop_" .. shop.shop_id)
    Pages.editPage:RegisterElement("header", {
        value = _U("editShopHeader"),
        slot = "header"
    })

    local fields = {
        { key = "shop_name",     label = _U("editShopName") },
        { key = "shop_location", label = _U("editShopLocation") },
        { key = "inv_limit",     label = _U("editInventoryLimit") },
        { key = "webhook_link",  label = _U("editWebhookLink") },
        { key = "ledger",        label = _U("editLedgerAmount") },
        { key = "blip_hash",     label = _U("editBlipHash") },
        { key = "npc_model",     label = _U("editNPCModel") },
        { key = "show_blip",     label = _U("editShowBlip") },
    }

    local edits = {}

    for _, field in ipairs(fields) do
        Pages.editPage:RegisterElement("input", {
            label = field.label,
            placeholder = tostring(shop[field.key] or ""),
            default = tostring(shop[field.key] or ""),
            slot = "content"
        }, function(value)
            edits[field.key] = value.value or value
        end)
    end

    Pages.editPage:RegisterElement("line", { slot = "footer" })

    Pages.editPage:RegisterElement("button", {
        label = _U("submitChanges"),
        slot = "footer",
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        edits.shopId   = shop.shop_id
        edits.shop_type = shop.shop_type

        exports['feather-core']:CallRPC("bcc-shops:EditShop", edits, function(success)
            if success then
                Notify(_U("itemUpdated"), "success", 4000)
                Pages.playerListPage:RouteTo()
            else
                Notify(_U("itemUpdatedFail"), "error", 4000)
            end
        end)
    end)

    Pages.editPage:RegisterElement("button", {
        label = _U("backButton"),
        slot = "footer",
        sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }
    }, function()
        Pages.playerListPage:RouteTo()
    end)

    Pages.editPage:RegisterElement("bottomline", { slot = "footer" })
    BCCShopsMainMenu:Open({ startupPage = Pages.editPage })
end

-- Open Delete Category Menu
function OpenDeleteCategoryMenu()
    local deleteCatPage = BCCShopsMainMenu:RegisterPage("bcc-shops:deleteCategory")
    deleteCatPage:RegisterElement('header', {
        value = _U('deleteCategory'),
        slot = "header"
    })

    local categories = exports['feather-core']:CallRPCAsync("bcc-shops:GetAllCategories", {})

    for _, cat in ipairs(categories) do
        deleteCatPage:RegisterElement('button', {
            label = (cat.label and cat.label ~= "" and cat.label) or cat.name or _U("unknownCategory"),
            slot = "content",
            style = {},
            sound = {
                action = "SELECT",
                soundset = "RDRO_Character_Creator_Sounds"
            }
        }, function()
            local confirmDeletePage = BCCShopsMainMenu:RegisterPage("bcc-shops:confirmDeleteCategory")

            confirmDeletePage:RegisterElement('header', {
                value = _U('confirmDeleteCategory'),
                slot = "header"
            })
            confirmDeletePage:RegisterElement("button", {
                label = _U("yes"),
                slot = "content",
                style = {},
                sound = {
                    action = "SELECT",
                    soundset = "RDRO_Character_Creator_Sounds"
                }
            }, function()
                exports['feather-core']:CallRPC("bcc-shops:DeleteCategory", { id = cat.id }, function(success)
                    if success then
                        Notify(_U("categoryDeletedSuccess"), "success", 4000)
                        deleteCatPage:RouteTo()
                    else
                        Notify(_U("categoryDeletedFail"), "error", 4000)
                    end
                end)
            end)
            confirmDeletePage:RegisterElement("button", {
                label = _U("no"),
                slot = "content",
                style = {},
                sound = {
                    action = "SELECT",
                    soundset = "RDRO_Character_Creator_Sounds"
                }
            }, function()
                deleteCatPage:RouteTo()
            end)
            BCCShopsMainMenu:Open({ startupPage = confirmDeletePage })
        end)
    end

    deleteCatPage:RegisterElement('line', {
        slot = "footer",
        style = {}
    })

    deleteCatPage:RegisterElement('button', {
        label = _U('backButton'),
        slot = "footer",
        style = {},
        sound = {
            action = "SELECT",
            soundset = "RDRO_Character_Creator_Sounds"
        }
    }, function()
        Pages.CategoryPage:RouteTo()
    end)

    deleteCatPage:RegisterElement('bottomline', {
        slot = "footer",
        style = {}
    })

    BCCShopsMainMenu:Open({ startupPage = deleteCatPage })
end
