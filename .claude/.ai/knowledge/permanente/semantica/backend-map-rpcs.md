---
tema: backend-map · escopo: projeto · estado: atual · atualizado: 2026-07-01
id: backend-map-rpcs
tipo: conceito
origem: [Supabase project ojykpzwqrtusfeakzrna, information_schema.routines]
ultima_confirmacao: 2026-07-08
zona: vermelha
confianca: auto
---

# Backend Map — Funções / RPCs (schema public)

~330 rotinas (inclui funções de trigger `_*` e alguns overloads). 🔴 = zona de dinheiro (existe; lógica NÃO descrita). Índice: [backend-map.md](./backend-map.md).

## 🔴 Dinheiro — pricing / order / settlement / payout / refund / wallet / token / finalize

Estas ~55 rotinas tocam €/tokens. NÃO alterar sem ordem explícita.

**Pricing / quote:** `pricing_calculate` 🔴 · `pricing_calculate_errand` 🔴 · `pricing_calculate_legacy_pre_settings` 🔴 · `quote_order_pricing` 🔴 · `tvde_calculate_fare` 🔴

**Order / criação / finalize:** `create_order` 🔴 · `finalize_errand_purchase` 🔴 · `finalize_storeshopping_purchase` 🔴 · `finalize_storeshopping_purchase_v2` 🔴 · `post_order_to_ledger` 🔴 · `apply_order_financial_split` 🔴 · `set_delivered_at`

**Settlement (fecho semanal):** `close_partner_week_settlements` 🔴 · `close_previous_week_settlements` 🔴 · `compute_driver_settlement` 🔴 · `compute_partner_weekly_settlement` 🔴 · `compute_provider_weekly_payout` 🔴 · `compute_all_provider_weekly_payouts` 🔴 · `run_weekly_closeout` 🔴 · `driver_settlement_week_bounds` · `apply_driver_cash_settlement` 🔴

**Payout:** `create_payout` 🔴 · `auto_payout_pending` 🔴 · `admin_mark_partner_payouts_paid` 🔴 · `admin_mark_appointment_payouts_paid` 🔴 · `admin_mark_partner_credits_paid` 🔴 · `admin_partner_payout_summary` · `admin_list_partner_payouts` · `admin_list_appointment_payouts`

**Refund:** `compute_refund_split` 🔴 · `wallet_credit_refund_full` 🔴 · `wallet_credit_refund_split` 🔴 · `_enforce_refund_cap` 🔴

**Wallet:** `wallet_apply_post_delivery_adjustment` 🔴 · `wallet_credit_generic` 🔴 · `wallet_debit_cancel_fee` 🔴 · `wallet_debit_for_order` 🔴 · `wallet_get_balance` · `wallet_settle_debt` 🔴 · `admin_grant_wallet_free` 🔴 · `admin_revoke_wallet_free` 🔴 · `admin_forgive_wallet_debt` 🔴 · `admin_list_wallets` · `admin_user_wallet_transactions` · `recompute_user_balance` 🔴 · `ledger_after_insert_recompute` 🔴 · `fn_apply_client_debt_settlement_on_cash_delivery` 🔴 · `fn_apply_client_debt_settlement_on_payment_paid` 🔴 · `fn_credit_driver_on_delivery` 🔴

**Tokens:** `add_tokens` 🔴 · `consume_tokens` 🔴 · `get_user_tokens` · `admin_get_user_tokens` · `admin_grant_tokens` 🔴 · `admin_revoke_token_grant` 🔴 · `driver_convert_tokens` 🔴 · `client_redeem_promo_tokens` 🔴 · `fn_award_tokens_on_delivery` 🔴 · `agent_get_user_tokens_summary`

**Cash / limites:** `enforce_cash_payment_limit` 🔴 · `auto_confirm_cod_payment` 🔴 · `enforce_financial_immutability` 🔴 · `enforce_payment_before_preparing` 🔴 · `enforce_storeshopping_finalize_before_pickup` 🔴 · `ledger_append_only_guard` 🔴 · `pay-debt` (via edge)

**Referral (recompensa €/token):** `fn_referral_reward_on_first_delivery` 🔴 · `client_register_with_referral` · `admin_grant_referral_code` · `client_get_or_create_referral_code`

## Dispatch / Estafeta

`invoke_dispatch_engine` · `on_order_calling_driver` · `on_order_insert_calling_driver` · `fn_dispatch_on_calling_driver` · `dispatch_cancel_expired_order` · `bora_dispatch_maintenance` · `driver_accept_offer` · `driver_reject_offer` · `driver_cancel_order` · `driver_heartbeat` · `driver_heartbeat_by_id` · `driver_push_position` · `driver_update_location` · `driver_register_or_update` · `driver_effective_status` · `mark_stale_drivers_offline` · `fn_notify_driver_on_offer` · `invoke_notify_driver` · `recalc_driver_earnings_on_stack` 🔴 · `fn_recalc_earnings_on_assign` 🔴 · `request_driver_help` · `client_get_assigned_driver` · `get_driver_current_week_summary` · `list_driver_orders_in_week`

## TVDE (isolada) 🔴

`tvde_request_ride` · `tvde_accept_ride` · `tvde_reject_ride` · `tvde_offer_to_next` · `tvde_dispatch_sweep` · `tvde_driver_arrived` · `tvde_start_ride` · `tvde_finish_ride` 🔴 · `tvde_cancel_ride` · `tvde_rate` · `tvde_request_access` · `tvde_consume_subscription_ride` 🔴 · `fn_tvde_dispatch_on_request` · `fn_notify_tvde_driver_on_offer` · `admin_tvde_*` (access_requests_list, drivers_list, rides_list, subscriptions_list) · `admin_set_tvde_access`

