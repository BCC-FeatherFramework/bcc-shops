# BCC Shops Feather integration

Status: BCC-side Economy preparation; **not ready for live payments with the
currently installed Economy permissions**. Economy and BCC Banks are unchanged.

The existing BCC menus, resource name, catalog, management, configuration and
translations remain in place. Character identity comes directly from Core and
Character. Shops no longer depends on Banks or exposes wallet credit/debit
compatibility functions. Monetary operations call named feather-economy exports
directly; there is no forwarding Economy adapter.

## Prepared NPC-store purchases

1. Resolve server character identity and validate shop proximity, catalog row,
   quantity, level, currency and price. Client totals are ignored.
2. Read currency precision, character wallets and the system sink through Economy.
   Amounts use integer minor units.
3. Reserve stock and persist purchase intent in one Shops database transaction.
4. Call Transfer from the buyer wallet to the currency's system sink using
   shop.purchase, shop_order and a stable key derived from the stored order.
5. Persist the Economy transaction receipt before item/weapon delivery.
6. Mark delivery started before calling Inventory/Weapons; save completion.

bcc_shop_payments contains workflow receipts, never wallet/shop balances.
Exact retries replay completed receipts without charging or granting again.
Client request IDs persist through a lost RPC response and resource restart.
An unfinished order blocks new orders for that character. Retrying accepted
payment intent uses its original price/accounts; initial acceptance checks
current catalog terms under lock.

The installed Inventory/Weapons grant methods are not idempotent. Interruption
after delivery_started, a partial weapon batch, or an uncertain grant requires
staff reconciliation. No blind re-grant or automatic refund runs. Paid orders
waiting for inventory space can be retried with their existing request IDs.
Confirmed insufficient-funds transfer rejection releases stock transactionally.
Unknown payment outcomes retain the original intent/key.

## Provider blockers

- Economy currently authorizes feather-shops, not bcc-shops. Its unchanged access
  lists reject BCC wallet provisioning/reads and transfers. Required access, if
  later approved: trustedReaders, trustedProvisioners, trustedTransactors.
  Do not grant trustedSuppliers for ordinary purchases.
- Economy has no independent shop/business-account API. Player-shop purchases,
  player sales to any shop, ledger deposits/withdrawals and NPC customer purchases
  return shop_accounts_unsupported before inventory/stock mutation.
- Existing bcc_shops.ledger values remain as migration evidence and historical
  display values, not spendable Economy money. Management cannot edit this
  column; NPC simulation cannot credit it. No automatic import, currency issuance,
  account impersonation or SQL access to Economy tables is implemented.
- NPC-store purchases, once authorized, settle to Economy's shared system sink.
  This cannot fund seller payouts or ledger withdrawals.
- Audit integration and unrelated existing catalog-management authorization
  remain separate unfinished work. This is not full masterplan compliance.

## Validation and operation

Start feather-economy and the other manifest dependencies before bcc-shops.
Banks is not required. The server-console diagnostic is read-only:

```text
restart bcc-shops
BccShopsEconomyStatus
```

With the unchanged Economy configuration, expect authorization_denied. Ready
resource state does not imply payment access. Do not deploy this preparation
expecting existing buying/selling availability. Preserve old wallet/ledger data
until a separate migration is approved and reconciled.

Offline tests: tests/payments.lua covers mocked dependency failures, authoritative
pricing, stock rollback, duplicate requests, payment replay and uncertain delivery.
Run from the bcc-shops directory with Lua 5.4: lua tests/payments.lua.
Mocks do not validate MySQL transactions or RedM. Before activation, live-test
permission failures, items/weapons, concurrent last-stock purchases, session
changes, lost responses, restarts and interrupted-delivery reconciliation.
