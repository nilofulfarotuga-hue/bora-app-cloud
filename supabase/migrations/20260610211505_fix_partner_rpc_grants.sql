-- ============================================================================
-- fix_partner_rpc_grants — 2026-06-10
-- ----------------------------------------------------------------------------
-- ROOT CAUSE: as migrations de hardening 20260609232339/20260609232719 fizeram
-- REVOKE ... FROM PUBLIC sem repor GRANT EXECUTE a `authenticated` em todas as
-- funções que a app Flutter chama via supabase.rpc(). Resultado: 42501
-- (permission denied) no painel parceiro (BUG do device-test 2026-06-10) e em
-- vários outros caminhos. Os grants do parceiro foram aplicados a quente via
-- MCP em 2026-06-10; esta migration PERSISTE esses 15 e corrige TODAS as
-- restantes órfãs encontradas no sweep completo (grep .rpc() em lib/ —
-- incluindo chamadas multi-linha e o wrapper dinâmico AdminDriverService).
--
-- VALIDAÇÃO DE SEGURANÇA (2026-06-10): todas as funções abaixo são
-- SECURITY DEFINER e validam o caller internamente (auth.uid() ou
-- _admin_op_guard / _reservas_pro_assert_admin / is_admin / _is_admin),
-- EXCETO consume_tokens — que recebia p_user_id sem validar o caller.
-- Por isso, antes do GRANT, esta migration adiciona um guard a
-- consume_tokens: utilizador autenticado só consome os PRÓPRIOS tokens
-- (admin e contextos sem utilizador — service_role/jobs — continuam a passar).
--
-- Aplicada em produção via MCP apply_migration em 2026-06-10 21:15:05 UTC
-- (version 20260610211505). Este ficheiro persiste-a no repo.
-- ============================================================================

