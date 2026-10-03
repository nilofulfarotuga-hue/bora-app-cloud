-- =============================================================================
-- ronda-fecho-2026-09-22 · A2 (a) — pacote ida-e-volta: guarda de distância na
-- segunda perna (a volta com distância suspeita NÃO dispara; fica retida para
-- correção manual do admin).
--
-- Caso real: volta 1d24a5c2 (vale 1ef05919, ida 1b522c7b de 2,43 km). O
-- geocode de "Casa China" caiu a 50,32 km; a volta despachou e fechou com
-- ganho 39,50 (3,50 + 45 km x 0,80). A linha da corrida foi corrigida por MCP a
-- 18/09 (2,43 km, ganho 3,50, evento correcao_manual).
--
-- O que muda aqui:
--   1) tvde_rides.dispatch_hold_reason / dispatch_hold_at (NULL = normal).
--   2) settings: tvde_roundtrip_return_max_ratio (3x a ida),
--      tvde_roundtrip_return_max_km (30 km), dispatch_gps_fresh_seconds (180).
--   3) tvde_request_return_ride: volta suspeita nasce retida, com o ganho
--      calculado pela distância da ida, evento correcao_manual PENDENTE e
--      alerta ao admin (Pendências de operação).
--   4) fn_tvde_dispatch_on_request não dispara corridas retidas.
-- As restantes peças (tvde_offer_to_next, admin_tvde_ride_release_hold e a
-- correção do evento da volta da Stela) estão nas migrações irmãs
-- 20260923_ronda_a2_b_*, _c_* e _d_*.
-- =============================================================================

ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS dispatch_hold_reason text,
  ADD COLUMN IF NOT EXISTS dispatch_hold_at timestamptz;

COMMENT ON COLUMN public.tvde_rides.dispatch_hold_reason IS
  'Retenção do despacho: NULL = normal; distancia_suspeita = volta de pacote com distância suspeita, à espera de correção manual do admin (admin_tvde_ride_release_hold).';

INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('tvde_roundtrip_return_max_ratio', '3'::jsonb,
   'Pacote ida-e-volta: a volta com mais do que estas vezes a distância da ida é suspeita — fica retida para correção manual, não dispara (caso Stela 18/09: geocode a 50 km).',
   'tvde'),
  ('tvde_roundtrip_return_max_km', '30'::jsonb,
   'Pacote ida-e-volta: volta acima destes km é suspeita — fica retida para correção manual, não dispara.',
   'tvde'),
  ('dispatch_gps_fresh_seconds', '180'::jsonb,
   'Despacho (entregas e TVDE): motorista/estafeta cuja última posição GPS tem mais do que estes segundos não recebe oferta e é posto offline pelo relógio. Online = heartbeat vivo E GPS fresco.',
   'dispatch')
ON CONFLICT (key) DO NOTHING;

-- ── 3) tvde_request_return_ride com a guarda ────────────────────────────────
CREATE OR REPLACE FUNCTION public.tvde_request_return_ride(p_credit_id uuid, p_origin_lat double precision, p_origin_lng double precision, p_origin_label text, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text, p_est_distance_km numeric)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_credit public.tvde_roundtrip_credits; v_ride public.tvde_rides;
  v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT;
  v_out_km numeric; v_ratio numeric; v_max_km numeric; v_km_calc numeric;
  v_suspeita boolean := false; v_motivo text;
