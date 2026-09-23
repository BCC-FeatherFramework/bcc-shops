Config = {
    defaultlang = "en_us", -- Fallback locale: en_us (English), ro (Romanian), pl (Polish).
    keys = {
        access = 0x760A9C6F, -- [G] Access Player menu
    },
    devMode = false,
    ManagementRoles = { 'admin', 'owner', 'moderator' }, -- Feather character role keys.
    DefaultPlayerXP = 0, -- Replace with your progression service when available.
    Payments = {
        maximumQuantity = 100,
        maximumDistance = 5.0,
        maximumAmount = 1000000000000 -- Integer minor units; Economy applies its own limits too.
    },
    ManageShopsCommand = "manageStores", 
    Webhook = "",
    WebhookTitle = 'BCC-Shops',
    WebhookAvatar = '',


    DefaultNPCModel = "u_m_m_valgenstoreowner_01",
    DefaultBlipHash = "1475879922",

    BlipStyles = {
        { label = "Animal Trapper",     blipName = "blip_shop_animal_trapper",    blipHash = -1406874050 },
        { label = "Barber",             blipName = "blip_shop_barber",            blipHash = -2090472724 },
        { label = "Blacksmith",         blipName = "blip_shop_blacksmith",        blipHash = -758970771 },
        { label = "Butcher",            blipName = "blip_shop_butcher",           blipHash = -1665418949 },
        { label = "Coach Fencing",      blipName = "blip_shop_coach_fencing",     blipHash = -1989306548 },
        { label = "Doctor",             blipName = "blip_shop_doctor",            blipHash = -1739686743 },
        { label = "Gunsmith",           blipName = "blip_shop_gunsmith",          blipHash = -145868367 },
        { label = "Horse",              blipName = "blip_shop_horse",             blipHash = 1938782895 },
        { label = "Horse Fencing",      blipName = "blip_shop_horse_fencing",     blipHash = -1456209806 },
        { label = "Horse Saddle",       blipName = "blip_shop_horse_saddle",      blipHash = 469827317 },
        { label = "Market Stall",       blipName = "blip_shop_market_stall",      blipHash = 819673798 },
        { label = "Shady Store",        blipName = "blip_shop_shady_store",       blipHash = 531267562 },
        { label = "Store",              blipName = "blip_shop_store",             blipHash = 1475879922 },
        { label = "Tackle",             blipName = "blip_shop_tackle",            blipHash = -852241114 },
        { label = "Tailor",             blipName = "blip_shop_tailor",            blipHash = 1195729388 },
        { label = "Train",              blipName = "blip_shop_train",             blipHash = 103490298 },
        { label = "Trainer",            blipName = "blip_shop_trainer",           blipHash = 1542275196 }
    },

    NPC = {
        npcBuyFromPlayerShop = true,
        purchaseInterval = 900000,

        -- thes next configs are unused in resource on this version, next version will be implemented new function with these values
        npcModels = {
            "g_m_m_unibanditos_01",
            "ge_delloboparty_females_01",
            "amsp_robsdgunsmith_males_01"
        },

        emotes = {
            "KIT_EMOTE_GREET_HAND_SHAKE_1",
            "KIT_EMOTE_GREET_HAT_TIP_1",
            "KIT_EMOTE_GREET_HEY_YOU_1"
        },

        idleScenarios = {
            { name = "WORLD_HUMAN_SMOKE_CIGAR", duration = 25000 },
            { name = "WORLD_HUMAN_WRITE_NOTEBOOK", duration = 22000 },
            { name = "WORLD_HUMAN_WAITING_IMPATIENT", duration = 30000 }
        },

        locations = {
            Blackwater = {
                meet = vector3(-815.65, -1330.41, 43.67),
                npcA = vector3(-769.78, -1318.04, 43.56),
                npcB = vector3(-770.74, -1298.85, 43.73)
            },
            Valentine = {
                 meet = vector3(-325.09, 822.11, 118.16),
                 npcA = vector3(-337.89, 805.3, 116.65),
                 npcB = vector3(-299.07, 804.02, 118.45)
            },
            Rhodes = {
                meet = vector3(1232.45, -1280.67, 76.45),
                npcA = vector3(1230.12, -1265.34, 76.45),
                npcB = vector3(1245.67, -1262.89, 76.45)
            },
        }
    },
    Notify = "feather-notify",
}
