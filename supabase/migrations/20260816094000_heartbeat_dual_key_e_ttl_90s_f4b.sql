-- F4B: heartbeat caia no vazio para contas id<>user_id + TTL honesto (90s,
-- ambas as tabelas). APLICADA em producao a 2026-08-16
-- (heartbeat_dual_key_e_ttl_90s_f4b_2026_08_16).

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

  UPDATE public.drivers
     SET last_heartbeat_at = v_now,
         is_online = true
   WHERE user_id = v_uid OR id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'driver_id', v_uid,
    'heartbeat_at', v_now
  );
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

  UPDATE public.drivers
     SET last_heartbeat_at = v_now,
         is_online         = true
   WHERE id = p_driver_id::uuid OR user_id = p_driver_id::uuid;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'heartbeat_at', v_now);
END;
$function$;

CREATE OR REPLACE FUNCTION public.expire_stale_driver_presence()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
  v_dl    integer;
BEGIN
  UPDATE public.drivers
     SET is_online = false
   WHERE is_online
     AND (last_heartbeat_at IS NULL
          OR last_heartbeat_at < now() - interval '90 seconds');
  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.driver_locations
     SET is_online = false
   WHERE is_online
     AND last_updated < now() - interval '90 seconds';
  GET DIAGNOSTICS v_dl = ROW_COUNT;

  RETURN v_count + v_dl;
END;
$function$;
