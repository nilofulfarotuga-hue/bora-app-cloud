-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE-CAMPO-02 · DECISÃO #3 — ida-volta é EXTRA (não consome a corrida do plano)
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO — aplicar com "vai" (implementa decisão do Danilo, escopo F3).
--
-- Decisão do Danilo (provisória, revê pós-lançamento): um cliente de plano PODE
-- comprar o pacote ida-e-volta (8€) e isso é um EXTRA — NÃO consome a corrida grátis
-- do dia. A versão anterior chamava tvde_consume_subscription_ride SEMPRE, inclusive
-- na corrida pré-paga do vale, o que descontaria a corrida do plano. Corrigido:
-- numa corrida pré-paga (roundtrip_credit_id != NULL) NÃO se consome o plano.
--
-- Compatibilidade: corridas SEM pré-pago mantêm-se idênticas (consomem/85%/extra-ride).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tvde_finish_ride(
  p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

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

  IF v_prepaid THEN
    -- [DECISÃO #3] ida-volta é EXTRA: NÃO consome o plano. Cliente paga 0 pela corrida
    -- (8€ pré-pagos); motorista recebe o ganho completo. Paradas à parte.
    v_covered     := false;
    v_sub         := jsonb_build_object('covered', false, 'prepaid_roundtrip', true);
    v_sub_id      := NULL;
    v_fare        := v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  ELSE
    v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
    v_covered := COALESCE((v_sub->>'covered')::boolean, false);
    v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
    IF v_covered THEN
      -- coberta pelo plano: motorista 85% do ganho da CORRIDA; Bora 15%; cliente 0.
      -- Paradas somam-se SEMPRE (não cobertas) e NÃO entram nos 85%.
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
  END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source), updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

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
      'distance_source', p_distance_source, 'subscription', v_sub));

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
REVOKE ALL ON FUNCTION public.tvde_finish_ride(uuid, numeric, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(uuid, numeric, text) TO authenticated;
