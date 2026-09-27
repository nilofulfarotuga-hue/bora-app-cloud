-- Copia da funcao NO AR antes da migration 20260927190000 (lida por
-- pg_get_functiondef a 27/09/2026 ~19:30 Lisboa). Rollback = correr isto.
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
  -- 2026-09-25: mesmo tratamento do GPS -- definicao propria, neutralizada.
  v_hb_off_secs int := COALESCE((public.get_setting('dispatch_heartbeat_offline_seconds') #>> '{}')::int, 90);
BEGIN
  WITH off AS (
    UPDATE public.drivers
       SET is_online = false
     WHERE is_online
       AND (last_heartbeat_at IS NULL
            OR last_heartbeat_at < now() - make_interval(secs => v_hb_off_secs))
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
