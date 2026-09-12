-- ============================================================================
-- TVDE — CORRIDAS EM FILA (BACK-TO-BACK, estilo Uber) · Parte 3
-- ----------------------------------------------------------------------------
-- Como a Uber: perto do FIM da viagem, se surgir pedido com pickup próximo do
-- destino atual, o motorista recebe a oferta DURANTE a viagem; aceita → fica
-- motorista_atribuido + is_queued=true; ao finalizar a atual, a fila ativa-se
-- (motorista_a_caminho) e o passageiro recebe o push 'a_caminho' pela infra
-- notify-tvde-client existente (trigger dispara na mudança de status).
--
-- REGRAS (refinam a Parte 2b — não a revertem):
--  • Livre GANHA sempre do ocupado (tier 1 intacto; tier 2 só se tier 1 vazio).
--  • Ocupado só é candidato se: viagem atual 'em_andamento' (passageiro a
--    bordo) E pickup novo a ≤ tvde_queue_pickup_radius_km do destino atual
--    E sem corrida já em fila (máx 1) E sem entrega ativa.
--  • Com corrida em fila → mais NENHUMA oferta (o NOT EXISTS de ocupado do
--    tier 1 e o guard de fila do tier 2 cobrem ambos os casos).
--  • Oferta em fila expirada → sweep/rotação NORMAIS (mecânica de oferta
--    intacta: current_offer_driver_id + offer_expires_at + tried_driver_ids).
--  • Cancelamento da viagem atual com fila → a fila ativa-se também.
-- Pagamento: corrida em fila paga IGUAL a corrida normal (tvde_finish_ride
-- financeiro byte-idêntico; só se acrescenta a ativação da fila no fim).
-- ============================================================================

-- 1) Coluna aditiva
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS is_queued boolean NOT NULL DEFAULT false;

-- 2) Raio configurável (aparece no admin via admin_list_settings)
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_queue_pickup_radius_km', to_jsonb(3),
        'Raio (km) entre o destino da viagem atual e o pickup novo para oferta em fila (back-to-back). 0 desliga a fila.',
        'tvde')
ON CONFLICT (key) DO NOTHING;