BEGIN
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits WHERE id = p_credit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credit_not_found'; END IF;
  IF v_credit.client_id <> v_uid THEN RAISE EXCEPTION 'not_credit_owner'; END IF;
  IF v_credit.status <> 'ativo' THEN RAISE EXCEPTION 'credit_not_active: %', v_credit.status; END IF;
  IF now() > v_credit.expires_at THEN
    UPDATE public.tvde_roundtrip_credits SET status = 'expirado' WHERE id = p_credit_id;
    RAISE EXCEPTION 'credit_expired';
  END IF;

  -- 2026-09-23 (ronda-fecho A2a, caso real Stela Neves 18/09): a volta com
  -- distância suspeita não dispara — fica retida para correção manual.
  SELECT COALESCE(r.final_distance_km, r.est_distance_km) INTO v_out_km
    FROM public.tvde_rides r WHERE r.id = v_credit.outbound_ride_id;
  v_ratio  := COALESCE((public.get_setting('tvde_roundtrip_return_max_ratio') #>> '{}')::numeric, 3);
  v_max_km := COALESCE((public.get_setting('tvde_roundtrip_return_max_km') #>> '{}')::numeric, 30);
  IF COALESCE(p_est_distance_km, 0) > v_max_km THEN
    v_suspeita := true;
    v_motivo := format('volta %s km acima do máximo %s km', p_est_distance_km, v_max_km);
  ELSIF v_out_km IS NOT NULL AND v_out_km > 0 AND COALESCE(p_est_distance_km, 0) > v_out_km * v_ratio THEN
    v_suspeita := true;
    v_motivo := format('volta %s km é mais de %s vezes a ida (%s km)', p_est_distance_km, v_ratio, v_out_km);
  END IF;
  -- Com distância suspeita o ganho calcula-se pela ida; o admin corrige ao libertar.
  v_km_calc := CASE WHEN v_suspeita THEN COALESCE(v_out_km, p_est_distance_km) ELSE p_est_distance_km END;

  -- Ganho do motorista da VOLTA = base da volta (tvde_roundtrip_return_driver_cents) + extra km.
  v_d_base   := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  v_d_perkm  := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(COALESCE(v_km_calc, 0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, payment_method, status, roundtrip_credit_id, is_return_leg,
    dispatch_hold_reason, dispatch_hold_at)
  VALUES (
    v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, 0, v_driver_earn, 'cash', 'solicitada', p_credit_id, true,
    CASE WHEN v_suspeita THEN 'distancia_suspeita' END,
    CASE WHEN v_suspeita THEN now() END)
  RETURNING * INTO v_ride;
  UPDATE public.tvde_roundtrip_credits SET status = 'usado', return_ride_id = v_ride.id WHERE id = p_credit_id;

  IF v_suspeita THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'correcao_manual', 'system',
      jsonb_build_object('pendente', true, 'motivo', 'distancia_suspeita', 'detalhe', v_motivo,
        'est_distance_km_pedido', p_est_distance_km, 'ida_km', v_out_km,
        'ganho_calculado_pela_ida_cents', v_driver_earn,
        'origin_label', p_origin_label, 'dest_label', p_dest_label));
    BEGIN
      PERFORM public.notify_admin_urgent_push(
        'tvde_return_suspect',
        E'⚠️ Volta de pacote retida (distância suspeita)\n' || v_motivo || ' · ' ||
          COALESCE(p_origin_label, '?') || ' → ' || COALESCE(p_dest_label, '?') ||
          '. Corrigir em Pendências de operação.',
        'tvde_ride', v_ride.id::text,
        jsonb_build_object('ride_id', v_ride.id, 'client_id', v_uid, 'credit_id', p_credit_id,
          'est_distance_km', p_est_distance_km, 'ida_km', v_out_km, 'motivo', v_motivo),
        '/admin/pendencias');
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'tvde_request_return_ride: alerta admin falhou (%)', sqlerrm;
    END;
  END IF;

  RETURN v_ride;
END; $function$;

-- ── 4) trigger de despacho respeita a retenção ──────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_tvde_dispatch_on_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.dispatch_hold_reason is not null then
    -- 2026-09-23 (A2a): corrida retida para correção manual — não dispara.
    insert into public.tvde_ride_events (ride_id, status, actor, meta)
    values (new.id, new.status, 'system',
      jsonb_build_object('dispatch_deferred', true,
        'payment_method', new.payment_method,
        'reason', 'retida para correcao manual: ' || new.dispatch_hold_reason));
  elsif new.status = 'solicitada' and new.payment_method = 'cash' then
    perform public.tvde_offer_to_next(new.id);
  elsif new.status = 'agendada' then
    insert into public.tvde_ride_events (ride_id, status, actor, meta)
    values (new.id, new.status, 'system',
      jsonb_build_object('dispatch_deferred', true,
        'payment_method', new.payment_method,
        'reason', case when new.reservation_status = 'aguarda_pagamento'
                       then 'reserva online: aguarda pagamento do cliente'
                       else 'reserva agendada: procura de motorista propria ate a hora marcada' end));
  else
    insert into public.tvde_ride_events (ride_id, status, actor, meta)
    values (new.id, new.status, 'system',
      jsonb_build_object('dispatch_deferred', true,
        'payment_method', new.payment_method,
        'reason', 'aguarda payment_status=succeeded'));
  end if;
  return new;
end; $function$;
