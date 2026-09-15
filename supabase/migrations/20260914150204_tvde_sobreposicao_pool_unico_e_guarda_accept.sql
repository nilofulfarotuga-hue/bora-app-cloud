-- ============================================================================
-- TVDE — sobreposição de corridas (back-to-back, "igualzinho à Uber")
-- 2026-09-14 · missão tvde-sobreposicao-back-to-back · Bloco A.1
--
-- PORQUE EXISTE (caso real de hoje, lido de tvde_ride_events, hora de Lisboa):
--   15:19:43  Danilo (4f61dd31…, livre mas no PORTO) aceita a corrida 45bcad34
--   15:24:02  Danilo larga-a (motorista_desistiu, requeued=true)
--   15:24:41  a roda volta a oferecer ao PRÓPRIO Danilo
--   15:25:26  a oferta expira
--   15:26:03  a Claude.ai mete a corrida na fila do Valdemir À MÃO, por SQL
--   Ao mesmo tempo o Valdemir (e355fde0…) estava em 'motorista_a_caminho' na
--   corrida 497eb515, a 1,58 km da recolha largada — e NUNCA foi chamado.
--
-- Raiz, em tvde_offer_to_next:
--   (1) o pool principal exclui qualquer motorista com corrida activa;
--   (2) o ramo de fila só corre se o pool principal não achar NINGUÉM, e só
--       aceita corrida actual em 'em_andamento'.
-- E em tvde_accept_ride: o ramo de fila só existia para 'em_andamento' —
-- aceitar em 'motorista_a_caminho' deixava o motorista com DUAS activas.
--
-- O QUE MUDA (ordem do Danilo, 14/09: "copia e cola da Uber"):
--   • tvde_offer_to_next: UM pool só, ordenado. Prioridade 1 = livres, por
--     distância à recolha (o pool de sempre, sem regressão). Prioridade 2 =
--     ocupados elegíveis, por distância destino-da-corrida-actual → recolha
--     da nova. O ocupado entra na MESMA rotação: recusa/expira → tried → a
--     roda segue e pode voltar ao livre (o Danilo confirmou que está certo).
--     O evento 'oferta' continua a levar queued_candidate true/false — é por
--     aí que a app sabe que é sobreposição.
--   • Elegível para sobreposição = online com heartbeat vivo (ficar offline é
--     a forma da Uber de deixar de receber), EXACTAMENTE uma corrida activa
--     não-fila numa fase >= tvde_backtoback_min_stage, menos de
--     tvde_backtoback_max_queue corridas em fila, sem entrega activa, sem
--     reserva a travar (tvde_driver_reservation_locked), não tentado, e a
--     distância destino→recolha dentro de tvde_queue_pickup_radius_km.
--   • tvde_accept_ride: o ramo de fila dispara com QUALQUER corrida activa
--     não-fila (atribuido/a_caminho/chegou/em_andamento), respeita
--     tvde_backtoback_max_queue (queue_full) e tem guarda final que desfaz o
--     aceite se resultasse em duas activas (ride_conflict).
--   • tvde_cancel_ride: largar SÓ a corrida em fila deixa de promover outra
--     corrida da fila por cima da viagem em curso (guarda que faltava para
--     max_queue > 1 e para a reserva que o sweep põe em fila). A taxa de
--     cancelamento não é tocada — a alteração é feita por substituição
--     cirúrgica de texto sobre a definição viva, para o resto ficar igual.
--   • settings novas (categoria tvde, editáveis no painel admin):
--       tvde_backtoback_enabled    true
--       tvde_backtoback_max_queue  1
--       tvde_backtoback_min_stage  'motorista_a_caminho'
--     tvde_queue_pickup_radius_km sobe de 3 para 5 (a Guarda é pequena; a
--     3 km perde-se meia cidade).
--   • tvde_backtoback_enabled=false → comportamento EXACTAMENTE igual ao de
--     antes desta migration (a prioridade 2 fica vazia).
--
-- NÃO TOCA: tvde_finish_ride (já promove a fila — provado hoje às 15:35:13
-- com corrida real), dispatch-engine (entregas), kinds existentes da
-- notify-tvde-driver, funções de reserva (tvde_reservation_*).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Settings
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, category, description)
VALUES
  ('tvde_backtoback_enabled', 'true'::jsonb, 'tvde',
   'Sobreposição de corridas (back-to-back, à Uber): um motorista a meio de uma corrida também recebe ofertas e a nova fica em fila atrás da que ele leva. false = só motoristas livres recebem ofertas (comportamento antigo).'),
  ('tvde_backtoback_max_queue', '1'::jsonb, 'tvde',
   'Quantas corridas podem ficar em fila por motorista, atrás da que ele leva. 1 = uma de cada vez, como a Uber.'),
  ('tvde_backtoback_min_stage', '"motorista_a_caminho"'::jsonb, 'tvde',
   'Fase mínima da corrida actual para o motorista poder receber uma oferta em sobreposição: motorista_atribuido, motorista_a_caminho, motorista_chegou ou em_andamento.')
