-- =============================================================================
-- ronda-fecho-2026-09-22 · A2 (c) — o admin resolve uma volta retida:
-- corrige a distância (recalcula o ganho da volta pela regra do pacote) e
-- liberta para despacho, ou cancela e devolve o vale ao cliente.
-- Chamada pelo painel (Pendências de operação) e pela central por MCP
-- (is_admin() com o JWT do admin; sem JWT usar o caminho ops_* da A5).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_tvde_ride_release_hold(p_ride_id uuid, p_est_distance_km numeric DEFAULT NULL::numeric, p_nota text DEFAULT NULL::text, p_cancelar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ride public.tvde_rides; v_km numeric; v_d_base int; v_d_perkm int; v_extra_km int; v_earn int;
  v_admin uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.dispatch_hold_reason IS NULL THEN RAISE EXCEPTION 'ride_not_on_hold'; END IF;
  IF v_ride.status <> 'solicitada' THEN RAISE EXCEPTION 'invalid_status: %', v_ride.status; END IF;

  IF COALESCE(p_cancelar, false) THEN
    UPDATE public.tvde_rides
       SET status = 'cancelada_cliente', cancel_reason = 'distancia_suspeita_cancelada_admin',
           cancel_fee_cents = 0, dispatch_hold_reason = NULL, dispatch_hold_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    -- o vale volta ao cliente (se ainda estiver dentro da validade)
    IF v_ride.roundtrip_credit_id IS NOT NULL THEN
      UPDATE public.tvde_roundtrip_credits
         SET status = CASE WHEN expires_at > now() THEN 'ativo' ELSE 'expirado' END,
             return_ride_id = NULL
       WHERE id = v_ride.roundtrip_credit_id AND return_ride_id = p_ride_id;
    END IF;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'correcao_manual', 'admin',
      jsonb_build_object('pendente', false, 'resolvido', true, 'accao', 'cancelada',
        'motivo', v_ride.dispatch_hold_reason, 'nota', p_nota, 'admin', v_admin,
        'vale_devolvido', v_ride.roundtrip_credit_id IS NOT NULL));
    RETURN jsonb_build_object('ok', true, 'ride_id', p_ride_id, 'accao', 'cancelada');
  END IF;

  v_km := COALESCE(p_est_distance_km, v_ride.est_distance_km);
  IF v_km IS NULL OR v_km <= 0 THEN RAISE EXCEPTION 'distancia_invalida'; END IF;
  v_d_base   := (public.get_setting(CASE WHEN COALESCE(v_ride.is_return_leg, false)
                                         THEN 'tvde_roundtrip_return_driver_cents'
                                         ELSE 'tvde_driver_base_cents' END) #>> '{}')::int;
  v_d_perkm  := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(v_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_earn     := v_d_base + v_extra_km * v_d_perkm;

  UPDATE public.tvde_rides
     SET est_distance_km = v_km, driver_earn_cents = v_earn,
         dispatch_hold_reason = NULL, dispatch_hold_at = NULL, updated_at = now()
   WHERE id = p_ride_id;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride_id, 'correcao_manual', 'admin',
    jsonb_build_object('pendente', false, 'resolvido', true, 'accao', 'libertada',
      'motivo', v_ride.dispatch_hold_reason, 'km_antes', v_ride.est_distance_km, 'km_depois', v_km,
      'driver_earn_cents_antes', v_ride.driver_earn_cents, 'driver_earn_cents', v_earn,
      'nota', p_nota, 'admin', v_admin));
  PERFORM public.tvde_offer_to_next(p_ride_id);
  RETURN jsonb_build_object('ok', true, 'ride_id', p_ride_id, 'accao', 'libertada',
                            'est_distance_km', v_km, 'driver_earn_cents', v_earn);
END; $function$;

REVOKE ALL ON FUNCTION public.admin_tvde_ride_release_hold(uuid, numeric, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_tvde_ride_release_hold(uuid, numeric, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_ride_release_hold(uuid, numeric, text, boolean) TO authenticated, service_role;