-- 3) Matching com 2 níveis: livres primeiro; ocupados-perto só se não há livres
CREATE OR REPLACE FUNCTION public.tvde_offer_to_next(p_ride_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ride   public.tvde_rides;
  v_driver UUID;
  v_ttl    INT := (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int;
  v_hb     INT := (public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int;
  v_radius NUMERIC := COALESCE((public.get_setting('tvde_queue_pickup_radius_km') #>> '{}')::numeric, 3);
  v_queued BOOLEAN := false;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  -- TIER 1 — motoristas LIVRES online (comportamento atual, intacto)
  SELECT d.user_id INTO v_driver
  FROM public.drivers d
  JOIN public.driver_locations dl ON dl.driver_id = d.user_id
  WHERE d.vehicle_type = 'carro_passageiros'
    AND d.approval_status = 'approved'
    AND d.user_id IS NOT NULL
    AND (dl.is_online = true OR d.is_online = true)
    AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                 COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
        > now() - make_interval(secs => v_hb)
    AND dl.latitude IS NOT NULL AND dl.longitude IS NOT NULL
    AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.user_id
        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
    -- dual-driver: entrega ativa -> sem ofertas de corrida TVDE
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.assigned_driver_id = d.id::text
        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
  ORDER BY public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
  LIMIT 1;

  -- TIER 2 — back-to-back: só se NENHUM livre; motorista 'em_andamento' cujo
  -- DESTINO atual está a <= raio do pickup novo, sem fila e sem entrega ativa.
  IF v_driver IS NULL AND v_radius > 0 THEN
    SELECT d.user_id INTO v_driver
    FROM public.drivers d
    JOIN public.tvde_rides cur ON cur.driver_id = d.user_id AND cur.status = 'em_andamento'
    WHERE d.vehicle_type = 'carro_passageiros'
      AND d.approval_status = 'approved'
      AND d.user_id IS NOT NULL
      AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
      AND NOT EXISTS (
        SELECT 1 FROM public.tvde_rides r3
        WHERE r3.driver_id = d.user_id
          AND r3.is_queued = true AND r3.status = 'motorista_atribuido')
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.assigned_driver_id = d.id::text
          AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
      AND public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                               v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) <= v_radius
    ORDER BY public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                                  v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
    LIMIT 1;
    v_queued := v_driver IS NOT NULL;
  END IF;

  IF v_driver IS NULL THEN
    UPDATE public.tvde_rides
       SET status='sem_motorista', current_offer_driver_id=NULL, offer_expires_at=NULL, updated_at=now()
     WHERE id = p_ride_id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor) VALUES (p_ride_id,'sem_motorista','system');
    RETURN false;
  END IF;

  UPDATE public.tvde_rides
     SET current_offer_driver_id = v_driver,
         offer_expires_at = now() + make_interval(secs => v_ttl), updated_at = now()
   WHERE id = p_ride_id;
  INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
    VALUES (p_ride_id,'oferta','system',
            jsonb_build_object('driver_id', v_driver, 'expires_in_s', v_ttl, 'queued_candidate', v_queued));
  RETURN true;
END; $function$;

-- 4) Aceite: motorista com viagem em curso aceita → fica EM FILA (máx 1)
CREATE OR REPLACE FUNCTION public.tvde_accept_ride(p_ride_id uuid)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_pre public.tvde_rides; v_current UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_pre FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_pre.status <> 'solicitada' THEN RAISE EXCEPTION 'ride_not_available: %', v_pre.status; END IF;
  IF v_uid = ANY(v_pre.tried_driver_ids) THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;
  IF v_pre.current_offer_driver_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;

  -- back-to-back: viagem atual em curso -> a nova corrida entra EM FILA
  SELECT r2.id INTO v_current FROM public.tvde_rides r2
   WHERE r2.driver_id = v_uid AND r2.status = 'em_andamento' LIMIT 1;
  IF v_current IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.tvde_rides r3
               WHERE r3.driver_id = v_uid AND r3.is_queued = true
                 AND r3.status = 'motorista_atribuido') THEN
      RAISE EXCEPTION 'queue_full';
    END IF;
    UPDATE public.tvde_rides
       SET driver_id = v_uid, status = 'motorista_atribuido', is_queued = true,
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id AND status = 'solicitada' AND driver_id IS NULL
       AND current_offer_driver_id = v_uid
     RETURNING * INTO v_ride;
    IF NOT FOUND THEN RAISE EXCEPTION 'ride_already_taken'; END IF;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'motorista_atribuido', 'driver',
              jsonb_build_object('queued', true, 'behind_ride_id', v_current));
    RETURN v_ride;
  END IF;

  UPDATE public.tvde_rides
     SET driver_id = v_uid, status = 'motorista_a_caminho',
         current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id AND status = 'solicitada' AND driver_id IS NULL
     AND current_offer_driver_id = v_uid
   RETURNING * INTO v_ride;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_already_taken'; END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_atribuido', 'driver');
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_a_caminho', 'driver');
  RETURN v_ride;
END; $function$;

-- 5) Finalizar: financeiro BYTE-IDÊNTICO; no fim, ativa a corrida em fila.
--    A mudança de status dispara o push 'a_caminho' (notify-tvde-client).
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
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;
  v_bora_cut := v_fare - v_driver_earn;
  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
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

  -- back-to-back: ativa a corrida em fila deste motorista, se existir
  UPDATE public.tvde_rides
     SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3
               WHERE r3.driver_id = v_uid AND r3.is_queued = true
                 AND r3.status = 'motorista_atribuido'
               ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system',
              jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END; $function$;

-- 6) Cancelar: limpa is_queued no terminal; se a viagem CANCELADA era a ativa
--    do motorista, a corrida em fila ativa-se (mesma regra do finalizar).
CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(p_ride_id uuid, p_actor text, p_reason text DEFAULT NULL::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_new_status TEXT; v_fee INT := 0;
  v_is_admin BOOLEAN := public.is_admin(); v_was_active_of_driver BOOLEAN := false; v_next UUID;
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;
  v_was_active_of_driver := v_ride.driver_id IS NOT NULL AND v_ride.is_queued = false
    AND v_ride.status IN ('motorista_a_caminho','motorista_chegou','em_andamento');
  v_new_status := CASE p_actor WHEN 'cliente' THEN 'cancelada_cliente' WHEN 'motorista' THEN 'cancelada_motorista' ELSE 'no_show' END;
  IF v_ride.status <> 'solicitada' THEN v_fee := (public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int; END IF;
  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason, cancel_fee_cents = v_fee,
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END, jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee));

  -- back-to-back: a ativa caiu -> ativa a corrida em fila do motorista
  IF v_was_active_of_driver THEN
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_ride.driver_id AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
                jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_cancel', true));
    END IF;
  END IF;

  RETURN v_ride;
END; $function$;
