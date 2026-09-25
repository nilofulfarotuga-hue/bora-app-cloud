-- ronda-fecho-2026-09-22 · A10 (b) — o espelho drivers -> driver_locations
-- renovava last_updated (a data da ÚLTIMA POSIÇÃO) sempre que só o is_online
-- mudava, sem posição nova. Isso mascarava o GPS parado: o relógio punha offline,
-- o espelho "renovava" o GPS, e o heartbeat voltava a ligar. Agora: só uma
-- posição nova (lat/lng diferente) renova last_updated; a mudança de is_online
-- espelha-se sem mexer na data.
-- Aplicada em produção a 2026-09-23 (versão 20260923130945).
CREATE OR REPLACE FUNCTION public.fn_sync_drivers_to_driver_locations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pos_nova boolean := (NEW.lat IS DISTINCT FROM OLD.lat) OR (NEW.lng IS DISTINCT FROM OLD.lng);
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;
  IF NOT v_pos_nova AND NEW.is_online IS NOT DISTINCT FROM OLD.is_online THEN
    RETURN NEW;
  END IF;
  IF v_pos_nova THEN
    INSERT INTO public.driver_locations (
      driver_id, latitude, longitude, is_online, last_updated
    ) VALUES (
      NEW.id,
      COALESCE(NEW.lat, 0),
      COALESCE(NEW.lng, 0),
      COALESCE(NEW.is_online, true),
      NOW()
    )
    ON CONFLICT (driver_id) DO UPDATE SET
      latitude = EXCLUDED.latitude,
      longitude = EXCLUDED.longitude,
      is_online = EXCLUDED.is_online,
      last_updated = NOW();
  ELSE
    -- 2026-09-23 (A10): só o estado mudou — espelha sem renovar a data do GPS.
    UPDATE public.driver_locations
       SET is_online = COALESCE(NEW.is_online, true)
     WHERE driver_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;
