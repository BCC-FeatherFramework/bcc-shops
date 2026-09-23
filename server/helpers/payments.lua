-- BCC owns purchase intent and stock; Economy owns every monetary posting.
ShopsPayments = {}
local active = {}
local function fail(code, message) return { ok = false, code = code, message = message } end
local function ok(value) return { ok = true, value = value } end

function ShopsPayments.ShopFundsUnavailable()
    return fail('shop_accounts_unsupported', 'Shop funds are unavailable until Economy supports shop accounts.')
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

function ShopsPayments.ToUnits(value, precision)
    value, precision = tonumber(value), tonumber(precision)
    if not finite(value) or value <= 0 or not precision or precision % 1 ~= 0
        or precision < 0 or precision > 6 then return nil end
    local scaled = value * 10 ^ precision
    if not finite(scaled) or scaled > Config.Payments.maximumAmount then return nil end
    local units = math.floor(scaled + 0.5)
    if units < 1 or math.abs(scaled - units) > 0.00001 then return nil end
    return units
end

function ShopsPayments.Quote(params, character, weapon)
    if type(params) ~= 'table' or type(params.shopName) ~= 'string' or #params.shopName > 255
        or type(params.quantity) ~= 'number' or not finite(params.quantity)
        or params.quantity % 1 ~= 0 or params.quantity < 1
        or params.quantity > Config.Payments.maximumQuantity then
        return fail('invalid_input', 'A valid shop and whole quantity are required.')
    end
    local name = weapon and params.weaponName or params.itemName
    if type(name) ~= 'string' or name == '' or #name > 255 then
        return fail('invalid_input', 'A valid catalog item is required.')
    end
    local tableName = weapon and 'bcc_shop_weapon_items' or 'bcc_shop_items'
    local nameColumn = weapon and 'weapon_name' or 'item_name'
    local rows = MySQL.query.await(('SELECT i.*, s.shop_name, s.is_npc_shop, s.owner_id, '
        .. 's.pos_x, s.pos_y, s.pos_z FROM %s i JOIN bcc_shops s ON s.shop_id = i.shop_id '
        .. 'WHERE s.shop_name = ? AND i.%s = ? LIMIT 2'):format(tableName, nameColumn),
        { params.shopName, name }) or {}
    if #rows ~= 1 then return fail('catalog_unavailable', 'The shop offer is unavailable or ambiguous.') end
    local item = rows[1]
    if tonumber(item.is_npc_shop) ~= 1 or item.owner_id ~= nil then
        return ShopsPayments.ShopFundsUnavailable()
    end
    if not weapon and (tonumber(item.is_weapon) == 1 or name:lower():match('^weapon_')) then
        return fail('invalid_input', 'Weapons require the weapon purchase route.')
    end
    local ped = GetPlayerPed(character.source)
    if not ped or ped == 0 then return fail('not_at_shop', 'Visit the shop to purchase.') end
    local pos = GetEntityCoords(ped)
    local x, y, z = tonumber(item.pos_x), tonumber(item.pos_y), tonumber(item.pos_z)
    if not x or not y or not z or ((pos.x-x)^2 + (pos.y-y)^2 + (pos.z-z)^2)
        > Config.Payments.maximumDistance ^ 2 then
        return fail('not_at_shop', 'Visit the shop to purchase.')
    end
    if getLevelFromXP(character.xp) < (tonumber(item.level_required) or 0) then
        return fail('level_required', 'Your level is too low for this offer.')
    end
    if (tonumber(item.buy_quantity) or 0) < params.quantity then
        return fail('insufficient_stock', 'The shop has insufficient stock.')
    end
    local currency = ({ cash = 'dollars', dollars = 'dollars', gold = 'gold' })[item.currency_type]
    if not currency then return fail('invalid_currency', 'The offer currency is unsupported.') end
    local definition = exports['feather-economy']:GetCurrency(currency)
    if not definition.ok then return definition end
    if type(definition.value) ~= 'table' or definition.value.enabled ~= true then
        return fail('invalid_currency', 'The offer currency is unavailable.')
    end
    local unitPrice = ShopsPayments.ToUnits(item.buy_price, definition.value.precision)
    if not unitPrice or unitPrice * params.quantity > Config.Payments.maximumAmount then
        return fail('invalid_price', 'The shop price is invalid.')
    end
    return ok({ shopId = item.shop_id, shopName = item.shop_name, itemName = name,
        stockId = weapon and item.weapon_id or item.item_id, weapon = weapon,
        quantity = params.quantity, unitPrice = unitPrice, amount = unitPrice * params.quantity,
        currency = currency, precision = definition.value.precision,
        label = (weapon and item.weapon_label or item.item_label) or name,
        levelRequired = tonumber(item.level_required) or 0 })
