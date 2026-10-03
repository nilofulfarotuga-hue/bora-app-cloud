# Auditoria Total — 2026-04-30

> Sessão: AUDITORIA TOTAL + IMPLEMENTAÇÃO COMPLETA
> Branch: `autonomous-night-2026-04-29` (HEAD `1a901b2`)
> Project Supabase: `ojykpzwqrtusfeakzrna` (LIVE)

## Mapa mental do estado actual

### Backend (Supabase prod)

**Tabelas novas confirmadas (8)**:
- `client_wallets`, `wallet_transactions` — Wallet 80/20
- `cancellation_requests` — F4 cancelamentos com aprovação
- `promo_codes`, `promo_code_uses` — F9 promos
- `referral_codes`, `referral_invites` — F10 convites
- `partner_status_override` — admin overrides parceiro

**RPCs admin (43 confirmadas listadas)**:
admin_approve_cancellation, admin_approve_driver, admin_ban_client/driver, admin_cancel_order, admin_clear_partner_override, admin_create_broadcast, admin_create_promo_code, admin_dashboard_metrics, admin_deactivate_promo_code, admin_get_client_history, admin_get_user_tokens, admin_grant_tokens, admin_grant_wallet_free, admin_kpi_avg_ticket, admin_kpi_conversion, admin_kpi_hot_zones, admin_list_audit_action_types, admin_list_audit_log, admin_list_broadcasts, admin_list_cancellation_requests, admin_list_clients, admin_list_complaints, admin_list_products_by_partner, admin_list_promo_codes, admin_list_settings, admin_list_wallets, admin_partners_with_counts, admin_reactivate_driver, admin_reject_cancellation, admin_reject_driver, admin_revoke_token_grant, admin_revoke_wallet_free, admin_set_partner_override, admin_set_partner_special_date, admin_set_product_availability, admin_soft_delete_driver, admin_unban_client, admin_update_complaint_status, admin_update_driver, admin_update_partner_data, admin_update_partner_hours, admin_update_product_price, admin_update_setting.

**RPCs em FALTA (a criar)**:
- ❌ `admin_realtime_metrics` (D1)
- ❌ `admin_live_orders` (B1)
- ❌ `admin_live_drivers` (B1)
- ❌ `driver_update_location` (B1)
- ❌ `admin_partner_sales_summary` (B2)

**Tabelas em FALTA (a criar)**:
- ❌ `driver_locations` (B1)

**Edge Functions ACTIVE (19)**:
Confirmadas: dispatch-engine v38, stripe-webhook v15, refund v12, cancel-order-with-choice v1, execute-cancellation v1, create-payment-intent v17, create-mbway-payment-intent v11, notify-driver/client/partner, admin-cancel-order v1, admin-force-driver-logout v1, upload-avatar v1, charge-extra v8, client-cancel-order v8, delete-account v8, update-products v9, confirm-mbway-payment v11 (a apagar pós-testes).

**platform_settings**: 26 entradas (key column ainda a confirmar — esperava `setting_key`, é outra coisa).

### Flutter (`bora_app/lib/`)

**Admin screens (22 ficheiros)** em `lib/screens/admin/`:
admin_advanced_kpis_screen, admin_audit_log_screen, admin_cancellation_requests_screen, admin_catalog_screen, admin_clients_screen, admin_complaints_screen, admin_dashboard_screen, admin_drivers_screen, admin_driver_approval_screen, admin_driver_detail_screen, admin_driver_payments_screen, admin_orders_screen, admin_order_detail_screen, admin_partners_screen, admin_partner_detail_screen, admin_platform_settings_screen, admin_promo_codes_screen, admin_ratings_screen, admin_reservations_screen, admin_tokens_screen, admin_wallets_screen.

**Widgets/Services novos**: `admin_realtime_metrics_card.dart`, `refund_choice_dialog.dart`, `wallet_service.dart`.

**Cliente screens novos**: `wallet_history_screen.dart`, `referral_screen.dart`.

### TODOs in-line (do relatório wiring-cliente)

1. ⚠️ **W2 wallet debit não corre na DB** — UI mostra desconto mas `wallet_debit_for_order` não chamado em OrderStore.createOrder. **Comment in `cart_screen.dart:376`** marca a localização aproximada.
2. ⚠️ **`OrderModel.refundMethod` não está mapeado** — coluna existe em DB (migration 20260430130000) mas não no Dart model. `_RefundBanner` faz query directa.
3. ⚠️ **`share_plus` não está em pubspec** — `referral_screen` usa Clipboard fallback.

### Branches

- `autonomous-night-2026-04-29` ⭐ (current, HEAD `1a901b2`)
- `draft/01-jwt-vault` — JWT vault refactor (HIGH-RISK, defer)
- `draft/02-restaurants-uuid` — restaurants.id TEXT→UUID (PLAN-ONLY, defer)
- `draft/03-partner-open-dispatch` — dispatch valida is_partner_open (defer)

⚠️ NÃO EXISTE `draft/pricing-from-settings` — Grupo C1 vai ter de criar do zero ou ser deferido com plano.

### pubspec.yaml — packages relevantes

✅ Já tem: provider, supabase_flutter, google_maps_flutter, flutter_map, geolocator, geocoding, audioplayers, fl_chart, firebase_core, firebase_messaging, image_picker, image, http, flutter_stripe.

❌ FALTAM: `share_plus`, `csv`, `pdf`, `printing`.

### Bugs descobertos durante auditoria

1. **`platform_settings` schema** — query `SELECT setting_key FROM platform_settings` falhou. Coluna chama-se outra coisa. Investigar antes de pricing-from-settings refactor.
2. **`confirm-mbway-payment` Edge Fn** — marcada para apagar pós-testes mas ainda ACTIVE em prod. Bug latente.
3. **`mbway_debug_errors`** tem 1 row — vale a pena investigar pós-launch.

## Próximos passos

Implementar Grupos A→D em sequência. Grupo E só documentar.

## Verificação MCP

✅ 41 tabelas em `public` (incl 8 novas)
✅ 43 RPCs admin
✅ 19 Edge Functions ACTIVE
❌ `driver_locations` ausente
❌ 4 RPCs realtime/live/sales ausentes
