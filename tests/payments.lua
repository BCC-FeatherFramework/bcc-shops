-- Run from bcc-shops with Lua 5.4. Mocked workflow tests; no database/server needed.
local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}; for k, child in pairs(v) do out[k] = copy(child) end; return out
end
local function encode(v)
    if type(v) == 'string' then return string.format('%q', v) end
    if type(v) ~= 'table' then return tostring(v) end
    local keys, out = {}, {}; for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = '[' .. encode(k) .. ']=' .. encode(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
end
json = { encode = encode, decode = function(v) return assert(load('return ' .. v, nil, 't', {}))() end }
Config = { Payments = { maximumQuantity = 100, maximumDistance = 5, maximumAmount = 1000000000000 } }
local db, flags, calls, receiptCache, balance, serial, fixture
local character = { source = 1, characterId = 'character-a', accountId = 'account-a', sessionId = 'session-a', xp = 0 }
local function ok(v) return { ok = true, value = v } end
local function err(code) return { ok = false, code = code, message = code } end
function GetResourceState() return flags.stopped and 'stopped' or 'started' end
function GetPlayerPed() return 1 end
function GetEntityCoords() return { x = flags.far and 100 or 0, y = 0, z = 0 } end
function getLevelFromXP() return 0 end
ShopsCore = { GetCharacterContext = function()
    local c = copy(character); if flags.sessionChanged then c.sessionId = 'another-session' end
    return { character = c }
end }
ShopsInventory = {
    canCarryItem = function() return not flags.full end,
    addItem = function(_, _, _, qty, charId)
        assert(charId == character.characterId, 'delivery must bind captured identity')
        calls.grants = calls.grants + 1; calls.items = calls.items + qty
        if flags.grantFailure then error('uncertain inventory outcome') end
        return true
    end,
    createWeapon = function(_, _, _, charId)
        assert(charId == character.characterId)
        calls.grants = calls.grants + 1
        if flags.grantFailure and calls.grants > 1 then error('partial weapon delivery') end
        return 'instance-' .. calls.grants
    end
}
local economy = {
    GetCapabilities = function() return ok({ contract = flags.contract or 1, state = 'ready', features = { transfers = 1, idempotency = 1 } }) end,
    GetCurrency = function(_, currency)
        calls.currency = currency
        return ok({ code = currency, precision = 2, enabled = true })
    end,
    EnsureCharacterWallets = function(_, request)
        calls.wallets = calls.wallets + 1
        if flags.denied then return err('authorization_denied') end
        return ok({ { accountId = 'wallet', ownerType = 'character', ownerId = request.characterId,
            accountType = 'wallet', currency = calls.currency, status = 'open', balance = balance } })
    end,
    GetSystemAccount = function(_, request) return ok({ accountId = 'sink', currency = request.currency,
        status = 'open', accountType = 'system_sink' }) end,
    Transfer = function(_, request)
        calls.transfer = calls.transfer + 1
        if receiptCache[request.idempotencyKey] then return copy(receiptCache[request.idempotencyKey]) end
        if flags.insufficient then return err('insufficient_funds') end
        if flags.transferDenied then return err('authorization_denied') end
        if flags.reenter then
            flags.reenter = false
            local r = ShopsPayments.Purchase(copy(fixture), 1, false)
            assert(r.code == 'purchase_pending'); calls.reentered = true
        end
        balance = balance - request.amount; calls.posts = calls.posts + 1
        local result = ok({ transactionId = 'transaction-' .. calls.posts, amount = request.amount,
            currency = request.currency, fromAccountId = request.fromAccountId, toAccountId = request.toAccountId })
        receiptCache[request.idempotencyKey] = copy(result)
        if flags.lostPaymentReply then flags.lostPaymentReply = false; error('payment committed, reply lost') end
        if flags.sessionAfterPay then flags.sessionChanged = true end
        return result
    end
}
local handlers = {}
exports = { ['feather-economy'] = economy,
    ['feather-core'] = { RegisterRPC = function(_, name, fn) handlers[name] = fn end } }
function CreateThread() end
function ShopTranslator() return function(key) return key end end
function NotifyClient() end
local function query(sql, args)
    sql = sql:gsub('%s+', ' ')
    if sql:find('SELECT i.*', 1, true) then
        if flags.noOffer then return {} end
        local row = copy(db.item)
        if flags.priceRace and sql:find('FOR UPDATE', 1, true) then row.buy_price = row.buy_price + 1 end
        return flags.ambiguous and { row, copy(row) } or { row }
    end
    if sql:find('SELECT state FROM', 1, true) then return { { state = db.orders[args[1]].state } } end
    if sql:find('SELECT item_id FROM', 1, true) or sql:find('SELECT weapon_id FROM', 1, true) then return { copy(db.item) } end
    if sql:find('SET buy_quantity=buy_quantity-', 1, true) then db.item.buy_quantity = db.item.buy_quantity - args[1]; return 1 end
    if sql:find('SET buy_quantity=buy_quantity+', 1, true) then db.item.buy_quantity = db.item.buy_quantity + args[1]; return 1 end
    if sql:find('INSERT INTO bcc_shop_payments', 1, true) then
        if flags.insertFailure then error('insert failed') end
        db.orders[args[1]] = { order_id = args[1], buyer_character_id = args[2], request_id = args[3],
            fingerprint = args[4], stock_id = args[5], is_weapon = args[6], payload_json = args[7], state = 'payment_pending' }
        return 1
    end
    if sql:find("SET state='rejected'", 1, true) then db.orders[args[2]].state = 'rejected'; return 1 end
    error('Unexpected SQL: ' .. sql)
end
MySQL = {
    query = { await = query },
    scalar = { await = function(sql, args)
        if sql == 'SELECT UUID()' then serial = serial + 1; return 'order-' .. serial end
        for _, order in pairs(db.orders) do
            if order.buyer_character_id == args[1] and order.state ~= 'fulfilled' and order.state ~= 'rejected' then return order.order_id end
        end
    end },
    single = { await = function(_, args)
        for _, order in pairs(db.orders) do
            if order.buyer_character_id == args[1] and order.request_id == args[2] then return copy(order) end
        end
    end },
    update = { await = function(sql, args)
        if sql:find("state='paid'", 1, true) and sql:find('payment_transaction_id', 1, true) then
            if flags.lostReceiptWrite then flags.lostReceiptWrite = false; error('receipt write lost') end
            local order = db.orders[args[2]]; order.state = 'paid'; order.payment_transaction_id = args[1]; return 1
        elseif sql:find("SET state='delivery_started'", 1, true) then
            local order = db.orders[args[1]]; assert(order.state == 'paid'); order.state = 'delivery_started'
            if flags.stopBeforeGrant then flags.stopBeforeGrant = false; error('restart before grant') end
            return 1
        elseif sql:find("SET state='delivery_review'", 1, true) then
            db.orders[args[2]].state = 'delivery_review'; db.orders[args[2]].delivery_json = args[1]; return 1
        elseif sql:find("SET state='fulfilled'", 1, true) then
            if flags.lostDeliveryWrite then flags.lostDeliveryWrite = false; error('lost delivery receipt') end
            local order = db.orders[args[2]]; order.state = 'fulfilled'; order.delivery_json = args[1]; return 1
        elseif sql:find('SET last_error', 1, true) then db.orders[args[2]].last_error = args[1]; return 1 end
        error('Unexpected update: ' .. sql)
    end },
    startTransaction = function(body)
        local before = copy(db)
        local passed, committed = pcall(body, query)
        if not passed or committed ~= true then db = before; return false end
        return true
    end
}
local function reset()
    flags, receiptCache, balance, serial = {}, {}, 10000, 0
    calls = { wallets = 0, transfer = 0, posts = 0, grants = 0, items = 0 }
    db = { orders = {}, item = { item_id = 1, weapon_id = 1, shop_id = 1, shop_name = 'Store',
        is_npc_shop = 1, pos_x = 0, pos_y = 0, pos_z = 0, currency_type = 'cash',
        buy_quantity = 10, buy_price = 1.25, item_label = 'Apple', weapon_label = 'Weapon', level_required = 0 } }
    ShopsPaymentSchemaReady = true
    dofile('server/helpers/payments.lua')
    fixture = { shopName = 'Store', itemName = 'apple', weaponName = 'weapon_test', quantity = 2,
        total = 0.01, requestId = '1234567890abcdef' }
end
local count = 0
local function test(name, run)
    reset(); run(); count = count + 1; print('PASS ' .. name)
end
local function buy(weapon) return ShopsPayments.Purchase(copy(fixture), 1, weapon) end
local function state() for _, order in pairs(db.orders) do return order.state end end
local function unchanged() assert(balance == 10000 and db.item.buy_quantity == 10 and calls.grants == 0 and not next(db.orders)) end

test('permission denial cannot alter stock, money or inventory', function()
    flags.denied = true; assert(buy().code == 'authorization_denied'); unchanged()
end)
test('provider stopped and incompatible contract fail before mutation', function()
    flags.stopped = true; assert(buy().code == 'economy_unavailable'); unchanged()
    flags.stopped = false; flags.contract = 2; assert(buy().code == 'economy_not_ready'); unchanged()
end)
test('server catalog overrides client total; exact retry never charges/grants twice', function()
    local r = buy(); assert(r.ok and r.value.amount == 250 and balance == 9750)
    assert(db.item.buy_quantity == 8 and calls.items == 2)
    dofile('server/helpers/payments.lua') -- resource restart
    local again = buy(); assert(again.ok and again.value.replayed and calls.posts == 1 and calls.grants == 1)
end)
test('same ID cannot purchase a different quantity', function()
    assert(buy().ok); fixture.quantity = 3
    assert(buy().code == 'idempotency_conflict' and calls.posts == 1)
end)
test('fractional, negative, infinite and NaN quantities rejected', function()
    for _, q in ipairs({ 0, -1, 1.5, math.huge, 0/0 }) do fixture.quantity = q; assert(not buy().ok); unchanged() end
end)
test('invalid precision and unrepresentable price rejected', function()
    assert(ShopsPayments.ToUnits(1.25, 2) == 125)
    assert(not ShopsPayments.ToUnits(1.001, 2))
    db.item.buy_price = -1; assert(buy().code == 'invalid_price'); unchanged()
end)
test('gold uses the matching Economy currency and integer amount', function()
    db.item.currency_type = 'gold'; local r = buy()
    assert(r.ok and r.value.currency == 'gold' and r.value.amount == 250)
end)
test('player shops and ambiguous catalog rows fail before mutation', function()
    db.item.owner_id = 'owner'; db.item.is_npc_shop = 0
    assert(buy().code == 'shop_accounts_unsupported'); unchanged()
    db.item.owner_id = nil; db.item.is_npc_shop = 1; flags.ambiguous = true
    assert(buy().code == 'catalog_unavailable'); unchanged()
end)
test('proximity, capacity, stock and level checks precede payment', function()
    flags.far = true; assert(buy().code == 'not_at_shop'); unchanged()
    flags.far = false; flags.full = true; assert(buy().code == 'inventory_full'); unchanged()
    flags.full = false; db.item.buy_quantity = 1; assert(buy().code == 'insufficient_stock'); assert(calls.posts == 0)
    db.item.buy_quantity = 10; db.item.level_required = 1; assert(buy().code == 'level_required'); unchanged()
end)
test('catalog change under lock and receipt insert failure roll back stock', function()
    flags.priceRace = true; assert(buy().code == 'offer_changed'); unchanged()
    flags.priceRace = false; flags.insertFailure = true; assert(not buy().ok); unchanged()
end)
test('concurrent entry for the same character is rejected', function()
    flags.reenter = true; assert(buy().ok and calls.reentered and calls.posts == 1)
end)
test('definitive insufficient funds releases reservation exactly once', function()
    flags.insufficient = true; assert(buy().code == 'purchase_rejected')
    assert(state() == 'rejected' and db.item.buy_quantity == 10 and balance == 10000)
    assert(buy().code == 'purchase_rejected' and db.item.buy_quantity == 10)
end)
test('lost payment response replays original Economy key after restart', function()
    flags.lostPaymentReply = true; assert(not buy().ok and calls.posts == 1 and calls.grants == 0)
    dofile('server/helpers/payments.lua'); assert(buy().ok and calls.posts == 1 and calls.grants == 1)
end)
test('lost local payment receipt recovers without another debit', function()
    flags.lostReceiptWrite = true; assert(not buy().ok and state() == 'payment_pending')
    assert(buy().ok and calls.posts == 1)
end)
test('uncertain payment blocks new request IDs', function()
    flags.transferDenied = true; assert(buy().code == 'payment_pending')
    fixture.requestId = 'fedcba0987654321'; assert(buy().code == 'purchase_pending' and calls.posts == 0)
end)
test('session changes after payment cannot deliver to another session', function()
    flags.sessionAfterPay = true; assert(buy().code == 'purchase_pending' and calls.grants == 0 and state() == 'paid')
    flags.sessionAfterPay = false; flags.sessionChanged = false; assert(buy().ok and calls.posts == 1)
end)
test('unknown grant and lost delivery receipt never re-grant', function()
    flags.grantFailure = true; assert(buy().code == 'delivery_review' and calls.grants == 1)
    flags.grantFailure = false; assert(buy().code == 'delivery_review' and calls.grants == 1)
end)
test('restart after delivery intent requires review, not blind grant', function()
    flags.stopBeforeGrant = true; assert(not buy().ok and state() == 'delivery_started')
    dofile('server/helpers/payments.lua'); assert(buy().code == 'delivery_review' and calls.grants == 0)
end)
test('lost fulfilled write cannot duplicate delivered items', function()
    flags.lostDeliveryWrite = true; assert(not buy().ok and calls.grants == 1)
    assert(buy().code == 'delivery_review' and calls.grants == 1)
end)
test('partial weapon delivery cannot retry or refund automatically', function()
    flags.grantFailure = true; assert(buy(true).code == 'delivery_review' and calls.grants == 2)
    for _, order in pairs(db.orders) do assert(#json.decode(order.delivery_json) == 1) end
    flags.grantFailure = false; assert(buy(true).code == 'delivery_review' and calls.grants == 2 and calls.posts == 1)
end)
test('all unsupported RPCs reject without monetary or inventory activity', function()
    dofile('server/services/modify.lua'); dofile('server/services/ledger.lua')
    for _, name in ipairs({ 'SellItem', 'SellWeapon', 'ModifyLedger', 'PurchaseItemNPC', 'PurchaseWeaponNPC' }) do
        local answered = false
        handlers['bcc-shops:' .. name]({}, function(success, result)
            answered = true; assert(not success and result.code == 'shop_accounts_unsupported')
        end, 1)
        assert(answered); unchanged()
    end
end)
test('client retains uncertain request ID across restart and ignores stale callbacks', function()
    local kvp = {}
    function GetResourceKvpString(k) return kvp[k] end
    function SetResourceKvp(k, v) kvp[k] = v end
    function DeleteResourceKvp(k) kvp[k] = nil end
    dofile('client/feather/init.lua')
    local request, key = BeginShopPayment('Store', 'apple', 2, false)
    FinishShopPayment(key, request, false, { code = 'payment_pending' })
    dofile('client/feather/init.lua')
    local replay = BeginShopPayment('Store', 'apple', 2, false); assert(replay == request)
    FinishShopPayment(key, request, true)
    local nextRequest = BeginShopPayment('Store', 'apple', 2, false); assert(nextRequest ~= request)
    FinishShopPayment(key, request, true)
    assert(GetResourceKvpString(key) == nextRequest)
end)
print(('Payment workflow tests: %d passed'):format(count))
