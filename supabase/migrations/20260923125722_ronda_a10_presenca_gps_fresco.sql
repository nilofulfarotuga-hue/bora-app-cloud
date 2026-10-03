-- =============================================================================
-- ronda-fecho-2026-09-22 · A10 — despacho: online = heartbeat vivo E GPS fresco
--
-- Caso vivo a 23/09 12:40Z: Euliney Fernandes online com heartbeat de 3 s (o
-- serviço em segundo plano continua a bater) e última posição GPS há 19 horas —
-- a app morreu, mas continuava a receber ofertas que não podia aceitar.
--
-- Duas chaves (categoria dispatch, editáveis no painel):
--   · dispatch_gps_fresh_seconds = 180 — posição mais velha do que isto NÃO
--     recebe oferta: tvde_offer_to_next (migração 20260923124627),
--     _driver_reachability.online_agora (pré-atribuição e "Escolher estafeta"),
--     admin_drivers_for_assignment / admin_driver_presence (gps_age_s).
--   · dispatch_gps_offline_seconds = 1800 — o relógio expire_stale_driver_presence
--     (agora todos os minutos) põe is_online=false quando o GPS está parado há
--     mais do que isto, com aviso ao estafeta; os heartbeats (driver_heartbeat,
--     driver_heartbeat(p_platform), driver_heartbeat_by_id do serviço em segundo
--     plano) deixam de voltar a pôr online quem passou este limite — só o ping de
--     posição (driver_update_location) ou a própria app o fazem. É o que gate o
--     motor de entregas (Edge dispatch-engine v61, que filtra por is_online e
--     NÃO se redeploya: o repo tem a v58).
--     Começa a 30 min de propósito: a app publicada hoje só manda posição quando
--     o estafeta se mexe (filtro de 50 m), por isso um estafeta parado ficaria
--     offline aos 3 min. A build deste push (heartbeat_service.dart) passa a
--     mandar a posição de 30 em 30 s mesmo parado; quando estiver nos telemóveis,
--     baixa-se esta chave para 180 no painel (Configurações › dispatch).
-- =============================================================================

INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('dispatch_gps_fresh_seconds', '180'::jsonb,
   'Despacho (entregas e TVDE): motorista/estafeta cuja última posição GPS tem mais do que estes segundos não recebe oferta. Online = heartbeat vivo E GPS fresco.',
   'dispatch'),
  ('dispatch_gps_offline_seconds', '1800'::jsonb,
   'Relógio de presença: estafeta com o GPS parado há mais do que estes segundos é posto offline (com aviso) e o heartbeat não o volta a ligar. Baixar para 180 quando a app com o ping de posição de 30 s (build ≥ 618, 23/09/2026) estiver nos telemóveis.',
   'dispatch')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.driver_gps_last_at(p_user_id uuid, p_driver_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT max(l.last_updated) FROM public.driver_locations l
   WHERE l.driver_id IN (p_user_id, p_driver_id);
$function$;

CREATE OR REPLACE FUNCTION public.driver_gps_age_seconds(p_user_id uuid, p_driver_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT extract(epoch FROM (now() - public.driver_gps_last_at(p_user_id, p_driver_id)))::int;
$function$;

-- fresco = recebe oferta (180 s)
CREATE OR REPLACE FUNCTION public.driver_gps_fresh(p_user_id uuid, p_driver_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    public.driver_gps_last_at(p_user_id, p_driver_id)
      > now() - make_interval(secs => COALESCE((public.get_setting('dispatch_gps_fresh_seconds') #>> '{}')::int, 180)),
    false);
$function$;

-- vivo = continua online (1800 s por agora; ver cabeçalho)
CREATE OR REPLACE FUNCTION public.driver_gps_alive(p_user_id uuid, p_driver_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    public.driver_gps_last_at(p_user_id, p_driver_id)
      > now() - make_interval(secs => COALESCE((public.get_setting('dispatch_gps_offline_seconds') #>> '{}')::int, 1800)),
    false);
$function$;

-- ── relógio de presença: heartbeat (90 s) OU GPS parado ─────────────────────
CREATE OR REPLACE FUNCTION public.expire_stale_driver_presence()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
  v_gps_count integer;
  v_dl    integer;
  v_uid   text;
  v_uids  text[];
  v_gps   text[];
  v_off_secs int := COALESCE((public.get_setting('dispatch_gps_offline_seconds') #>> '{}')::int, 1800);
BEGIN
  WITH off AS (
    UPDATE public.drivers
       SET is_online = false
     WHERE is_online
       AND (last_heartbeat_at IS NULL
            OR last_heartbeat_at < now() - interval '90 seconds')
    RETURNING COALESCE(user_id, id)::text AS uid
  )
  SELECT count(*), array_agg(uid) INTO v_count, v_uids FROM off;

  -- 2026-09-23 (A10): heartbeat vivo mas GPS parado = não está mesmo online.
  WITH off_gps AS (
    UPDATE public.drivers d
       SET is_online = false
     WHERE d.is_online
       AND NOT public.driver_gps_alive(d.user_id, d.id)
    RETURNING COALESCE(d.user_id, d.id)::text AS uid,
              COALESCE(public.driver_gps_age_seconds(d.user_id, d.id), -1) AS idade
  )
  SELECT count(*), array_agg(uid || '|' || idade) INTO v_gps_count, v_gps FROM off_gps;

  UPDATE public.driver_locations
     SET is_online = false
   WHERE is_online
     AND last_updated < now() - make_interval(secs => GREATEST(90, v_off_secs));
  GET DIAGNOSTICS v_dl = ROW_COUNT;

  IF v_uids IS NOT NULL THEN
    FOREACH v_uid IN ARRAY v_uids LOOP
      PERFORM public._notify_driver_assigned_http(
        v_uid, NULL, 'driver_offline',
        'Ficaste desligado',
        'Ficaste desligado. Abre a Bora para voltares a receber pedidos.');
    END LOOP;
  END IF;

  IF v_gps IS NOT NULL THEN
    FOREACH v_uid IN ARRAY v_gps LOOP
      PERFORM public._notify_driver_assigned_http(
        split_part(v_uid, '|', 1), NULL, 'driver_offline',
        'Sem sinal de GPS',
        CASE WHEN split_part(v_uid, '|', 2)::int < 0
             THEN 'Ficaste desligado: a Bora não recebe a tua localização. Liga o GPS e abre a Bora para voltares a receber pedidos.'
             ELSE 'Ficaste desligado: a tua localização parou há ' || GREATEST(1, split_part(v_uid, '|', 2)::int / 60) || ' min. Abre a Bora (e atualiza a app) para voltares a receber pedidos.' END);
    END LOOP;
  END IF;

  RETURN COALESCE(v_count, 0) + COALESCE(v_gps_count, 0) + v_dl;
END;
$function$;

-- todos os minutos (era */5)
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'drivers-heartbeat-expire';
SELECT cron.schedule('drivers-heartbeat-expire', '* * * * *', 'SELECT public.expire_stale_driver_presence();');

-- ── heartbeats: não voltam a pôr online quem passou o limite de GPS ─────────
CREATE OR REPLACE FUNCTION public.driver_heartbeat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         -- 2026-09-23 (A10): só volta a online se o GPS ainda estiver vivo.
         is_online = CASE WHEN public.driver_gps_alive(d.user_id, d.id) THEN true ELSE d.is_online END
   WHERE d.user_id = v_uid OR d.id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'driver_id', v_uid,
    'heartbeat_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.driver_heartbeat(p_platform text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
  v_plat text := lower(btrim(coalesce(p_platform, '')));
  v_gps boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  IF v_plat NOT IN ('android_app','ios_app','web_ios','web_android','web_desktop') THEN
    v_plat := NULL;
  END IF;

  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         -- 2026-09-23 (A10): só volta a online se o GPS ainda estiver vivo.
         is_online = CASE WHEN public.driver_gps_alive(d.user_id, d.id) THEN true ELSE d.is_online END,
         last_platform    = COALESCE(v_plat, last_platform),
         last_platform_at = CASE WHEN v_plat IS NULL THEN last_platform_at ELSE v_now END
   WHERE d.user_id = v_uid OR d.id = v_uid;

  SELECT public.driver_gps_fresh(d.user_id, d.id) INTO v_gps
    FROM public.drivers d WHERE d.user_id = v_uid OR d.id = v_uid LIMIT 1;
  RETURN jsonb_build_object('success', true, 'driver_id', v_uid, 'heartbeat_at', v_now, 'platform', v_plat,
                            'gps_fresco', COALESCE(v_gps, false));
END;
$function$;

CREATE OR REPLACE FUNCTION public.driver_heartbeat_by_id(p_driver_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now     timestamptz := now();
  v_updated int;
BEGIN
  IF p_driver_id IS NULL OR length(trim(p_driver_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_id_required');
  END IF;

  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         -- 2026-09-23 (A10): o serviço em segundo plano só volta a pôr online com o GPS vivo.
         is_online         = CASE WHEN public.driver_gps_alive(d.user_id, d.id) THEN true ELSE d.is_online END,
         last_platform     = 'android_app',
         last_platform_at  = v_now
   WHERE d.id = p_driver_id::uuid OR d.user_id = p_driver_id::uuid;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'heartbeat_at', v_now);
END;
$function$;

-- ── quem "vai receber": heartbeat E GPS fresco ──────────────────────────────
CREATE OR REPLACE FUNCTION public._driver_reachability(p_driver text)
 RETURNS TABLE(driver_id uuid, user_id uuid, name text, approval_status text, is_banned boolean, online_agora boolean, tem_notificacoes boolean, last_heartbeat_at timestamp with time zone, last_platform text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select d.id, d.user_id, d.name, d.approval_status, coalesce(d.is_banned, false),
         coalesce(d.is_online, false)
           and d.last_heartbeat_at is not null
           and d.last_heartbeat_at > now() - interval '90 seconds'
           and public.driver_gps_fresh(d.user_id, d.id),
         d.fcm_token is not null
           or exists (select 1 from public.driver_push_tokens t
                       where t.user_id::text = coalesce(d.user_id, d.id)::text and t.active)
           or exists (select 1 from public.provider_push_tokens t
                       where t.user_id::text = coalesce(d.user_id, d.id)::text
                         and t.role = 'driver' and t.active),
         d.last_heartbeat_at, d.last_platform
  from public.drivers d
  where d.user_id::text = p_driver or d.id::text = p_driver
  limit 1;
$function$;

-- ── painel: gps_age_s nas duas RPCs do "Escolher estafeta" ──────────────────
DROP FUNCTION IF EXISTS public.admin_drivers_for_assignment(text, text);
CREATE OR REPLACE FUNCTION public.admin_drivers_for_assignment(p_order_id text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS TABLE(user_id text, driver_id uuid, name text, phone text, photo_url text, vehicle_type text, is_online boolean, online_agora boolean, last_heartbeat_at timestamp with time zone, tem_notificacoes boolean, last_platform text, pedidos_em_curso integer, distancia_km numeric, gps_age_s integer, gps_fresco boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lat double precision;
  v_lng double precision;
BEGIN
  PERFORM public._admin_op_guard();

  IF p_order_id IS NOT NULL THEN
    SELECT o.pickup_lat, o.pickup_lng INTO v_lat, v_lng FROM orders o WHERE o.id = p_order_id;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(d.user_id, d.id)::text,
    d.id,
    d.name,
    d.phone,
    d.photo_url,
    d.vehicle_type,
    COALESCE(d.is_online, false),
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at IS NOT NULL
       AND d.last_heartbeat_at > now() - interval '90 seconds'
       AND public.driver_gps_fresh(d.user_id, d.id)),
    d.last_heartbeat_at,
    (d.fcm_token IS NOT NULL
       OR EXISTS (SELECT 1 FROM driver_push_tokens t
                   WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    d.last_platform,
    (SELECT count(*)::int FROM orders o2
      WHERE o2.assigned_driver_id = COALESCE(d.user_id, d.id)::text
        AND o2.status IN ('driverAccepted', 'pickedUp', 'onTheWay')),
    CASE WHEN v_lat IS NULL THEN NULL
         ELSE round(public._haversine_km(v_lat, v_lng, d.lat, d.lng)::numeric, 1) END,
    public.driver_gps_age_seconds(d.user_id, d.id),
    public.driver_gps_fresh(d.user_id, d.id)
  FROM drivers d
  WHERE d.approval_status = 'approved'
    AND COALESCE(d.is_banned, false) = false
    AND d.deleted_at IS NULL
    AND (p_search IS NULL OR btrim(p_search) = ''
         OR d.name ILIKE '%' || btrim(p_search) || '%'
         OR d.phone ILIKE '%' || btrim(p_search) || '%')
  ORDER BY
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at > now() - interval '90 seconds'
       AND public.driver_gps_fresh(d.user_id, d.id)) DESC,
    CASE WHEN v_lat IS NULL THEN NULL ELSE public._haversine_km(v_lat, v_lng, d.lat, d.lng) END ASC NULLS LAST,
    d.last_heartbeat_at DESC NULLS LAST,
    d.name;
END $function$;
REVOKE ALL ON FUNCTION public.admin_drivers_for_assignment(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_drivers_for_assignment(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_drivers_for_assignment(text, text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_driver_presence(text);
CREATE OR REPLACE FUNCTION public.admin_driver_presence(p_driver text)
 RETURNS TABLE(user_id text, driver_id uuid, name text, is_online boolean, online_agora boolean, last_heartbeat_at timestamp with time zone, tem_notificacoes boolean, tokens_ativos integer, last_platform text, last_platform_at timestamp with time zone, pedidos_em_curso integer, gps_age_s integer, gps_fresco boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT
    COALESCE(d.user_id, d.id)::text, d.id, d.name,
    COALESCE(d.is_online, false),
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at IS NOT NULL
       AND d.last_heartbeat_at > now() - interval '90 seconds'
       AND public.driver_gps_fresh(d.user_id, d.id)),
    d.last_heartbeat_at,
    (d.fcm_token IS NOT NULL
       OR EXISTS (SELECT 1 FROM driver_push_tokens t
                   WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    ((CASE WHEN d.fcm_token IS NOT NULL THEN 1 ELSE 0 END)
       + (SELECT count(*)::int FROM driver_push_tokens t
           WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    d.last_platform, d.last_platform_at,
    (SELECT count(*)::int FROM orders o2
      WHERE o2.assigned_driver_id = COALESCE(d.user_id, d.id)::text
        AND o2.status IN ('driverAccepted', 'pickedUp', 'onTheWay')),
    public.driver_gps_age_seconds(d.user_id, d.id),
    public.driver_gps_fresh(d.user_id, d.id)
  FROM drivers d
  WHERE d.user_id::text = p_driver OR d.id::text = p_driver
  LIMIT 1;
END $function$;
REVOKE ALL ON FUNCTION public.admin_driver_presence(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_driver_presence(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_driver_presence(text) TO authenticated, service_role;
