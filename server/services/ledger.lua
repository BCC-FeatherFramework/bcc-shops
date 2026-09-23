-- Preserve the BCC ledger route. Existing ledger values are migration evidence,
-- not spendable money. No wallet or local balance changes without shop accounts.
exports['feather-core']:RegisterRPC("bcc-shops:ModifyLedger", function(_, cb, src)
    local result = ShopsPayments.ShopFundsUnavailable()
    ShopsPayments.NotifyFailure(src, result)
    cb(false, { code = result.code })
end)
