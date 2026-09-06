---
tema: backend-map · escopo: projeto · estado: atual · atualizado: 2026-07-01
id: backend-map-triggers-rls
tipo: conceito
origem: [Supabase project ojykpzwqrtusfeakzrna, information_schema.triggers, pg_policies]
ultima_confirmacao: 2026-07-08
zona: vermelha
confianca: auto
---

# Backend Map — Triggers & RLS

Índice: [backend-map.md](./backend-map.md). 🔴 = zona de dinheiro.

## Triggers por tabela (~72)

### `orders` (hub — 24 triggers) 🔴
`orders_post_to_ledger` 🔴 · `orders_financial_split` 🔴 · `orders_financial_lock` 🔴 · `orders_cash_settlement` 🔴 · `orders_enforce_cash_limit` 🔴 · `orders_enforce_payment_before_preparing` 🔴 · `orders_storeshopping_pickup_guard` 🔴 · `orders_auto_confirm_cod` 🔴 · `apply_client_debt_settlement_on_cash_delivery` 🔴 · `apply_client_debt_settlement_on_payment_paid` 🔴 · `trg_award_tokens_on_delivery` 🔴 · `trigger_credit_driver_on_delivery` 🔴 · `trg_recalc_earnings_on_assign` 🔴 · `trg_enforce_refund_cap` 🔴 · `trg_referral_reward` 🔴 · `orders_set_delivered_at` · `trg_dispatch_on_calling_driver` · `trg_set_dispatch_calling_since` · `tr_notify_driver_on_offer` · `trg_notify_on_order_cancel` · `trg_zz_set_purchase_flow_version` · `_trg_admin_notif_cancel_mid_delivery` · `_trg_admin_notif_refund_high`.

### `ledger_entries` 🔴
`ledger_no_delete` 🔴 · `ledger_no_update` 🔴 · `ledger_recompute_on_insert` 🔴 (append-only enforcement).

### `products`
`trg_products_auto_taxonomy` · `trg_products_set_category_root` · `trg_products_set_search_normalized` · `trg_products_set_updated_at`.

### `ratings`
`trg_driver_avg_rating` · `trg_restaurant_avg_rating` · `trg_zz_notify_partner_low_rating`.

### `reservations`
`trg_reservation_finished` · `trg_reservation_late_cancel` · `trg_reservation_seated` · `trg_reservation_notify_partner_new` · `_trg_admin_notif_reservation_noshow`.

### `reservation_waitlist`
`trg_waitlist_notify_partner_new`.

### `order_receipts_v2` 🔴
`trg_enqueue_errand_catalog` · `trg_notify_reimbursement_pending` 🔴.

### `tvde_rides` 🔴
`tr_notify_tvde_driver_on_offer` · `tr_tvde_dispatch_on_request`.

### `drivers`
`trg_sync_drivers_to_driver_locations`.

### `messages`
`trg_messages_notify_chat`.

### `wallet_transactions` 🔴
`trg_notify_on_cashback` 🔴.

### `complaints`
`_trg_admin_notif_complaint_high` · `trg_complaints_updated_at`.

### `client_wallets` 🔴
`_trg_admin_notif_wallet_debt_high` 🔴.

### `skill_suggestions`
`_trg_admin_notif_skill_critical`.

### `robot_crosstalk`
`trg_robot_crosstalk_notify_urgent`.

### `support_pending_actions`
`trg_zz_pending_action_notify_admin`.

### Outros (updated_at / touch)
`admin_ai_sessions` · `appointments` · `category_mapping` · `client_restaurant_profiles` · `client_search_history` (trim) · `pending_charges` · `restaurant_floor_plans` · `restaurant_pacing_rules` · `restaurant_tables` · `service_providers`.

## RLS — estado

**RLS ativo (`rowsecurity=true`) em 100% das 130 tabelas.**

### Tabelas com 0 policies (efetivamente fechadas — só service_role)
- **Backup/staging (67):** todos os `_backup_*`, `_continente_price_sources_*`, `_wells_price_sources_*`, `continente_price_staging`, `guarda_businesses`.
- **Robot internas (3):** `robot_runs`, `robot_suggestions`, `robot_audit_log`.

> RLS on + 0 policies = nega tudo por padrão (exceto service_role/edge fns). Intencional para estas tabelas de infraestrutura.

### Tabelas com mais policies (acesso multi-papel)
`orders` (8) · `products` (7) · `restaurants` (7) · `ratings` (6) · `client_addresses` (5) · `drivers` (5) · `order_receipts_v2` (5) · `messages` (4) · `order_purchase_items_v2` (4) · `users` (4) · `service_providers` (4).

### Financeiras — RLS restritiva (poucas policies, own-read)
`bora_tokens` (1) · `ledger_entries` (2) · `payouts` (1) · `driver_balances` (1) · `driver_transactions` (2) · `order_financials` (1) · `order_financial_transactions` (1) · `wallet_transactions` (2) · `client_wallets` (2) · `driver_weekly_settlements` (1) · `partner_weekly_settlements` (1) · `partner_reservation_payouts` (1) · `platform_settings` (1) · `tvde_driver_balances` (1).

Contagem total de policies distribuída por ~63 tabelas de domínio; nenhuma tabela de domínio ficou sem policy (só backups/robot-internas).