end

local function transaction(body)
    local result
    local called, committed = pcall(MySQL.startTransaction, function(query)
        result = body(query)
        return result and result.ok == true
    end)
    if called and committed == true then return result end
    if called and result and not result.ok then return result end
    return fail('persistence_failed', 'The purchase could not be recorded.')
end

local function orderFor(characterId, requestId)
    return MySQL.single.await('SELECT * FROM bcc_shop_payments WHERE buyer_character_id = ? AND request_id = ?',
        { characterId, requestId })
end

local function stockInfo(weapon)
    return weapon and 'bcc_shop_weapon_items' or 'bcc_shop_items', weapon and 'weapon_id' or 'item_id'
end

local function reserve(quote, character, requestId, fingerprint)
    local orderId = MySQL.scalar.await('SELECT UUID()')
    local tableName, idColumn = stockInfo(quote.weapon)
    local result = transaction(function(query)
        -- Lock the selected offer and recheck its price/owner before accepting intent.
        local rows = query(('SELECT i.*, s.owner_id, s.is_npc_shop FROM %s i '
            .. 'JOIN bcc_shops s ON s.shop_id=i.shop_id WHERE i.%s=? FOR UPDATE'):format(tableName, idColumn),
            { quote.stockId }) or {}
        local row = rows[1]
        if not row or tonumber(row.buy_quantity) < quote.quantity or row.owner_id ~= nil
            or tonumber(row.is_npc_shop) ~= 1 or tonumber(row.shop_id) ~= tonumber(quote.shopId)
            or ShopsPayments.ToUnits(row.buy_price, quote.precision) ~= quote.unitPrice
            or (tonumber(row.level_required) or 0) ~= quote.levelRequired
            or ({ cash = 'dollars', dollars = 'dollars', gold = 'gold' })[row.currency_type] ~= quote.currency then
            return fail('offer_changed', 'The shop offer changed. Please try again.')
        end
        query(('UPDATE %s SET buy_quantity=buy_quantity-? WHERE %s=?'):format(tableName, idColumn),
            { quote.quantity, quote.stockId })
        query([[INSERT INTO bcc_shop_payments
            (order_id, buyer_character_id, request_id, fingerprint, stock_id, is_weapon, payload_json, state)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'payment_pending')]],
            { orderId, character.characterId, requestId, fingerprint, quote.stockId, quote.weapon and 1 or 0,
                json.encode(quote) })
        return ok(true)
    end)
    if not result.ok then return result end
    local row = orderFor(character.characterId, requestId)
    return row and ok(row) or fail('persistence_failed', 'The purchase record is unavailable.')
end

local function reject(order, quote, code)
    return transaction(function(query)
        local rows = query('SELECT state FROM bcc_shop_payments WHERE order_id=? FOR UPDATE', { order.order_id }) or {}
        if not rows[1] or rows[1].state ~= 'payment_pending' then
            return fail('purchase_pending', 'The purchase needs reconciliation.')
        end
        local tableName, idColumn = stockInfo(quote.weapon)
        -- Never silently discard a reservation whose catalog row was deleted.
        local stock = query(('SELECT %s FROM %s WHERE %s=? FOR UPDATE'):format(idColumn, tableName, idColumn),
            { quote.stockId }) or {}
        if not stock[1] then return fail('purchase_pending', 'The reserved offer needs reconciliation.') end
        query(('UPDATE %s SET buy_quantity=buy_quantity+? WHERE %s=?'):format(tableName, idColumn),
            { quote.quantity, quote.stockId })
        query("UPDATE bcc_shop_payments SET state='rejected', last_error=? WHERE order_id=?", { code, order.order_id })
        return ok(true)
    end)
end

local function receipt(order, quote, replayed)
    return ok({ orderId = order.order_id, transactionId = order.payment_transaction_id,
        shopId = quote.shopId, itemName = quote.itemName, label = quote.label, quantity = quote.quantity,
        amount = quote.amount, total = quote.amount / 10 ^ quote.precision, currency = quote.currency,
        replayed = replayed == true })
end

