# BCC Shops Feather port

Shops uses Feather Core RPC, Character UUIDs, Feather Inventory, Feather
Weapons issuance, Toolkit prompts/entities/blips, Notify, and Menu v2.
The Menu v2 adapter follows bcc-banks; HTML displays are rendered as plain text.

Start bcc-banks before bcc-shops. Banks exposes GetBankingContext so both
resources use the same temporary Economy wallets. This dependency can be
replaced once the shared Feather Economy resource is available.

Management uses Feather Roles GetActorRole and Config.ManagementRoles.
The default allowed character roles are admin, owner, and moderator.
Employment data is not published by Feather Character profiles.
Config.DefaultPlayerXP supplies shop progression until a progression provider
is connected; the default is 0 (level 0).

Existing owner_id columns are widened to UUID-capable VARCHAR(36). Old numeric
owner/access identifiers require an explicit mapping to Feather Character
UUIDs; widening does not map ownership automatically.

Validation: Lua 5.4 syntax checks and mocked service contract checks passed.
RedM smoke testing remains required: NPC and player shop purchases/sales,
weapon stocking/issuance, ledger deposits/withdrawals, management permissions,
access grants, menu pagination, reconnects, and resource restarts.

Localization registers namespaced shop keys through Feather Core for en_us, ro,
and pl. Account locale preferences select translations; Config.defaultlang
provides the fallback when a translation is unavailable.
