-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item B ponto 3: preço da corrida EXTRA do membro do plano.
--
-- Estado antes: coberta → €0 (ok). Fora do limite diário / plano esgotado →
-- cobrava a tarifa PADRÃO (tvde_calculate_fare, €5). Devia cobrar o preço de
-- corrida EXTRA do plano: tvde_extra_ride_cents (€4.50).
--
-- Regra (3 tiers), aplicada em request (estimativa/insert) e finish (cobrança):
--   • COBERTA (plano ativo, dentro do limite diário, plano não esgotado)
--       → cliente €0 · motorista ganho normal × 0.85 · Bora fica com 15%.
--   • MEMBRO ATIVO mas fora do limite / plano esgotado (v_is_member por datas)
--       → cliente tvde_extra_ride_cents (€4.50) · motorista GANHO NORMAL ·
--         Bora fica com o resto (decisão do Danilo — pode subsidiar corridas
--         longas onde o ganho normal passa dos €4.50).
--   • SEM PLANO ativo → tarifa padrão (tvde_calculate_fare) · ganho normal.
--
-- Só toca nestas 3 funções (request + os 2 overloads de finish). Não mexe em
-- consume/preview/counters. is_member = subscrição active=true dentro das datas
-- (ignora rides_used → apanha também o plano esgotado, como pede o ponto 3).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) REQUEST — estimativa + insert da corrida ────────────────────────────────
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
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID; v_is_member BOOLEAN;
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
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_normal := v_d_base + v_extra_km * v_d_perkm;
  v_cov := public.tvde_preview_coverage(v_uid);
  v_covered := COALESCE((v_cov->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_cov->>'subscription_id','')::uuid;
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
    WHERE client_id = v_uid AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_is_member;
  IF v_covered THEN
    v_client_fare := 0;
    v_driver_earn := ROUND(v_driver_normal * 0.85)::int;
    v_bora_cut    := v_driver_normal - v_driver_earn;
  ELSIF v_is_member THEN
    -- [Item B p3] corrida extra do membro → preço de plano, motorista ganho normal.
    v_client_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_client_fare - v_driver_normal;
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
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut, v_covered, v_sub_id, 'solicitada')
  RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'is_member', v_is_member, 'driver_earn_cents', v_driver_earn));
  RETURN v_ride;
END; $function$;

-- 2) FINISH (overload 2 args) — cobrança final ───────────────────────────────
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;
  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
  IF v_covered THEN
    v_bora_cut    := v_driver_earn - ROUND(v_driver_earn * 0.85)::int;
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int;
    v_fare        := 0;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;  -- [Item B p3]
    END IF;
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
  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;
  RETURN v_ride;
END; $function$;

-- 3) FINISH (overload 3 args, com distance_source) ───────────────────────────
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;
  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
  IF v_covered THEN
    v_bora_cut    := v_driver_earn - ROUND(v_driver_earn * 0.85)::int;
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int;
    v_fare        := 0;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;  -- [Item B p3]
    END IF;
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
  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;
  RETURN v_ride;
END; $function$;