local function purchase(params, character, weapon)
    if not ShopsPaymentSchemaReady then return fail('not_ready', 'Shop payments are not ready.') end
    if type(params) ~= 'table' or type(params.requestId) ~= 'string' or #params.requestId < 16
        or #params.requestId > 80 or not params.requestId:match('^[a-z0-9%-]+$') then
        return fail('invalid_input', 'A stable purchase request ID is required.')
    end
    if type(params.shopName) ~= 'string' or type(params.quantity) ~= 'number'
        or not finite(params.quantity) or params.quantity < 1 or params.quantity % 1 ~= 0
        or params.quantity > Config.Payments.maximumQuantity
        or type(weapon and params.weaponName or params.itemName) ~= 'string' then
        return fail('invalid_input', 'The purchase request is invalid.')
    end
    local fingerprint = json.encode({ params.shopName, weapon and params.weaponName or params.itemName,
        params.quantity, weapon })
    local order = orderFor(character.characterId, params.requestId)
    if order and order.fingerprint ~= fingerprint then
        return fail('idempotency_conflict', 'This request ID belongs to another purchase.')
    end
    local quote
    if order then
        quote = json.decode(order.payload_json)
        if order.state == 'fulfilled' then return receipt(order, quote, true) end
        if order.state == 'rejected' then return fail('purchase_rejected', 'This purchase was rejected.') end
        if order.state == 'delivery_started' or order.state == 'delivery_review' then
            return fail('delivery_review', 'This purchase delivery needs staff review.')
        end
    else
        if GetResourceState('feather-economy') ~= 'started' then
            return fail('economy_unavailable', 'Economy is unavailable.')
        end
        local capabilities = exports['feather-economy']:GetCapabilities()
        if not capabilities or not capabilities.ok or type(capabilities.value) ~= 'table'
            or capabilities.value.contract ~= 1 or capabilities.value.state ~= 'ready' then
            return fail('economy_not_ready', 'Economy Contract 1 is not ready.')
        end
        local features = capabilities.value.features or {}
        if features.transfers ~= 1 or features.idempotency ~= 1 then
            return fail('unsupported_capability', 'Economy transfers and idempotency are required.')
        end
        local pending = MySQL.scalar.await([[SELECT order_id FROM bcc_shop_payments WHERE buyer_character_id=?
            AND state NOT IN ('fulfilled','rejected') LIMIT 1]], { character.characterId })
        if pending then return fail('purchase_pending', 'An earlier purchase is still pending.') end
        local quoted = ShopsPayments.Quote(params, character, weapon)
        if not quoted.ok then return quoted end
        quote = quoted.value
        local wallets = exports['feather-economy']:EnsureCharacterWallets({ characterId = character.characterId })
        if not wallets.ok then return wallets end
        local wallet
        for _, account in ipairs(wallets.value) do
            if account.ownerType == 'character' and account.ownerId == character.characterId
                and account.accountType == 'wallet' and account.currency == quote.currency
                and account.status == 'open' and type(account.balance) == 'number' then wallet = account end
        end
        if not wallet then return fail('account_not_found', 'The character wallet is unavailable.') end
        local sink = exports['feather-economy']:GetSystemAccount({ currency = quote.currency, accountType = 'system_sink' })
        if not sink.ok then return sink end
        if type(sink.value) ~= 'table' or sink.value.accountType ~= 'system_sink'
            or sink.value.currency ~= quote.currency or sink.value.status ~= 'open' then
            return fail('invalid_provider_result', 'The settlement account is invalid.')
        end
        if wallet.balance < quote.amount then return fail('insufficient_funds', 'Insufficient wallet funds.') end
        if not ShopsInventory:canCarryItem(character.source, quote.itemName, quote.quantity) then
            return fail('inventory_full', 'You cannot carry this purchase.')
        end
        quote.fromAccountId, quote.toAccountId = wallet.accountId, sink.value.accountId
        quote.actorAccountId = character.accountId
        local reserved = reserve(quote, character, params.requestId, fingerprint)
        if not reserved.ok then return reserved end
        order = reserved.value
    end
    if order.state == 'payment_pending' then
        local paid = exports['feather-economy']:Transfer({ fromAccountId = quote.fromAccountId, toAccountId = quote.toAccountId,
            currency = quote.currency, amount = quote.amount, reasonCode = 'shop.purchase',
            referenceType = 'shop_order', referenceId = order.order_id,
            idempotencyKey = 'bcc-shop-payment:' .. order.order_id },
            { actorSource = character.source, actorAccountId = quote.actorAccountId,
                actorCharacterId = character.characterId, correlationId = order.order_id })
        if not paid.ok then
            -- Unknown outcomes retain the original intent/key. Only a confirmed
            -- insufficient-funds result proves this payment did not commit.
            if paid.code == 'insufficient_funds' then
                local rejected = reject(order, quote, paid.code)
                if not rejected.ok then return rejected end
                return fail('purchase_rejected', 'Insufficient wallet funds.')
            end
            MySQL.update.await('UPDATE bcc_shop_payments SET last_error=? WHERE order_id=?', { paid.code, order.order_id })
            return fail('payment_pending', 'Payment is pending. Retry this same purchase.')
        end
        if type(paid.value) ~= 'table' or type(paid.value.transactionId) ~= 'string'
            or paid.value.amount ~= quote.amount or paid.value.currency ~= quote.currency
            or paid.value.fromAccountId ~= quote.fromAccountId or paid.value.toAccountId ~= quote.toAccountId then
            return fail('payment_pending', 'The payment receipt needs reconciliation.')
        end
        local saved = MySQL.update.await([[UPDATE bcc_shop_payments SET state='paid', payment_transaction_id=?,
            last_error=NULL WHERE order_id=? AND state='payment_pending']], { paid.value.transactionId, order.order_id })
        if saved ~= 1 then return fail('purchase_pending', 'The payment receipt needs reconciliation.') end
        order.state, order.payment_transaction_id = 'paid', paid.value.transactionId
    end
    if order.state ~= 'paid' then return fail('purchase_pending', 'The purchase needs reconciliation.') end
    local current = ShopsCore.GetCharacterContext(character.source)
    if not current or current.character.characterId ~= character.characterId
        or current.character.sessionId ~= character.sessionId then
        return fail('purchase_pending', 'Reconnect with the purchasing character to finish delivery.')
    end
    if not ShopsInventory:canCarryItem(character.source, quote.itemName, quote.quantity) then
        return fail('purchase_pending', 'Make inventory space and retry this same purchase.')
    end
    -- Commit intent before the non-idempotent Inventory/Weapons call. A restart
    -- here requires review, never blind re-granting or a fresh currency issuance.
    local claimed = MySQL.update.await([[UPDATE bcc_shop_payments SET state='delivery_started'
        WHERE order_id=? AND state='paid']], { order.order_id })
    if claimed ~= 1 then return fail('delivery_review', 'Delivery is already in progress or needs review.') end
    local issuedInstances = {}
    local delivered = pcall(function()
        if weapon then
            for index = 1, quote.quantity do
                issuedInstances[#issuedInstances + 1] = ShopsInventory:createWeapon(character.source, quote.itemName, character.characterId,
                    ('bcc-shop-order:%s:%d'):format(order.order_id, index))
            end
            return
        end
        ShopsInventory:addItem(character.source, quote.itemName, quote.quantity, character.characterId)
    end)
    if not delivered then
        MySQL.update.await([[UPDATE bcc_shop_payments SET state='delivery_review', delivery_json=?,
            last_error='inventory_delivery_failed' WHERE order_id=?]], { json.encode(issuedInstances), order.order_id })
        return fail('delivery_review', 'Payment recorded; delivery needs staff review.')
    end
    local saved = MySQL.update.await([[UPDATE bcc_shop_payments SET state='fulfilled', delivery_json=?, last_error=NULL
        WHERE order_id=? AND state='delivery_started']], { json.encode(issuedInstances), order.order_id })
    if saved ~= 1 then return fail('delivery_review', 'Delivery receipt needs staff review.') end
    return receipt(order, quote, false)
end

function ShopsPayments.Purchase(params, source, weapon)
    local context = ShopsCore.GetCharacterContext(source)
    if not context then return fail('invalid_character', 'An active character is required.') end
    local character = context.character
    if active[character.characterId] then return fail('purchase_pending', 'A purchase is already in progress.') end
    active[character.characterId] = true
    local called, result = pcall(purchase, params, character, weapon == true)
    active[character.characterId] = nil
    if not called then
        print('[bcc-shops] Purchase interrupted; inspect bcc_shop_payments before retrying delivery.')
        return fail('purchase_pending', 'The purchase needs reconciliation; retain the same request ID.')
    end
    return result
end

function ShopsPayments.NotifyFailure(source, result)
    print(('[bcc-shops] payment unavailable: %s'):format(result.code))
    local pending = result.code == 'payment_pending' or result.code == 'purchase_pending'
        or result.code == 'delivery_review'
    NotifyClient(source, ShopTranslator(source)(pending and 'shop_payment_pending' or 'shop_payment_unavailable'), 'error', 5000)
end
