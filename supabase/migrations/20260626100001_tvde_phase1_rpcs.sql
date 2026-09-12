-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 1 · RPCs isoladas
-- ============================================================================
-- Todas SECURITY DEFINER, search_path=public, REVOKE public/anon + GRANT authenticated.
-- Admin via _admin_op_guard() + log_admin_action. NÃO toca zonas protegidas.
-- ============================================================================

BEGIN;

-- ── ratings.subject_type: permitir avaliação de passageiro TVDE (aditivo) ────
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_subject_type_check;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_subject_type_check
  CHECK (subject_type = ANY (ARRAY['partner','driver','app','tvde_passenger']));

-- ════════════════════════════════════════════════════════════════════════════
-- ACESSO À CATEGORIA ESCONDIDA
-- ════════════════════════════════════════════════════════════════════════════

-- Cliente pede acesso → notifica admin
CREATE OR REPLACE FUNCTION public.tvde_request_access()
RETURNS public.tvde_access_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_access BOOLEAN;
  v_name   TEXT;
  v_row    public.tvde_access_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT tvde_access, name INTO v_access, v_name FROM public.users WHERE id = v_uid;
  IF v_access IS TRUE THEN RAISE EXCEPTION 'already_has_access'; END IF;

  SELECT * INTO v_row FROM public.tvde_access_requests
    WHERE client_id = v_uid AND status = 'pendente' LIMIT 1;
  IF FOUND THEN RETURN v_row; END IF;

  INSERT INTO public.tvde_access_requests (client_id)
    VALUES (v_uid) RETURNING * INTO v_row;

  PERFORM public.notify_admin_event(
    'tvde_access_request', 'medium',
    'Novo pedido de acesso Bora Motorista: ' || COALESCE(v_name, 'cliente'),
    'tvde_access_request', v_row.id::text,
    jsonb_build_object('client_id', v_uid, 'client_name', v_name),
    '/admin/tvde/access-requests'
  );
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_request_access() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_request_access() TO authenticated;

