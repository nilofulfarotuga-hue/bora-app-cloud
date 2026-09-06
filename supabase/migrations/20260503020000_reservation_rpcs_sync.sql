-- =============================================================================
-- Reservation RPCs · Git ← Prod sync (BUG D4 — Sessão 2)
-- 2026-05-03
-- =============================================================================
-- Captura literal de pg_get_functiondef() em prod (project ojykpzwqrtusfeakzrna)
-- para 7 RPCs do domínio Reservas que existiam em prod mas estavam ausentes
-- em supabase/migrations/. Foram aplicadas anteriormente via MCP sem ficheiro
-- correspondente; este sync garante replay-safety e rebuild-from-scratch.
--
-- ZERO mudanças funcionais. Cada CREATE OR REPLACE é byte-equivalente ao
-- pg_get_functiondef() de prod no momento da extracção.
--
-- Hashes md5 esperados pós-replay (validados antes/depois):
--   admin_reservations_metrics            f0254edeec1833f06e5d4289df7e20ed
--   admin_reservations_today              5d0c42046ddeaaa0443c2af03b478f68
--   auto_close_no_show_reservations       463bc92ae71d51856f50eb5abcb70a20
--   client_cancel_reservation             3609a4a291d38b29c59b4d971743e3f0
--   client_confirm_reservation_payment    e52f212e03458760171ee2d742c135c0
--   partner_decide_reservation            5bf1c297f4136cca19f5c08d14054c06
--   partner_mark_arrival                  185b8626abd8a2cee757d14adac8bda4
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1/7 · admin_reservations_metrics(p_days int DEFAULT 30) → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reservations_metrics(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total int; v_pending int; v_approved int; v_arrived int;
  v_no_show int; v_cancelled_no_refund int; v_cancelled_refunded int;
  v_rejected int; v_revenue_cents bigint; v_credits_given_cents bigint;
BEGIN
  PERFORM public._admin_op_guard();

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status='pending'),
    COUNT(*) FILTER (WHERE status='approved'),
    COUNT(*) FILTER (WHERE status='arrived'),
    COUNT(*) FILTER (WHERE status='no_show'),
    COUNT(*) FILTER (WHERE status='cancelled_no_refund'),
    COUNT(*) FILTER (WHERE status='cancelled_refunded'),
    COUNT(*) FILTER (WHERE status='rejected_refunded'),
    COALESCE(SUM(prepayment_cents) FILTER (WHERE status IN ('no_show','cancelled_no_refund')), 0),
    COALESCE(SUM(prepayment_cents) FILTER (WHERE status='arrived'), 0)
  INTO v_total, v_pending, v_approved, v_arrived, v_no_show,
       v_cancelled_no_refund, v_cancelled_refunded, v_rejected,
       v_revenue_cents, v_credits_given_cents
  FROM public.reservations
  WHERE created_at > NOW() - (p_days || ' days')::interval;

  RETURN jsonb_build_object(
    'period_days', p_days,
    'total', v_total,
    'pending', v_pending,
    'approved', v_approved,
    'arrived', v_arrived,
    'no_show', v_no_show,
    'cancelled_no_refund', v_cancelled_no_refund,
    'cancelled_refunded', v_cancelled_refunded,
    'rejected_refunded', v_rejected,
    'no_show_rate_pct', CASE WHEN v_total = 0 THEN 0
                             ELSE ROUND(100.0 * v_no_show / v_total, 1) END,
    'cancellation_rate_pct', CASE WHEN v_total = 0 THEN 0
                                  ELSE ROUND(100.0 * (v_cancelled_no_refund + v_cancelled_refunded) / v_total, 1) END,
    'bora_revenue_cents', v_revenue_cents,
    'credits_given_cents', v_credits_given_cents
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2/7 · admin_reservations_today() → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reservations_today()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_pending int; v_approved int; v_next jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT
    COUNT(*) FILTER (WHERE status='pending'),
    COUNT(*) FILTER (WHERE status='approved')
  INTO v_pending, v_approved
  FROM public.reservations
  WHERE reserved_for::date = CURRENT_DATE;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'reserved_for', reserved_for, 'people', people,
    'status', status, 'restaurant_id', restaurant_id,
    'client_name', client_name
  ) ORDER BY reserved_for ASC), '[]'::jsonb)
  INTO v_next
  FROM (
    SELECT * FROM public.reservations
    WHERE reserved_for >= NOW()
      AND status IN ('pending','approved')
    ORDER BY reserved_for ASC LIMIT 5
  ) t;

  RETURN jsonb_build_object(
    'pending', v_pending,
    'approved', v_approved,
    'next', v_next
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3/7 · auto_close_no_show_reservations() → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_close_no_show_reservations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
  v_grace int;
  v_rsv_record record;
BEGIN
  SELECT (value::text)::int INTO v_grace FROM platform_settings
  WHERE key = 'reservation_no_show_grace_minutes';
  v_grace := COALESCE(v_grace, 60);

  -- Notify each client first (via in_app)
  FOR v_rsv_record IN
    SELECT id, client_user_id, prepayment_cents
    FROM reservations
    WHERE status = 'approved'
      AND arrived_at IS NULL
      AND reserved_for < NOW() - (v_grace || ' minutes')::interval
  LOOP
    PERFORM _push_in_app_notification(
      v_rsv_record.client_user_id, 'reservation',
      'Reserva marcada como falta',
      'Não chegaste à reserva. Pré-pagamento de €' ||
        ROUND(v_rsv_record.prepayment_cents / 100.0, 2)::text || ' não é devolvido.',
      v_rsv_record.id::text
    );
  END LOOP;

  UPDATE reservations
  SET status = 'no_show'
  WHERE status = 'approved'
    AND arrived_at IS NULL
    AND reserved_for < NOW() - (v_grace || ' minutes')::interval;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('marked_no_show', v_count, 'ran_at', NOW());
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4/7 · client_cancel_reservation(uuid, text DEFAULT NULL) → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_cancel_reservation(p_reservation_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rsv record;
  v_uid uuid := auth.uid();
  v_window_h int;
  v_diff_h numeric;
  v_will_refund boolean;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'cannot_cancel_status: %', v_rsv.status;
  END IF;

  SELECT (value::text)::int INTO v_window_h FROM platform_settings
  WHERE key = 'reservation_cancel_window_hours';
  v_window_h := COALESCE(v_window_h, 2);

  v_diff_h := EXTRACT(EPOCH FROM (v_rsv.reserved_for - NOW())) / 3600.0;
  v_will_refund := v_diff_h >= v_window_h;
  v_new_status := CASE WHEN v_will_refund THEN 'cancelled_refunded' ELSE 'cancelled_no_refund' END;

  UPDATE reservations
  SET status = v_new_status, cancelled_at = NOW(), cancel_reason = p_reason
  WHERE id = p_reservation_id;

  PERFORM _push_in_app_notification(
    v_uid, 'cancellation',
    CASE WHEN v_will_refund THEN 'Reserva cancelada — reembolso em curso'
         ELSE 'Reserva cancelada — pré-pagamento não devolvido' END,
    CASE WHEN v_will_refund THEN 'Reembolso de €' ||
           ROUND(v_rsv.prepayment_cents / 100.0, 2)::text || ' em 5–10 dias úteis.'
         ELSE 'Cancelaste dentro de ' || v_window_h::text ||
              'h — pré-pagamento de €' || ROUND(v_rsv.prepayment_cents / 100.0, 2)::text ||
              ' não é devolvido.' END,
    p_reservation_id::text
  );

  -- Audit
  PERFORM log_admin_action(
    'client_cancel_reservation', 'reservation', p_reservation_id::text,
    jsonb_build_object('hours_until', v_diff_h, 'window_h', v_window_h,
                       'refund', v_will_refund, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true, 'status', v_new_status,
    'will_refund', v_will_refund,
    'hours_until_reservation', v_diff_h,
    'prepayment_pi', v_rsv.prepayment_pi  -- caller (Edge Fn refund) refunds Stripe
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5/7 · client_confirm_reservation_payment(uuid) → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_confirm_reservation_payment(p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_rsv record; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('pending_payment', 'pending') THEN
    RAISE EXCEPTION 'invalid_status: %', v_rsv.status;
  END IF;

  UPDATE reservations SET status = 'pending', updated_at = NOW()
  WHERE id = p_reservation_id AND status = 'pending_payment';

  -- Notify partner via in_app (also FCM via Edge Fn — fire-and-forget Flutter)
  -- Find partner user_id from restaurants table
  PERFORM _push_in_app_notification(
    (SELECT u.id FROM auth.users u
     JOIN restaurants r ON r.email = u.email
     WHERE r.id = v_rsv.restaurant_id LIMIT 1),
    'reservation',
    'Nova reserva pendente',
    'Reserva para ' || v_rsv.people || ' pessoas em ' ||
       to_char(v_rsv.reserved_for, 'DD/MM HH24:MI'),
    p_reservation_id::text
  );
  RETURN jsonb_build_object('success', true, 'status', 'pending');
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6/7 · partner_decide_reservation(uuid, boolean, text DEFAULT NULL) → jsonb
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_decide_reservation(p_reservation_id uuid, p_accept boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rsv record;
  v_uid uuid := auth.uid();
  v_partner_owns boolean;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.status != 'pending' THEN
    RAISE EXCEPTION 'reservation_not_pending: %', v_rsv.status;
  END IF;

  -- Partner ownership check via restaurants.email = auth user email
  SELECT EXISTS (
    SELECT 1 FROM restaurants r
    JOIN auth.users u ON u.email = r.email
    WHERE r.id = v_rsv.restaurant_id AND u.id = v_uid
  ) INTO v_partner_owns;
  IF NOT v_partner_owns THEN RAISE EXCEPTION 'not_your_restaurant'; END IF;

  v_new_status := CASE WHEN p_accept THEN 'approved' ELSE 'rejected_refunded' END;

  UPDATE reservations
  SET status = v_new_status, decided_at = NOW(),
      cancel_reason = CASE WHEN p_accept THEN cancel_reason ELSE p_reason END
  WHERE id = p_reservation_id;

  PERFORM _push_in_app_notification(
    v_rsv.client_user_id, 'reservation',
    CASE WHEN p_accept THEN 'Reserva aprovada' ELSE 'Reserva rejeitada — reembolso' END,
    CASE WHEN p_accept THEN 'Vemo-nos a ' || to_char(v_rsv.reserved_for, 'DD/MM HH24:MI') || '.'
         ELSE 'O parceiro não pôde aceitar. Reembolso em curso.' END,
    p_reservation_id::text
  );

  RETURN jsonb_build_object(
    'success', true, 'status', v_new_status,
    'will_refund', NOT p_accept,
    'prepayment_pi', v_rsv.prepayment_pi
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7/7 · partner_mark_arrival(uuid) → jsonb
--   Domínio reservas: parceiro confirma chegada do cliente, debita €2 crédito
--   ao cliente naquele restaurante e regista obrigação de payout ao parceiro.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_mark_arrival(p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rsv record;
  v_uid uuid := auth.uid();
  v_partner_owns boolean;
  v_credit_id uuid;
  v_payout_id uuid;
  v_payout_cents int;
  v_expiry_days int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT * INTO v_rsv FROM public.reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.status != 'approved' THEN
    RAISE EXCEPTION 'reservation_not_approved: %', v_rsv.status;
  END IF;
  IF v_rsv.arrived_at IS NOT NULL THEN
    RAISE EXCEPTION 'already_arrived';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.restaurants r
    JOIN auth.users u ON u.email = r.email
    WHERE r.id = v_rsv.restaurant_id AND u.id = v_uid
  ) INTO v_partner_owns;
  IF NOT v_partner_owns THEN RAISE EXCEPTION 'not_your_restaurant'; END IF;

  -- v2: lê €2 (não €3) das settings
  SELECT (value::text)::int INTO v_payout_cents
  FROM public.platform_settings WHERE key = 'reservation_partner_payout_cents';
  v_payout_cents := COALESCE(v_payout_cents, 200);

  SELECT (value::text)::int INTO v_expiry_days
  FROM public.platform_settings WHERE key = 'reservation_credit_expiry_days';
  v_expiry_days := COALESCE(v_expiry_days, 30);

  -- Atomic: marca arrived + status='arrived'
  UPDATE public.reservations
  SET arrived_at = NOW(), status = 'arrived'
  WHERE id = p_reservation_id;

  -- Crédito de €2 para cliente naquele restaurante
  INSERT INTO public.restaurant_menu_credits (
    user_id, restaurant_id, amount_cents, source_reservation_id, expires_at
  ) VALUES (
    v_rsv.client_user_id, v_rsv.restaurant_id, v_payout_cents,
    p_reservation_id, NOW() + (v_expiry_days || ' days')::interval
  ) RETURNING id INTO v_credit_id;

  -- Obrigação de payout: Bora deve €2 ao parceiro no settlement semanal
  INSERT INTO public.partner_reservation_payouts (
    partner_id, reservation_id, amount_cents
  ) VALUES (
    v_rsv.restaurant_id, p_reservation_id, v_payout_cents
  )
  ON CONFLICT (reservation_id) DO NOTHING
  RETURNING id INTO v_payout_id;

  -- Notificação cliente
  PERFORM public._push_in_app_notification(
    v_rsv.client_user_id, 'reservation',
    'Crédito de €' || ROUND(v_payout_cents / 100.0, 2)::text || ' creditado',
    'Aplicado automaticamente no teu próximo pedido neste restaurante.',
    p_reservation_id::text
  );

  -- Audit
  PERFORM public.log_admin_action(
    'reservation_arrival_marked', 'reservation', p_reservation_id::text,
    jsonb_build_object(
      'credit_cents', v_payout_cents,
      'payout_cents', v_payout_cents,
      'partner_id', v_rsv.restaurant_id,
      'client_user_id', v_rsv.client_user_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'credit_id', v_credit_id,
    'credit_cents', v_payout_cents,
    'payout_id', v_payout_id,
    'payout_cents', v_payout_cents
  );
END;
$function$;