## Serviços / Agendamentos

`client_book_appointment` · `client_cancel_appointment` · `client_confirm_appointment_payment` 🔴 · `partner_complete_appointment` · `partner_cancel_appointment` · `get_available_slots` · `client_search_availability` · `admin_appointment_provider_approve` · `admin_appointment_provider_reject` · `admin_appointments_metrics` · `admin_cancel_appointment_on_behalf_of` · `_appt_*` (notify/assert)

## Reservas (Reservas Pro)

`client_cancel_reservation` · `client_confirm_reservation_payment` 🔴 · `confirm_reservation_payment_webhook` 🔴 · `client_join_waitlist` · `client_join_notify` · `client_arrived` · `client_get_active_menu_credit` · `consume_menu_credit_for_order` 🔴 · `partner_decide_reservation` · `partner_mark_arrival` 🔴 · `partner_mark_seated` · `partner_mark_finished` · `partner_mark_no_show` · `partner_add_table` · `partner_add_walk_in` · `partner_seat_walk_in` · `partner_block_slot` · `partner_combine_tables` · `partner_create_floor_plan` · `admin_force_create_reservation` · `admin_seat_walk_in` · `admin_reservations_*` · `auto_close_no_show_reservations` · `cancel_orphan_reservation` · `cancel_orphan_reservation` · `_reservas_pro_*` (crons/notify/asserts)

## Parceiro (pedidos / restaurante)

`partner_accept_order` · `partner_reject_order` · `partner_dispatch_decision` · `partner_takeaway_accept` · `partner_takeaway_mark_ready` · `partner_takeaway_mark_picked_up` · `partner_my_weekly_closeout` 🔴 · `approve_partner` · `reject_partner` · `is_partner_open` · `get_partner_fcm_tokens_for_restaurant`

## Cliente (geral)

`client_apply_promo_code` 🔴 · `client_record_promo_use` · `client_log_search` · `client_toggle_favorite` · `client_list_notifications` · `client_mark_notification_read` · `client_mark_all_notifications_read` · `client_unread_notifications_count` · `client_respond_budget_increase` · `client_set_errand_request_photo` · `errand_request_budget_increase` · `errand_min_distance_km` · `request_order_cancel` · `request_driver_help` · `submit_rating` · `rating_average` · `file_complaint` · `file_support_ticket` · `chat_mark_read` · `user_is_order_participant`

## Suporte / Robot / IA

`support-chatbot` (edge) · `match_knowledge` · `increment_chatbot_quota` · `agent_ask_robot_b` · `agent_get_order_status` · `agent_get_refund_status` · `agent_get_user_orders_summary` · `agent_get_user_wallet_summary` · `agent_propose_action` · `robot_apply_suggestion` · `robot_auto_execute` · `robot_b_respond` · `robot_create_suggestion` · `robot_finish_run` · `robot_start_run` · `robot_observe` · `robot_reject_suggestion` · `robot_mark_suggestion_done` · `robot_notify_digest` · `_robot_op_guard` · `_robot_setting_enabled`

## Admin (~90 rotinas `admin_*`)

Dashboards/KPIs: `admin_dashboard_metrics` · `admin_realtime_metrics` · `admin_kpi_avg_ticket` · `admin_kpi_conversion` · `admin_kpi_hot_zones` · `admin_search_kpi` · `admin_weekly_bora_totals` 🔴 · `admin_partner_sales_summary` · `admin_referral_stats` · `admin_robot_metrics` · `admin_get_support_stats` · `admin_skill_suggestions_metrics/stats`.
Gestão: `admin_approve_driver` · `admin_reject_driver` · `admin_reactivate_driver` · `admin_soft_delete_driver` · `admin_update_driver` · `admin_ban_driver` 🔴 · `admin_ban_client`/`unban`/`block`/`unblock` · `admin_cancel_order` 🔴 · `admin_update_product_price` 🔴 · `admin_set_product_availability` · `admin_create_promo_code` 🔴 · `admin_deactivate_promo_code` · `admin_list_promo_codes` · `admin_grant_subscription` · `admin_broadcast_notification` · `admin_send_push_notification` · `admin_create_broadcast` · `admin_set_partner_override` · `admin_update_setting` 🔴 · `admin_list_settings` · `admin_run_select` · `admin_run_write` · `admin_call_rpc` · `admin_continente_*` (price apply/list/review/summary).
Guards/aux: `is_admin` · `_is_admin` · `_admin_op_guard` · `log_admin_action` · `protect_admin_app_role`.

## Push / Notificações

`register_push_token` · `admin_register_push_token` · `mark_token_failed` · `notify_admin_event` · `_push_in_app_notification` · `_notify_*` (chat/order-cancel/cashback/partner-status) · `_trg_admin_notif_*` (wallet_debt/complaint/refund/reservation/skill/cancel-mid-delivery)

## Catálogo / Mercados / Utilidades

`search_products` · `search_businesses` · `bora_scraper_insert_batch` · `bora_normalize` · `_normalize_for_match` · `auto_map_category` · `fn_products_set_category_root` · `fn_products_set_search_normalized` · `_products_set_taxonomy_section` · `admin_upsert_business` · `admin_delete_business` · `admin_set_business_visibility` · `admin_list_businesses` · `place_autocomplete` · `_haversine_km` · `get_setting` · `_parse_hhmm_to_minutes` · `log_client_crash`

> Nota: overloads presentes em `admin_approve_driver` e `log_admin_action` (2 assinaturas cada).
