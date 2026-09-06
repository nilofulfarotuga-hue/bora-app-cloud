-- M3.5 v2 — correção do v1: o EXECUTE herdado do GRANT default a PUBLIC
-- mantinha anon/authenticated com acesso (REVOKE direto de anon não chegava).
-- Modelo final por função SECURITY DEFINER de public:
--   REVOKE PUBLIC/anon/authenticated  →  GRANT service_role (Edge Fns/scripts)
--   + GRANT authenticated APENAS na whitelist (108 RPCs do Flutter + agent_%
--     do support-chatbot + ratings públicas + log_admin_action das skills)
--   + GRANT anon APENAS nos 5 RPCs dos isolates background (FGS/notification:
--     heartbeat_by_id, driver/partner accept/reject — chamados com anon key
--     por desenho, sem sessão no isolate)
--   + funções usadas em policies RLS (is_admin, _restaurant_id_of_current_user,
--     user_is_order_participant) mantêm anon+authenticated — avaliadas pelo
--     role do caller em cada query; revogá-las partia a app inteira.
-- RESULTADO VERIFICADO (2026-06-10): definer com anon 193→8 (5 isolates + 3 RLS);
-- authenticated 286→125; dispatch_cancel_expired_order/_push_in_app_notification
-- só service_role; create_order/driver_heartbeat_by_id intactos para a app.

DO $do$
DECLARE
  r record;
  v_auth_whitelist text[] := ARRAY[
    -- 108 RPCs chamadas pela app Flutter (grep .rpc lib/, 2026-06-10)
    'admin_approve_action','admin_approve_cancellation','admin_approve_skill_suggestion',
    'admin_ban_client','admin_block_client','admin_broadcast_notification',
    'admin_bulk_reject_skill_suggestions','admin_category_mapping_stats','admin_clear_partner_override',
    'admin_create_broadcast','admin_create_promo_code','admin_dashboard_metrics',
    'admin_deactivate_promo_code','admin_edge_fn_health','admin_finalize_action',
    'admin_forgive_wallet_debt','admin_get_client_history','admin_get_knowledge_stats',
    'admin_get_user_tokens','admin_grant_referral_code','admin_grant_tokens',
    'admin_grant_wallet_free','admin_kpi_avg_ticket','admin_kpi_conversion','admin_kpi_hot_zones',
    'admin_list_audit_action_types','admin_list_audit_log','admin_list_cashbacks',
    'admin_list_category_mappings','admin_list_clients','admin_list_complaints',
    'admin_list_crosstalk','admin_list_orphans','admin_list_pending_actions',
    'admin_list_products_by_partner','admin_list_promo_codes','admin_list_settings',
    'admin_list_skill_suggestions','admin_list_wallets','admin_live_drivers','admin_live_orders',
    'admin_partners_closed_now','admin_partners_with_counts','admin_realtime_metrics',
    'admin_referral_stats','admin_reject_action','admin_reject_cancellation',
    'admin_reject_skill_suggestion','admin_reservations_metrics','admin_reservations_today',
    'admin_resolve_ticket','admin_respond_to_crosstalk','admin_revoke_token_grant',
    'admin_revoke_wallet_free','admin_rollback_suggestion','admin_save_broadcast_in_app',
    'admin_search_kpi','admin_send_push_notification','admin_set_partner_override',
    'admin_set_partner_special_date','admin_set_product_availability',
    'admin_skill_suggestions_metrics','admin_skill_suggestions_stats','admin_unban_client',
    'admin_unblock_client','admin_update_category_mapping','admin_update_complaint_status',
    'admin_update_partner_data','admin_update_partner_hours','admin_update_product_price',
    'admin_update_setting','admin_update_skill_suggestion_note','admin_user_wallet_transactions',
    'cancel_orphan_reservation','client_arrived','client_book_appointment',
    'client_cancel_appointment','client_confirm_appointment_payment','client_confirm_reservation_payment',
    'client_get_or_create_referral_code','client_join_notify','client_join_waitlist',
    'client_list_notifications','client_log_search','client_mark_all_notifications_read',
    'client_mark_notification_read','client_redeem_promo_tokens','client_search_availability',
    'client_toggle_favorite','client_unread_notifications_count','create_order',
    'driver_accept_offer','driver_effective_status','driver_heartbeat','driver_register_or_update',
    'driver_reject_offer','driver_update_location','get_available_slots',
    'get_driver_current_week_summary','get_setting','get_user_tokens','is_partner_open',
    'partner_decide_reservation','partner_mark_arrival','quote_order_pricing','submit_rating',
    'update_driver_mbway_phone','wallet_get_balance',
    -- públicas documentadas + helper audit usado pelas skills com JWT admin
    'get_restaurant_ratings_summary','get_driver_ratings_summary','log_admin_action',
    -- isolates background também usáveis com sessão
    'driver_heartbeat_by_id','partner_accept_order','partner_reject_order'
  ];
  v_anon_whitelist text[] := ARRAY[
    'driver_heartbeat_by_id','driver_accept_offer','driver_reject_offer',
    'partner_accept_order','partner_reject_order'
  ];
  v_rls_fns text[] := ARRAY['_restaurant_id_of_current_user','is_admin','user_is_order_participant'];
  v_revoked int := 0; v_auth_granted int := 0; v_anon_granted int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig, p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef AND p.prokind = 'f'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
    v_revoked := v_revoked + 1;

    IF r.proname = ANY(v_auth_whitelist) OR r.proname LIKE 'agent\_%' OR r.proname = ANY(v_rls_fns) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
      v_auth_granted := v_auth_granted + 1;
    END IF;

    IF r.proname = ANY(v_anon_whitelist) OR r.proname = ANY(v_rls_fns) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
      v_anon_granted := v_anon_granted + 1;
    END IF;
  END LOOP;

  -- Funções de RLS (definer ou não): garantir EXECUTE para os roles de query
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(v_rls_fns)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', r.sig);
  END LOOP;

  RAISE NOTICE '[hardening v2] % definer processadas | authenticated re-granted: % | anon re-granted: %',
    v_revoked, v_auth_granted, v_anon_granted;
END $do$;
