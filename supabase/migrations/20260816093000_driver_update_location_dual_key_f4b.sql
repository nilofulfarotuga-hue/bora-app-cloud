-- F4B: driver_update_location atualizava drivers WHERE id = auth.uid() -
-- conta com id<>user_id nunca via drivers.is_online/lat/lng atualizados.
-- Fix: WHERE user_id OR id + carimba last_heartbeat_at.
-- APLICADA em producao a 2026-08-16 (driver_update_location_dual_key_f4b_2026_08_16).

CREATE OR REPLACE FUNCTION public.driver_update_location(p_latitude numeric, p_longitude numeric, p_heading numeric DEFAULT NULL::numeric, p_speed_kmh numeric DEFAULT NULL::numeric, p_is_online boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'driver_required: not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'invalid_coords: latitude/longitude required' USING ERRCODE = '22023';
  END IF;
  IF p_latitude < -90 OR p_latitude > 90 OR p_longitude < -180 OR p_longitude > 180 THEN
    RAISE EXCEPTION 'invalid_coords: out of range' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.driver_locations (
    driver_id, latitude, longitude, heading, speed_kmh, is_online, last_updated
  ) VALUES (
    v_uid, p_latitude, p_longitude, p_heading, p_speed_kmh,
    COALESCE(p_is_online, true), NOW()
  )
  ON CONFLICT (driver_id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    heading = EXCLUDED.heading,
    speed_kmh = EXCLUDED.speed_kmh,
    is_online = EXCLUDED.is_online,
    last_updated = NOW();

  UPDATE public.drivers
  SET lat = p_latitude,
      lng = p_longitude,
      is_online = COALESCE(p_is_online, is_online),
      last_heartbeat_at = NOW(),
      updated_at = NOW()
  WHERE user_id = v_uid OR id = v_uid;
END;
$function$;
