-- Read-only diagnostic: never provisions wallets or moves money.
RegisterCommand('BccShopsEconomyStatus', function(source)
    if source ~= 0 then return end
    print(('[bcc-shops] payment schema: %s'):format(ShopsPaymentSchemaReady and 'ready' or 'not ready'))
    local called, capabilities = pcall(function() return exports['feather-economy']:GetCapabilities() end)
    if not called or type(capabilities) ~= 'table' or not capabilities.ok then
        print('[bcc-shops] Economy unavailable; payments are blocked.')
        return
    end
    print(('[bcc-shops] Economy contract=%s state=%s'):format(
        tostring(capabilities.value.contract), tostring(capabilities.value.state)))
    local read, account = pcall(function()
        return exports['feather-economy']:GetSystemAccount({ currency = 'dollars', accountType = 'system_sink' })
    end)
    print(('[bcc-shops] Economy account access: %s'):format(
        read and type(account) == 'table' and (account.ok and 'allowed' or account.code) or 'unavailable'))
    print('[bcc-shops] Transfer permission is checked by Economy when posting; this diagnostic moves no money.')
    print('[bcc-shops] Player shops, sales, ledger changes and NPC customers: blocked (shop accounts unsupported).')
    if ShopsPaymentSchemaReady then
        local states = DB.query('SELECT state, COUNT(*) AS total FROM bcc_shop_payments GROUP BY state') or {}
        for _, row in ipairs(states) do
            print(('[bcc-shops] purchase state=%s count=%s'):format(row.state, row.total))
        end
    end
end, true)
