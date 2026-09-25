-- =============================================================================
-- ronda-fecho-2026-09-22 · A2 (b-guarda) + A10 — tvde_offer_to_next
-- Corpo igual ao de produção (20260914150204 + fila justa 18/09) com três
-- acréscimos assinalados "2026-09-23":
--   · corrida com dispatch_hold_reason preenchido não recebe oferta (A2a);
--   · motorista só entra na roda com GPS fresco: driver_locations.last_updated
--     dentro de dispatch_gps_fresh_seconds (180) — online = heartbeat E GPS (A10),
--     nas duas prioridades (livres e sobreposição).
-- =============================================================================
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
  -- 2026-09-23 (A10): posição GPS mais velha do que isto não recebe oferta.
  v_gps    INT := COALESCE((public.get_setting('dispatch_gps_fresh_seconds') #>> '{}')::int, 180);
  v_radius NUMERIC := COALESCE((public.get_setting('tvde_queue_pickup_radius_km') #>> '{}')::numeric, 3);
  v_window INT := COALESCE((public.get_setting('tvde_retry_window_seconds') #>> '{}')::int, 120);
  v_b2b    BOOLEAN := COALESCE((public.get_setting('tvde_backtoback_enabled') #>> '{}')::boolean, true);
  v_maxq   INT := COALESCE((public.get_setting('tvde_backtoback_max_queue') #>> '{}')::int, 1);
  v_stage  TEXT := COALESCE(public.get_setting('tvde_backtoback_min_stage') #>> '{}', 'motorista_a_caminho');
  v_stages TEXT[];
  v_queued BOOLEAN := false;
  v_fila   BOOLEAN := false;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;
  -- 2026-09-23 (A2a): corrida retida para correção manual não recebe oferta.
  IF v_ride.dispatch_hold_reason IS NOT NULL THEN RETURN false; END IF;

  -- 2026-09-18 FILA JUSTA, SO em corridas de BALCAO: entre os colegas, chama
  -- primeiro quem esta ha mais tempo sem corrida (quem acabou de fazer uma vai
  -- para o fim). Corridas da aplicacao continuam a ir ao mais PERTO, como sempre.
  v_fila := COALESCE(v_ride.source, 'app') = 'balcao'
        AND COALESCE((public.get_setting('tvde_fila_justa_balcao_enabled') #>> '{}')::boolean, true);

  -- Fases da corrida actual (nao-fila) a partir das quais o motorista ocupado
  -- conta para a sobreposicao. Interruptor desligado, raio 0 ou fila 0 ->
  -- nenhuma fase -> a prioridade 2 fica vazia (comportamento antigo).
  v_stages := CASE v_stage
    WHEN 'motorista_atribuido' THEN ARRAY['motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento']
    WHEN 'motorista_a_caminho' THEN ARRAY['motorista_a_caminho','motorista_chegou','em_andamento']
    WHEN 'motorista_chegou'    THEN ARRAY['motorista_chegou','em_andamento']
    ELSE ARRAY['em_andamento'] END;
  IF NOT v_b2b OR v_radius <= 0 OR v_maxq <= 0 THEN
    v_stages := ARRAY[]::text[];
  END IF;

  SELECT c.driver_uid, c.queued INTO v_driver, v_queued
  FROM (
    -- Prioridade 1: LIVRES, por distancia a recolha (o pool de sempre).
    SELECT d.user_id AS driver_uid, false AS queued, 1 AS prio,
           public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) AS dist_km,
           (SELECT max(r4.created_at) FROM public.tvde_rides r4
             WHERE r4.driver_id = d.user_id
               AND r4.status IN ('finalizada','em_andamento','motorista_chegou','motorista_a_caminho','motorista_atribuido')) AS last_ride_at
    FROM public.drivers d
    JOIN LATERAL (
      SELECT * FROM public.driver_locations l
      WHERE l.driver_id IN (d.user_id, d.id)
      ORDER BY l.last_updated DESC NULLS LAST
      LIMIT 1
    ) dl ON true
    WHERE d.vehicle_type = 'carro_passageiros'
      AND d.approval_status = 'approved'
      AND d.user_id IS NOT NULL
      AND (dl.is_online = true OR d.is_online = true)
      AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                   COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
          > now() - make_interval(secs => v_hb)
      -- 2026-09-23 (A10): online = heartbeat vivo E GPS fresco.
      AND COALESCE(dl.last_updated, '-infinity'::timestamptz) > now() - make_interval(secs => v_gps)
      AND dl.latitude IS NOT NULL AND dl.longitude IS NOT NULL
      AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
      AND NOT EXISTS (
        SELECT 1 FROM public.tvde_rides r2
        WHERE r2.driver_id = d.user_id
          AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.assigned_driver_id = d.id::text
          AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
      AND NOT public.tvde_driver_reservation_locked(d.user_id)

    UNION ALL

    -- Prioridade 2: OCUPADOS elegiveis para sobreposicao, por distancia
    -- destino-da-corrida-actual -> recolha-da-nova.
    SELECT d.user_id, true, 2,
           public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric),
           (SELECT max(r4.created_at) FROM public.tvde_rides r4
             WHERE r4.driver_id = d.user_id
               AND r4.status IN ('finalizada','em_andamento','motorista_chegou','motorista_a_caminho','motorista_atribuido'))
    FROM public.drivers d
    JOIN public.tvde_rides cur
      ON cur.driver_id = d.user_id
     AND cur.is_queued = false
     AND cur.status = ANY(v_stages)
    LEFT JOIN LATERAL (
      SELECT * FROM public.driver_locations l
      WHERE l.driver_id IN (d.user_id, d.id)
      ORDER BY l.last_updated DESC NULLS LAST
      LIMIT 1
    ) dl ON true
    WHERE d.vehicle_type = 'carro_passageiros'
      AND d.approval_status = 'approved'
      AND d.user_id IS NOT NULL
      AND (dl.is_online = true OR d.is_online = true)
      AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                   COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
          > now() - make_interval(secs => v_hb)
      -- 2026-09-23 (A10): online = heartbeat vivo E GPS fresco.
      AND COALESCE(dl.last_updated, '-infinity'::timestamptz) > now() - make_interval(secs => v_gps)
      AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
      AND (SELECT count(*) FROM public.tvde_rides r2
            WHERE r2.driver_id = d.user_id AND r2.is_queued = false
              AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) = 1
      AND (SELECT count(*) FROM public.tvde_rides r3
            WHERE r3.driver_id = d.user_id AND r3.is_queued = true
              AND r3.status = 'motorista_atribuido') < v_maxq
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.assigned_driver_id = d.id::text
          AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
      AND NOT public.tvde_driver_reservation_locked(d.user_id)
      AND public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                               v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) <= v_radius
  ) c
  ORDER BY c.prio ASC,
           CASE WHEN v_fila THEN c.last_ride_at END ASC NULLS FIRST,
           c.dist_km ASC
  LIMIT 1;

  IF v_driver IS NULL THEN
    IF v_ride.no_driver_since IS NOT NULL
       AND now() - v_ride.no_driver_since > make_interval(secs => v_window) THEN
      UPDATE public.tvde_rides
         SET status='sem_motorista', current_offer_driver_id=NULL,
             offer_expires_at=NULL, updated_at=now()
       WHERE id = p_ride_id;
      INSERT INTO public.tvde_ride_events(ride_id,status,actor)
        VALUES (p_ride_id,'sem_motorista','system');
      RETURN false;
    END IF;
    UPDATE public.tvde_rides
       SET no_driver_since = COALESCE(v_ride.no_driver_since, now()),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    RETURN false;
  END IF;

  UPDATE public.tvde_rides
     SET current_offer_driver_id = v_driver,
         offer_expires_at = now() + make_interval(secs => v_ttl),
         no_driver_since = NULL, updated_at = now()
   WHERE id = p_ride_id;
  INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
    VALUES (p_ride_id,'oferta','system',
            jsonb_build_object('driver_id', v_driver, 'expires_in_s', v_ttl,
                               'queued_candidate', v_queued, 'fila_justa', v_fila));
  RETURN true;
END; $function$;
