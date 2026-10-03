-- [Itens B + C / TVDE-CAMPO-01] Plano aplicado na corrida (taxa zero) + o motorista
-- ve o SEU liquido desde a oferta.
--
-- Regra confirmada pelo Danilo (2026-07-03): numa corrida COBERTA pelo plano o
-- cliente paga €0 e o motorista recebe ganho_normal * 0.85 (ganho_normal =
-- tvde_driver_base_cents + extra_km * tvde_driver_per_km_cents). Fora do plano
-- mantem-se tudo como esta (motorista = base+km, corte Bora = fare - ganho).
--
-- Contador diario / rides_used continuam a incrementar SO na corrida CONCLUIDA
-- (via tvde_consume_subscription_ride, intacto). A preview e READ-ONLY (nao
-- consome) e serve para o cliente ver €0 + badge ANTES de pedir, e para o
-- request gravar o ganho estimado do motorista (para a oferta/corrida mostrarem
-- o liquido do motorista, item C).
--
-- Zona protegida: nao toca no webhook Stripe, no finalizePurchase, nem no
-- dispatch. So mexe nas RPCs proprias do vertical TVDE.

-- ── 1. PREVIEW de cobertura (READ-ONLY, nao incrementa nada) ────────────────
CREATE OR REPLACE FUNCTION public.tvde_preview_coverage(p_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_sub public.tvde_subscriptions; v_today INT;
BEGIN
  SELECT * INTO v_sub FROM public.tvde_subscriptions
    WHERE client_id = p_client_id AND active = true
      AND now() BETWEEN starts_at AND ends_at AND rides_used < rides_total
    ORDER BY ends_at ASC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('covered', false, 'reason', 'no_subscription');
  END IF;
  SELECT COALESCE(rides_count, 0) INTO v_today
    FROM public.tvde_ride_counters WHERE client_id = p_client_id AND day = current_date;
  v_today := COALESCE(v_today, 0);
  IF v_today < v_sub.daily_included THEN
    RETURN jsonb_build_object('covered', true, 'subscription_id', v_sub.id,
      'daily_used', v_today, 'daily_included', v_sub.daily_included,
      'rides_left', v_sub.rides_total - v_sub.rides_used);
  ELSE
    RETURN jsonb_build_object('covered', false, 'reason', 'daily_limit',
      'daily_used', v_today, 'daily_included', v_sub.daily_included);
  END IF;
END; $function$;

GRANT EXECUTE ON FUNCTION public.tvde_preview_coverage(uuid) TO authenticated;

-- ── 2. REQUEST: cobertura + ganho estimado do motorista ─────────────────────
CREATE OR REPLACE FUNCTION public.tvde_request_ride(
  p_origin_lat double precision, p_origin_lng double precision, p_origin_label text,
  p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_est_distance_km numeric)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_acc BOOLEAN; v_fare INTEGER; v_ride public.tvde_rides;
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID;
  v_d_base INT; v_d_perkm INT; v_extra_km INT;
  v_driver_normal INT; v_driver_earn INT; v_client_fare INT; v_bora_cut INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT tvde_access INTO v_acc FROM public.users WHERE id = v_uid;
  IF v_acc IS NOT TRUE THEN RAISE EXCEPTION 'no_tvde_access'; END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_rides WHERE client_id = v_uid
             AND status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'ride_in_progress'; END IF;

  v_fare := public.tvde_calculate_fare(p_est_distance_km);

  -- ganho NORMAL do motorista (mesma formula do finish)
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_normal := v_d_base + v_extra_km * v_d_perkm;

  -- cobertura pelo plano (READ-ONLY — nao consome)
  v_cov := public.tvde_preview_coverage(v_uid);
  v_covered := COALESCE((v_cov->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_cov->>'subscription_id','')::uuid;

  IF v_covered THEN
    v_client_fare := 0;                                  -- cliente paga €0
    v_driver_earn := ROUND(v_driver_normal * 0.85)::int; -- 85% do normal
    v_bora_cut    := v_driver_normal - v_driver_earn;    -- 15% Bora
  ELSE
    v_client_fare := v_fare;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_fare - v_driver_normal;
  END IF;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    used_subscription_ride, subscription_id, status)
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut,
    v_covered, v_sub_id, 'solicitada')
  RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'driver_earn_cents', v_driver_earn));
  RETURN v_ride;
END; $function$;

-- ── 3. FINISH (2 overloads): corrida coberta → 85% ao motorista, cliente €0 ──
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;
  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;                -- normal
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
  IF v_covered THEN
    v_bora_cut    := v_driver_earn - ROUND(v_driver_earn * 0.85)::int; -- 15% Bora
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int;                 -- 85% motorista
    v_fare        := 0;                                                -- cliente paga €0
  ELSE
    v_bora_cut := v_fare - v_driver_earn;
  END IF;
  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  IF v_covered IS NOT TRUE THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_bora_cut / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE SET balance = public.tvde_driver_balances.balance + ROUND(v_bora_cut / 100.0, 2), updated_at = now();
  END IF;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut, 'subscription', v_sub));
  UPDATE public.tvde_rides
     SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3
               WHERE r3.driver_id = v_uid AND r3.is_queued = true AND r3.status = 'motorista_atribuido'
               ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;
  RETURN v_ride;
END; $function$;

CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;
  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;                -- normal
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
  IF v_covered THEN
    v_bora_cut    := v_driver_earn - ROUND(v_driver_earn * 0.85)::int;
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int;
    v_fare        := 0;
  ELSE
    v_bora_cut := v_fare - v_driver_earn;
  END IF;
  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source), updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  IF v_covered IS NOT TRUE THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_bora_cut / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE SET balance = public.tvde_driver_balances.balance + ROUND(v_bora_cut / 100.0, 2), updated_at = now();
  END IF;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'distance_source', p_distance_source, 'subscription', v_sub));
  UPDATE public.tvde_rides
     SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3
               WHERE r3.driver_id = v_uid AND r3.is_queued = true AND r3.status = 'motorista_atribuido'
               ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;
  RETURN v_ride;
END; $function$;
