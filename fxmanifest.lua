fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

lua54 'yes'

author '@iseeyoucopy'
description 'Advanced NPC and Player Shops System for RedM'
version '1.2.3'

shared_scripts {
    'config.lua',
    'shared/locale.lua',
    'languages/*.lua',
    'itemsMaxBuyPriceConfig.lua',
    'itemsMaxSellPriceConfig.lua'
}

client_scripts {
    'client/feather/init.lua',
    'client/feather/menu_v2.lua',
    'client/client.lua',
    'client/controllers/*.lua',
	'client/services/*.lua',
    'client/menus/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/feather/init.lua',
    'server/dbupdater.lua',
	'server/main.lua',
    'server/helpers/*.lua',
    'server/services/*.lua',
}

files {
    'images/*.png'
}

dependencies {
    'oxmysql',
    'feather-core',
    'feather-character',
    'feather-roles',
    'feather-inventory',
    'feather-weapons',
    'feather-toolkit',
    'feather-notify',
    'feather-menu-v2',
    'bcc-banks'
}