ON CONFLICT (key) DO NOTHING;

UPDATE public.platform_settings
   SET value = '5'::jsonb,
       description = 'Raio (km) entre o destino da corrida actual do motorista ocupado e a recolha da nova para ele entrar na roda (sobreposição). 0 desliga a sobreposição.',
       updated_at = now()
 WHERE key = 'tvde_queue_pickup_radius_km';

-- ---------------------------------------------------------------------------
-- 2) tvde_offer_to_next — pool único e ordenado
-- ---------------------------------------------------------------------------
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
  v_window INT := COALESCE((public.get_setting('tvde_retry_window_seconds') #>> '{}')::int, 120);
  v_b2b    BOOLEAN := COALESCE((public.get_setting('tvde_backtoback_enabled') #>> '{}')::boolean, true);
  v_maxq   INT := COALESCE((public.get_setting('tvde_backtoback_max_queue') #>> '{}')::int, 1);
  v_stage  TEXT := COALESCE(public.get_setting('tvde_backtoback_min_stage') #>> '{}', 'motorista_a_caminho');
  v_stages TEXT[];
  v_queued BOOLEAN := false;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  -- Fases da corrida actual (não-fila) a partir das quais o motorista ocupado
  -- conta para a sobreposição. Interruptor desligado, raio 0 ou fila 0 →
  -- nenhuma fase → a prioridade 2 fica vazia (comportamento antigo).
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
    -- Prioridade 1: LIVRES, por distância à recolha (o pool de sempre).
    SELECT d.user_id AS driver_uid, false AS queued, 1 AS prio,
           public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) AS dist_km
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

    -- Prioridade 2: OCUPADOS elegíveis para sobreposição, por distância
    -- destino-da-corrida-actual → recolha-da-nova.
    SELECT d.user_id, true, 2,
           public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric)
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
  ORDER BY c.prio ASC, c.dist_km ASC
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
            jsonb_build_object('driver_id', v_driver, 'expires_in_s', v_ttl, 'queued_candidate', v_queued));
  RETURN true;
END; $function$;

-- ---------------------------------------------------------------------------
-- 3) tvde_accept_ride — fila com qualquer corrida activa + guarda
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_accept_ride(p_ride_id uuid)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_pre public.tvde_rides;
  v_current UUID;
  v_maxq INT := COALESCE((public.get_setting('tvde_backtoback_max_queue') #>> '{}')::int, 1);
  v_nq INT; v_nactive INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_pre FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_pre.status <> 'solicitada' THEN RAISE EXCEPTION 'ride_not_available: %', v_pre.status; END IF;
  IF v_uid = ANY(v_pre.tried_driver_ids) THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;
  IF v_pre.current_offer_driver_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;

  -- Sobreposição (back-to-back): se o motorista já leva uma corrida — em
  -- QUALQUER fase, não só 'em_andamento' — a nova entra EM FILA. É isto que
  -- torna impossível ficar com duas corridas activas.
  SELECT r2.id INTO v_current FROM public.tvde_rides r2
   WHERE r2.driver_id = v_uid AND r2.is_queued = false
     AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
   ORDER BY CASE r2.status WHEN 'em_andamento' THEN 4 WHEN 'motorista_chegou' THEN 3
                           WHEN 'motorista_a_caminho' THEN 2 ELSE 1 END DESC,
            r2.updated_at DESC
   LIMIT 1;
  IF v_current IS NOT NULL THEN
    SELECT count(*) INTO v_nq FROM public.tvde_rides r3
     WHERE r3.driver_id = v_uid AND r3.is_queued = true
       AND r3.status = 'motorista_atribuido';
    IF v_nq >= GREATEST(v_maxq, 1) THEN RAISE EXCEPTION 'queue_full'; END IF;
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

  -- Guarda explícita: nunca duas corridas activas não-fila no mesmo
  -- motorista. Se acontecer (outra corrida a entrar por outro caminho no
  -- mesmo instante), a excepção desfaz o aceite inteiro.
  SELECT count(*) INTO v_nactive FROM public.tvde_rides r4
   WHERE r4.driver_id = v_uid AND r4.is_queued = false
     AND r4.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento');
  IF v_nactive > 1 THEN RAISE EXCEPTION 'ride_conflict'; END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_atribuido', 'driver');
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_a_caminho', 'driver');
  RETURN v_ride;
END; $function$;

-- ---------------------------------------------------------------------------
-- 4) tvde_cancel_ride — largar SÓ a corrida em fila não promove outra fila
--    por cima da viagem em curso. Substituição cirúrgica sobre a definição
--    viva (cada troca tem de bater exactamente uma vez, senão a migration
--    pára e nada muda). O resto da função fica byte a byte igual.
-- ---------------------------------------------------------------------------
DO $do$
DECLARE
  v_def text; v_new text; v_needle text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'tvde_cancel_ride'
     AND pg_get_function_identity_arguments(p.oid) = 'p_ride_id uuid, p_actor text, p_reason text';
  IF v_def IS NULL THEN RAISE EXCEPTION 'tvde_cancel_ride(uuid,text,text) não encontrada'; END IF;
  IF position('v_was_queued' IN v_def) > 0 THEN
    RAISE NOTICE 'tvde_cancel_ride: guarda da fila já aplicada — nada a fazer';
    RETURN;
  END IF;

  -- (a) variável nova
  v_needle := E'  v_had_driver BOOLEAN;\nBEGIN';
  v_n := (length(v_def) - length(replace(v_def, v_needle, ''))) / length(v_needle);
  IF v_n <> 1 THEN RAISE EXCEPTION 'tvde_cancel_ride: âncora (a) encontrada % vezes', v_n; END IF;
  v_new := replace(v_def, v_needle, E'  v_had_driver BOOLEAN;\n  v_was_queued BOOLEAN := false;\nBEGIN');

  -- (b) fotografar is_queued ANTES de a corrida largada mudar
  v_needle := E'    v_quit_driver := v_ride.driver_id;\n';
  v_n := (length(v_new) - length(replace(v_new, v_needle, ''))) / length(v_needle);
  IF v_n <> 1 THEN RAISE EXCEPTION 'tvde_cancel_ride: âncora (b) encontrada % vezes', v_n; END IF;
  v_new := replace(v_new, v_needle,
    E'    v_quit_driver := v_ride.driver_id;\n    v_was_queued := COALESCE(v_ride.is_queued, false);\n');

  -- (c) abrir a guarda antes da promoção da fila (só no ramo do motorista)
  v_needle := E'    UPDATE public.tvde_rides\n       SET is_queued = false, status = ''motorista_a_caminho'', updated_at = now()\n     WHERE id = (SELECT r3.id FROM public.tvde_rides r3\n                 WHERE r3.driver_id = v_quit_driver';
  v_n := (length(v_new) - length(replace(v_new, v_needle, ''))) / length(v_needle);
  IF v_n <> 1 THEN RAISE EXCEPTION 'tvde_cancel_ride: âncora (c) encontrada % vezes', v_n; END IF;
  v_new := replace(v_new, v_needle,
    E'    IF NOT v_was_queued THEN\n' || v_needle);

  -- (d) fechar a guarda depois do IF v_next desse ramo
  v_needle := E'''after_driver_giveup'', true));\n    END IF;\n';
  v_n := (length(v_new) - length(replace(v_new, v_needle, ''))) / length(v_needle);
  IF v_n <> 1 THEN RAISE EXCEPTION 'tvde_cancel_ride: âncora (d) encontrada % vezes', v_n; END IF;
  v_new := replace(v_new, v_needle, v_needle || E'    END IF;\n');

  EXECUTE v_new;
  RAISE NOTICE 'tvde_cancel_ride: guarda da fila aplicada';
END $do$;