-- 1) consume_tokens: guard de caller (era SECURITY DEFINER sem validação).
CREATE OR REPLACE FUNCTION public.consume_tokens(p_user_id uuid, p_amount integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_balance  INTEGER;
  v_remaining        INTEGER := p_amount;
  v_row              RECORD;
  v_consume          INTEGER;
BEGIN
  -- ── Guard (2026-06-10): caller autenticado só consome os PRÓPRIOS tokens ──
  -- auth.uid() IS NULL = contexto sem utilizador (service_role / jobs internos).
  IF auth.uid() IS NOT NULL
     AND auth.uid() <> p_user_id
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'consume_tokens: caller % cannot consume tokens of user %',
      auth.uid(), p_user_id
      USING ERRCODE = '42501';
  END IF;

  -- ── Guard: reject invalid amounts ────────────────────────────────────────
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'consume_tokens: p_amount must be > 0, got %', p_amount;
  END IF;

  -- ── Guard: verify sufficient balance before mutating anything ────────────
  v_current_balance := get_user_tokens(p_user_id);

  IF v_current_balance < p_amount THEN
    RAISE NOTICE
      'consume_tokens: insufficient balance for user %. Have %, need %',
      p_user_id, v_current_balance, p_amount;
    RETURN FALSE;
  END IF;

  -- ── FIFO loop: consume oldest-expiring tokens first ───────────────────────
  -- SELECT FOR UPDATE ensures no concurrent call can touch the same rows.
  FOR v_row IN
    SELECT id, amount, expires_at, role
    FROM   bora_tokens
    WHERE  user_id    = p_user_id
      AND  is_used    = FALSE
      AND  expires_at > now()
    ORDER BY expires_at ASC, created_at ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining = 0;

    IF v_row.amount <= v_remaining THEN
      -- ── Case A: consume this token entirely ──────────────────────────────
      UPDATE bora_tokens
      SET    is_used = TRUE,
             used_at = now()
      WHERE  id = v_row.id;

      v_remaining := v_remaining - v_row.amount;

    ELSE
      -- ── Case B: partial — consume what's needed, keep the rest ───────────
      -- Mark the original row as fully used.
      UPDATE bora_tokens
      SET    is_used = TRUE,
             used_at = now()
      WHERE  id = v_row.id;

      -- Insert a remainder row with the same expiry so it doesn't gain
      -- artificial longevity. No source_order_id (it's a split, not a reward).
      INSERT INTO bora_tokens (user_id, role, amount, expires_at)
      VALUES (p_user_id, v_row.role, v_row.amount - v_remaining, v_row.expires_at);

      v_remaining := 0;
    END IF;

  END LOOP;

  -- ── Sanity check: should never happen given the pre-check above ──────────
  IF v_remaining > 0 THEN
    RAISE EXCEPTION
      'consume_tokens: consumed less than requested (remaining=%). Rolling back.',
      v_remaining;
  END IF;

  RETURN TRUE;
END;
$function$;

-- 2) GRANT EXECUTE a authenticated em TODAS as funções chamadas pela app via
--    .rpc() que ficaram órfãs no hardening. Loop por nome cobre overloads
--    (ex.: admin_approve_driver tem 2 assinaturas).
DO $$
DECLARE
  fn text;
  r record;
  fns text[] := ARRAY[
    -- (a) Persistência do hot-fix MCP 2026-06-10 — painel parceiro (42501)
    'partner_add_table',
    'partner_add_walk_in',
    'partner_block_slot',
    'partner_combine_tables',
    'partner_complete_appointment',
    'partner_create_floor_plan',
    'partner_dispatch_decision',
    'partner_mark_finished',
    'partner_mark_no_show',
    'partner_mark_seated',
    'partner_seat_walk_in',
    'partner_takeaway_accept',
    'partner_takeaway_mark_picked_up',
    'partner_takeaway_mark_ready',
    'compute_provider_weekly_payout',
    -- (b) Órfãs cliente/estafeta encontradas no sweep (todas com guard interno)
    'client_cancel_reservation',
    'client_register_with_referral',
    'consume_tokens',
    'driver_cancel_order',
    'request_driver_help',
    'finalize_storeshopping_purchase',
    'finalize_storeshopping_purchase_v2',
    'update_bag_count_bypass',
    'register_push_token',
    -- (c) Órfãs do painel admin (todas com _admin_op_guard/assert_admin/is_admin)
    'admin_register_push_token',
    'admin_approve_driver',
    'admin_reject_driver',
    'admin_ban_driver',
    'admin_reactivate_driver',
    'admin_update_driver',
    'admin_soft_delete_driver',
    'admin_appointment_provider_approve',
    'admin_appointment_provider_reject',
    'admin_appointments_metrics',
    'admin_cancel_appointment_on_behalf_of',
    'admin_cancel_reservation_on_behalf_of',
    'admin_force_create_reservation',
    'admin_seat_walk_in',
    'admin_get_reservations_stats',
    'admin_get_support_stats',
    'admin_list_appointment_payouts',
    'admin_mark_appointment_payouts_paid',
    'admin_list_broadcasts',
    'admin_list_cancellation_requests',
    'admin_list_partner_payouts',
    'admin_mark_partner_payouts_paid',
    'admin_partner_payout_summary',
    'admin_mark_partner_credits_paid',
    'admin_list_partners_detailed',
    'list_partners_by_status',
    'approve_partner',
    'reject_partner',
    'admin_list_ratings',
    'admin_low_rated_subjects',
    'admin_flag_rating',
    'admin_list_referral_invites',
    'admin_list_settlements_for_week',
    'admin_set_settlement_status',
    'admin_mark_receipt_paid',
    'admin_reject_receipt',
    'admin_partner_sales_summary',
    'admin_reset_product_photo'
  ];
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    FOR r IN
      SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = fn
    LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    END LOOP;
    IF NOT FOUND THEN
      RAISE WARNING 'fix_partner_rpc_grants: função % não encontrada — ignorada', fn;
    END IF;
  END LOOP;
END $$;
