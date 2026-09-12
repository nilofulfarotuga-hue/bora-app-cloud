-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE-CAMPO-02 · CORREÇÃO — paradas (F1) + perna-de-volta (F3) na finish REAL
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO — aplicar com "vai" (dentro do escopo já aprovado de F1+F3).
--
-- BUG: o app do motorista chama tvde_finish_ride(uuid,numeric,text) (3 args, com
-- p_distance_source) — a versão REAL de produção (split coberta×0.85, corrida-extra
-- do plano, back-to-back). As migrations F1/F3 alteraram por engano a overload de
-- 2 args (nunca chamada). Esta correção põe paradas+volta na 3-arg CORRETA,
-- preservando exatamente a lógica existente, e faz a 2-arg delegar na 3-arg.
--
-- Compatibilidade: sem paradas, sem perna-de-volta e sem pré-pago, o resultado é
-- IDÊNTICO à versão atual de produção (verificado caso a caso).
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

  -- [F1] paradas (flat, cobradas SEMPRE) · [F3] perna-de-volta / pré-pago
  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;  -- 3,50
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;               -- 4,00
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;   -- ganho da CORRIDA (sem paradas)

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  IF v_prepaid THEN
    -- [F3] corrida do vale ida-volta: prepaga (8€). Cliente paga 0 pela corrida;
    -- o motorista recebe o ganho completo (o pré-pago cobre). Paradas à parte.
    -- ⚠️ EM ABERTO: payout do ganho a partir do pré-pago (mecanismo à parte).
    v_fare        := v_stops_fee;                       -- cliente só paga as paradas (cash)
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;            -- reporting (tipicamente negativo)
  ELSIF v_covered THEN
    -- coberta pelo plano: motorista 85% do ganho da CORRIDA; Bora 15%; cliente paga 0.
    -- Paradas somam-se SEMPRE (não cobertas) e NÃO entram nos 85%.
    v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
    v_fare        := v_stops_fee;                       -- cliente só paga as paradas
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;   -- corrida-extra do plano
    END IF;
    v_fare        := v_fare + v_stops_fee;              -- paradas somam ao que o cliente paga
    v_driver_earn := v_driver_earn + v_stops_drv;       -- e ao ganho do motorista
    v_bora_cut    := v_fare - v_driver_earn;
  END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source), updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Liquidação em balances (driver deve à Bora). Coberta/pré-pago: só a fatia Bora
  -- das PARADAS (a corrida-base não gera cash aqui — 85% do plano e payout do vale
  -- são pagos à parte). Normal: fatia Bora do total. (Preserva: coberta sem paradas
  -- = 0 → não liquida, tal como a versão atual.)
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

  -- back-to-back (PRESERVADO): ativa a corrida em fila do motorista
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

-- 2-arg → delega na 3-arg (elimina a divergência; sem "drop" p/ não bater na Trava)
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id uuid, p_final_distance_km numeric)
RETURNS public.tvde_rides
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.tvde_finish_ride(p_ride_id, p_final_distance_km, NULL::text); $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(uuid, numeric) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(uuid, numeric) TO authenticated;
