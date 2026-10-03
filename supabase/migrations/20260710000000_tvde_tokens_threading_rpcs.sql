-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE — Threading de tokens (desconto na corrida)
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO (🔴) — aplicar com "vai" do Danilo.
--
-- Objetivo: permitir ao cliente GASTAR Bora Tokens numa corrida TVDE
-- (a semelhança do delivery orders.tokens_applied_count / tokens_applied_value_cents).
--
-- Regra:
-- • Token value: €0,005 = 5 cents (BRTokens.TOKEN_VALUE_EUR × 100)
-- • Max desconto: 50% do valor cobrado ao cliente (token_payment_max_pct)
-- • Cálculo: tokens_discount_cents = MIN(p_tokens_to_apply × 5, charge_total_cents × 50 / 100)
-- • Gasto: só CLIENTE paga menos (desconto). Motorista e Bora não mudam.
-- • Registro: tokens_applied_count (n.º tokens) e tokens_applied_value_cents (€ desconto)
--   em tvde_rides.
--
-- Não mexe em:
-- • GANHO de tokens (sempre zero para TVDE) — só GASTA.
-- • Lógica de pricing (base, por-km, plano, paradas, volta).
-- • Ledger de tokens (fora do escopo desta migration).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) tvde_request_ride — adiciona p_tokens_to_apply + desconto na estimativa
CREATE OR REPLACE FUNCTION public.tvde_request_ride(
  p_origin_lat double precision, p_origin_lng double precision, p_origin_label text,
  p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_est_distance_km numeric,
  p_tokens_to_apply INT DEFAULT 0)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_acc BOOLEAN; v_fare INTEGER; v_ride public.tvde_rides;
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID; v_is_member BOOLEAN;
  v_d_base INT; v_d_perkm INT; v_extra_km INT;
  v_driver_normal INT; v_driver_earn INT; v_client_fare INT; v_bora_cut INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT;
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
    v_client_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_client_fare - v_driver_normal;
  ELSE
    v_client_fare := v_fare;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_fare - v_driver_normal;
  END IF;

  -- ┌─────────────────────────────────────────────────────────────────────┐
  -- │ TOKENS: calcular desconto (MAX 50% do valor cobrado)               │
  -- └─────────────────────────────────────────────────────────────────────┘
  IF p_tokens_to_apply > 0 AND v_client_fare > 0 THEN
    v_max_discount_cents := GREATEST(0, (v_client_fare * 50) / 100);
    v_tokens_discount_cents := LEAST(p_tokens_to_apply * 5, v_max_discount_cents);
    v_client_fare := v_client_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    used_subscription_ride, subscription_id, status,
    tokens_applied_count, tokens_applied_value_cents)
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut, v_covered, v_sub_id, 'solicitada',
    p_tokens_to_apply, v_tokens_discount_cents)
  RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'is_member', v_is_member, 'driver_earn_cents', v_driver_earn,
        'tokens_applied_count', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));

  RETURN v_ride;
END; $function$;

REVOKE ALL ON FUNCTION public.tvde_request_ride(double precision, double precision, text, double precision, double precision, text, numeric, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_request_ride(double precision, double precision, text, double precision, double precision, text, numeric, INT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────

-- 2) tvde_finish_ride (3-arg) — adiciona p_tokens_to_apply + desconto na cobrança
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(
  p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text,
  p_tokens_to_apply INT DEFAULT 0)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  -- Paradas (F1) e pré-pago (F3)
  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  IF v_prepaid THEN
    v_fare        := v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  ELSIF v_covered THEN
    v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
    v_fare        := v_stops_fee;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    END IF;
    v_fare        := v_fare + v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  END IF;

  -- ┌─────────────────────────────────────────────────────────────────────┐
  -- │ TOKENS: calcular e aplicar desconto (MAX 50% do valor final)       │
  -- └─────────────────────────────────────────────────────────────────────┘
  IF p_tokens_to_apply > 0 AND v_fare > 0 THEN
    v_max_discount_cents := GREATEST(0, (v_fare * 50) / 100);
    v_tokens_discount_cents := LEAST(p_tokens_to_apply * 5, v_max_discount_cents);
    v_fare := v_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source),
    tokens_applied_count = CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply ELSE tokens_applied_count END,
    tokens_applied_value_cents = CASE WHEN p_tokens_to_apply > 0 THEN v_tokens_discount_cents ELSE tokens_applied_value_cents END,
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Liquidação em balances (igual ao logic original, com desconto de tokens já aplicado)
  IF v_covered OR v_prepaid THEN
    v_settle := v_stops_fee - v_stops_drv;
  ELSE
    v_settle := v_bora_cut;
  END IF;
  IF v_settle > 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid,
      'distance_source', p_distance_source, 'subscription', v_sub,
      'tokens_applied_count', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));

  -- Back-to-back (PRESERVADO)
  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true
               AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END; $function$;

REVOKE ALL ON FUNCTION public.tvde_finish_ride(uuid, numeric, text, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(uuid, numeric, text, INT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Compatibility: Manter as overloads de 2 e 3 args (sem tokens) delegando na nova 4-arg
-- ─────────────────────────────────────────────────────────────────────────────

-- 2-arg → delega na 4-arg com tokens_to_apply=0 (sem distance_source nem tokens)
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric)
RETURNS public.tvde_rides
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.tvde_finish_ride(p_ride_id, p_final_distance_km, NULL::text, 0); $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(uuid, numeric) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(uuid, numeric) TO authenticated;

-- 3-arg (com distance_source) → delega na 4-arg com tokens_to_apply=0
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric, p_distance_source text)
RETURNS public.tvde_rides
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.tvde_finish_ride(p_ride_id, p_final_distance_km, p_distance_source, 0); $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(uuid, numeric, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(uuid, numeric, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK (se necessário)
-- ═══════════════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.tvde_request_ride(double precision, double precision, text, double precision, double precision, text, numeric, INT) CASCADE;
-- DROP FUNCTION IF EXISTS public.tvde_finish_ride(uuid, numeric, text, INT) CASCADE;
--
-- CREATE OR REPLACE FUNCTION public.tvde_request_ride(...) — versão anterior (sem tokens)
-- CREATE OR REPLACE FUNCTION public.tvde_finish_ride(...) — versão anterior (sem tokens)