-- Admin aprova / recusa / revoga
CREATE OR REPLACE FUNCTION public.admin_set_tvde_access(p_client_id UUID, p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin RECORD;
  v_new_access BOOLEAN;
  v_req_status TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_action NOT IN ('aprovar','recusar','revogar') THEN
    RAISE EXCEPTION 'invalid_action: %', p_action;
  END IF;

  IF p_action = 'aprovar' THEN v_new_access := true;  v_req_status := 'aprovado';
  ELSIF p_action = 'recusar' THEN v_new_access := false; v_req_status := 'recusado';
  ELSE v_new_access := false; v_req_status := NULL; -- revogar
  END IF;

  UPDATE public.users SET tvde_access = v_new_access WHERE id = p_client_id;

  IF v_req_status IS NOT NULL THEN
    UPDATE public.tvde_access_requests
       SET status = v_req_status, decided_at = now(), decided_by = v_admin.admin_id
     WHERE client_id = p_client_id AND status = 'pendente';
  END IF;

  PERFORM public.log_admin_action(
    'tvde_access_' || p_action, 'tvde_access', p_client_id,
    jsonb_build_object('action', p_action, 'tvde_access', v_new_access)
  );

  RETURN jsonb_build_object('client_id', p_client_id, 'tvde_access', v_new_access, 'action', p_action);
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_tvde_access(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_tvde_access(UUID, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- CICLO DA CORRIDA
-- ════════════════════════════════════════════════════════════════════════════

-- Cliente solicita corrida (fare calculada no servidor)
CREATE OR REPLACE FUNCTION public.tvde_request_ride(
  p_origin_lat DOUBLE PRECISION, p_origin_lng DOUBLE PRECISION, p_origin_label TEXT,
  p_dest_lat   DOUBLE PRECISION, p_dest_lng   DOUBLE PRECISION, p_dest_label   TEXT,
  p_est_distance_km NUMERIC
) RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_acc  BOOLEAN;
  v_fare INTEGER;
  v_ride public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT tvde_access INTO v_acc FROM public.users WHERE id = v_uid;
  IF v_acc IS NOT TRUE THEN RAISE EXCEPTION 'no_tvde_access'; END IF;

  IF EXISTS (SELECT 1 FROM public.tvde_rides WHERE client_id = v_uid
             AND status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'ride_in_progress';
  END IF;

  v_fare := public.tvde_calculate_fare(p_est_distance_km);

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label,
    dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, status
  ) VALUES (
    v_uid, p_origin_lat, p_origin_lng, p_origin_label,
    p_dest_lat, p_dest_lng, p_dest_label, p_est_distance_km, v_fare, 'solicitada'
  ) RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
            jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_fare));

  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_request_ride(DOUBLE PRECISION,DOUBLE PRECISION,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_request_ride(DOUBLE PRECISION,DOUBLE PRECISION,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) TO authenticated;

-- Motorista aceita (claim) — vai a caminho
CREATE OR REPLACE FUNCTION public.tvde_accept_ride(p_ride_id UUID)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status <> 'solicitada' THEN RAISE EXCEPTION 'ride_not_available: %', v_ride.status; END IF;
  IF v_ride.current_offer_driver_id IS NOT NULL AND v_ride.current_offer_driver_id <> v_uid THEN
    RAISE EXCEPTION 'offer_belongs_to_other_driver';
  END IF;

  UPDATE public.tvde_rides
     SET driver_id = v_uid, status = 'motorista_a_caminho',
         current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_atribuido', 'driver');
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_a_caminho', 'driver');
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_accept_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_accept_ride(UUID) TO authenticated;

-- Motorista recusa oferta → liberta para o próximo (dispatch Fase 2)
CREATE OR REPLACE FUNCTION public.tvde_reject_ride(p_ride_id UUID)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;

  IF v_ride.current_offer_driver_id = v_uid THEN
    UPDATE public.tvde_rides
       SET current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id RETURNING * INTO v_ride;
  END IF;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_ride.status, 'driver', jsonb_build_object('rejected_by', v_uid));
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_reject_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_reject_ride(UUID) TO authenticated;

-- Motorista chegou
CREATE OR REPLACE FUNCTION public.tvde_driver_arrived(p_ride_id UUID)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status NOT IN ('motorista_a_caminho','motorista_atribuido') THEN
    RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  UPDATE public.tvde_rides SET status = 'motorista_chegou', updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_chegou', 'driver');
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_driver_arrived(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_driver_arrived(UUID) TO authenticated;

-- Inicia corrida
CREATE OR REPLACE FUNCTION public.tvde_start_ride(p_ride_id UUID)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'motorista_chegou' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  UPDATE public.tvde_rides SET status = 'em_andamento', updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'em_andamento', 'driver');
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_start_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_start_ride(UUID) TO authenticated;

-- Consome corrida de assinatura (incrementa contador diário + uso do plano)
CREATE OR REPLACE FUNCTION public.tvde_consume_subscription_ride(p_client_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sub public.tvde_subscriptions; v_today_count INT;
BEGIN
  SELECT * INTO v_sub FROM public.tvde_subscriptions
    WHERE client_id = p_client_id AND active = true
      AND now() BETWEEN starts_at AND ends_at AND rides_used < rides_total
    ORDER BY ends_at ASC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('covered', false, 'reason', 'no_subscription'); END IF;

  INSERT INTO public.tvde_ride_counters (client_id, day, rides_count)
    VALUES (p_client_id, current_date, 1)
    ON CONFLICT (client_id, day) DO UPDATE SET rides_count = public.tvde_ride_counters.rides_count + 1
    RETURNING rides_count INTO v_today_count;

  IF v_today_count <= v_sub.daily_included THEN
    UPDATE public.tvde_subscriptions SET rides_used = rides_used + 1 WHERE id = v_sub.id;
    RETURN jsonb_build_object('covered', true, 'subscription_id', v_sub.id,
      'daily_used', v_today_count, 'daily_included', v_sub.daily_included,
      'rides_left', v_sub.rides_total - v_sub.rides_used - 1);
  ELSE
    RETURN jsonb_build_object('covered', false, 'reason', 'daily_limit',
      'daily_used', v_today_count,
      'extra_ride_cents', (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int);
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_consume_subscription_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_consume_subscription_ride(UUID) TO authenticated;

-- Finaliza: tarifa final por distância real + ganho motorista/Bora + liquidação cash
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id UUID, p_final_distance_km NUMERIC)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_fare    := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base  := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;
  v_bora_cut := v_fare - v_driver_earn;  -- sempre o resto (auto-consistente)

  -- assinatura (se houver)
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  UPDATE public.tvde_rides SET
    status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Liquidação CASH isolada: só quando o passageiro paga em dinheiro (não coberto por assinatura)
  IF v_covered IS NOT TRUE THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_bora_cut / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_bora_cut / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver',
      jsonb_build_object('final_distance_km', p_final_distance_km, 'final_fare_cents', v_fare,
        'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut, 'subscription', v_sub));
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) TO authenticated;

-- Cancelar (cliente / motorista / no_show)
CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(p_ride_id UUID, p_actor TEXT, p_reason TEXT DEFAULT NULL)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_new_status TEXT; v_fee INT := 0; v_is_admin BOOLEAN := public.is_admin();
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN
    RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN
    RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;

  v_new_status := CASE p_actor
    WHEN 'cliente' THEN 'cancelada_cliente'
    WHEN 'motorista' THEN 'cancelada_motorista'
    ELSE 'no_show' END;

  -- Taxa só se já havia motorista atribuído (config; default 0)
  IF v_ride.status <> 'solicitada' THEN
    v_fee := (public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int;
  END IF;

  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason,
    cancel_fee_cents = v_fee, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END,
            jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee));
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_cancel_ride(UUID, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_cancel_ride(UUID, TEXT, TEXT) TO authenticated;

-- Avaliação bidirecional (cliente→motorista usa subject_type='driver'; motorista→passageiro 'tvde_passenger')
CREATE OR REPLACE FUNCTION public.tvde_rate(p_ride_id UUID, p_stars SMALLINT, p_comment TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_subject_type TEXT; v_subject_id TEXT;
BEGIN
  IF p_stars < 1 OR p_stars > 5 THEN RAISE EXCEPTION 'invalid_stars'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status <> 'finalizada' THEN RAISE EXCEPTION 'ride_not_finished'; END IF;

  IF v_uid = v_ride.client_id THEN
    IF v_ride.rated_by_client THEN RAISE EXCEPTION 'already_rated'; END IF;
    v_subject_type := 'driver'; v_subject_id := v_ride.driver_id::text;
    INSERT INTO public.ratings (driver_id, rating, stars, comment, subject_type, subject_id, rater_user_id)
      VALUES (v_ride.driver_id, p_stars, p_stars, p_comment, 'driver', v_subject_id, v_uid);
    UPDATE public.tvde_rides SET rated_by_client = true WHERE id = p_ride_id;
  ELSIF v_uid = v_ride.driver_id THEN
    IF v_ride.rated_by_driver THEN RAISE EXCEPTION 'already_rated'; END IF;
    v_subject_type := 'tvde_passenger'; v_subject_id := v_ride.client_id::text;
    INSERT INTO public.ratings (rating, stars, comment, subject_type, subject_id, rater_user_id)
      VALUES (p_stars, p_stars, p_comment, 'tvde_passenger', v_subject_id, v_uid);
    UPDATE public.tvde_rides SET rated_by_driver = true WHERE id = p_ride_id;
  ELSE
    RAISE EXCEPTION 'not_ride_party';
  END IF;

  RETURN jsonb_build_object('ride_id', p_ride_id, 'subject_type', v_subject_type, 'stars', p_stars);
END; $$;
REVOKE ALL ON FUNCTION public.tvde_rate(UUID, SMALLINT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_rate(UUID, SMALLINT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- ASSINATURA — admin concede (Stripe adiado)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_grant_subscription(p_client_id UUID, p_plan TEXT)
RETURNS public.tvde_subscriptions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin RECORD; v_rides_total INT; v_price INT; v_days INT;
  v_daily INT := (public.get_setting('tvde_plan_daily_included') #>> '{}')::int;
  v_sub public.tvde_subscriptions;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_plan NOT IN ('semanal','quinzenal','mensal') THEN RAISE EXCEPTION 'invalid_plan: %', p_plan; END IF;

  IF p_plan = 'semanal' THEN
    v_rides_total := 14; v_days := 7;  v_price := (public.get_setting('tvde_plan_weekly_cents') #>> '{}')::int;
  ELSIF p_plan = 'quinzenal' THEN
    v_rides_total := 30; v_days := 15; v_price := (public.get_setting('tvde_plan_biweekly_cents') #>> '{}')::int;
  ELSE
    v_rides_total := 60; v_days := 30; v_price := (public.get_setting('tvde_plan_monthly_cents') #>> '{}')::int;
  END IF;

  -- desativa assinaturas ativas anteriores (evita sobreposição)
  UPDATE public.tvde_subscriptions SET active = false WHERE client_id = p_client_id AND active = true;

  INSERT INTO public.tvde_subscriptions
    (client_id, plan, rides_total, daily_included, price_cents, granted_by, starts_at, ends_at, active)
  VALUES
    (p_client_id, p_plan, v_rides_total, v_daily, v_price, v_admin.admin_id, now(), now() + (v_days || ' days')::interval, true)
  RETURNING * INTO v_sub;

  PERFORM public.log_admin_action(
    'tvde_subscription_granted', 'tvde_subscription', v_sub.id,
    jsonb_build_object('client_id', p_client_id, 'plan', p_plan, 'rides_total', v_rides_total, 'price_cents', v_price)
  );
  RETURN v_sub;
END; $$;
REVOKE ALL ON FUNCTION public.admin_grant_subscription(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_subscription(UUID, TEXT) TO authenticated;

COMMIT;
