-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item E: retry-window no dispatch (rotação/recusa, densidade baixa).
--
-- Problema de campo (Guarda, 1 motorista): quando a pool elegível esgota (o
-- único motorista recusou/expirou, ou está ocupado), a corrida ia DIRETO a
-- 'sem_motorista'. Numa cidade pequena isso mata a corrida antes de um motorista
-- ficar livre/online.
--
-- Correção CIRÚRGICA (motor de matching INTACTO — Tier1/Tier2 idênticos):
--   • nova coluna aditiva tvde_rides.no_driver_since + setting
--     tvde_retry_window_seconds (default 120s);
--   • em tvde_offer_to_next, o bloco "v_driver IS NULL" deixa de marcar
--     'sem_motorista' já: mantém 'solicitada' e regista no_driver_since. Só
--     desiste quando a janela esgota. Ao ENCONTRAR motorista, limpa o relógio;
--   • tvde_dispatch_sweep ganha um 2.º loop que re-tenta as corridas à espera
--     (o cron de 15s dá o backoff).
--
-- Respeita 'tried_driver_ids': quem recusou/expirou continua excluído desta
-- corrida — a janela serve para APANHAR um motorista que fique livre/online,
-- não para re-oferecer a quem já disse não.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS no_driver_since TIMESTAMPTZ;

COMMENT ON COLUMN public.tvde_rides.no_driver_since IS
  '[Item E] Início da janela de retry (sem motorista elegível). NULL = há/houve oferta. Limpo ao oferecer; após tvde_retry_window_seconds → sem_motorista.';

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_retry_window_seconds', '120',
        'TVDE: janela (s) a insistir à procura de motorista antes de sem_motorista', 'tvde')
ON CONFLICT (key) DO NOTHING;

-- ── tvde_offer_to_next: motor idêntico, cauda com retry-window ───────────────
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
  v_queued BOOLEAN := false;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  -- TIER 1 - motoristas LIVRES online (comportamento atual, intacto)
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
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.assigned_driver_id = d.id::text
        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
  ORDER BY public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
  LIMIT 1;

  -- TIER 2 - back-to-back: so se NENHUM livre
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

  -- [Item E] Sem motorista elegível → NÃO desiste já: janela de retry.
  IF v_driver IS NULL THEN
    IF v_ride.no_driver_since IS NOT NULL
       AND now() - v_ride.no_driver_since > make_interval(secs => v_window) THEN
      -- Janela esgotada → agora sim, sem_motorista (comportamento antigo).
      UPDATE public.tvde_rides
         SET status='sem_motorista', current_offer_driver_id=NULL,
             offer_expires_at=NULL, updated_at=now()
       WHERE id = p_ride_id;
      INSERT INTO public.tvde_ride_events(ride_id,status,actor)
        VALUES (p_ride_id,'sem_motorista','system');
      RETURN false;
    END IF;
    -- Primeira falha ou ainda dentro da janela: fica à procura.
    UPDATE public.tvde_rides
       SET no_driver_since = COALESCE(v_ride.no_driver_since, now()),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    RETURN false;
  END IF;

  -- Encontrou motorista → oferta + limpa o relógio de retry.
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

-- ── tvde_dispatch_sweep: loop 1 (expiração, intacto) + loop 2 (retry) ────────
CREATE OR REPLACE FUNCTION public.tvde_dispatch_sweep()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  -- LOOP 1 (intacto): ofertas ativas que expiraram → rotação.
  FOR r IN
    SELECT id, current_offer_driver_id FROM public.tvde_rides
    WHERE status='solicitada' AND offer_expires_at IS NOT NULL AND offer_expires_at < now()
      AND current_offer_driver_id IS NOT NULL
  LOOP
    UPDATE public.tvde_rides
       SET tried_driver_ids = array_append(tried_driver_ids, r.current_offer_driver_id),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = r.id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
      VALUES (r.id,'oferta_expirada','system', jsonb_build_object('driver_id', r.current_offer_driver_id));
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;

  -- [Item E] LOOP 2: corridas à espera (retry-window ativo, sem oferta) →
  -- re-tenta a cada passagem do cron (15s). tvde_offer_to_next decide se ainda
  -- insiste ou marca sem_motorista quando a janela esgota.
  FOR r IN
    SELECT id FROM public.tvde_rides
    WHERE status='solicitada' AND current_offer_driver_id IS NULL
      AND no_driver_since IS NOT NULL
  LOOP
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;
END; $function$;
