-- Missao redondo-total-2026-09-26, bloco B7 (a).
--
-- Regra do Danilo: SO o botao desliga o online. O GPS parado tira o motorista
-- das ofertas (dispatch_gps_fresh_seconds, lido pelo tvde_offer_to_next e pelo
-- driver_gps_fresh) mas nunca lhe desliga o botao.
--
-- Ate hoje expire_stale_driver_presence tinha um segundo bloco (A10, 23/09)
-- que punha drivers.is_online = false quando driver_gps_alive falhava, com o
-- prazo dispatch_gps_offline_seconds. Esse prazo foi posto em 604800 (7 dias)
-- a 23/09 so para o neutralizar. Para se poder repor 1800 sem desligar
-- ninguem, o bloco do GPS sai daqui: o GPS velho passa a marcar apenas
-- driver_locations.is_online = false (fica fora do matching; volta sozinho
-- no ping seguinte, que manda p_is_online = true).
--
-- O bloco do heartbeat fica como estava, governado por
-- dispatch_heartbeat_offline_seconds (hoje 604800, neutralizado a 25/09).
-- Nenhuma logica de ofertas mexida.

CREATE OR REPLACE FUNCTION public.expire_stale_driver_presence()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
  v_dl    integer;
  v_uid   text;
  v_uids  text[];
  v_off_secs int := COALESCE((public.get_setting('dispatch_gps_offline_seconds') #>> '{}')::int, 1800);
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

  -- GPS parado: so sai do matching (driver_locations), o botao nao muda.
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

  RETURN COALESCE(v_count, 0) + v_dl;
END;
$function$;
