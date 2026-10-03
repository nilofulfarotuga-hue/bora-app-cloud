-- 20260501000000_driver_location_sync.sql
-- Fase 1 — BUG 12 (sessão Danilo 2026-05-01)
--
-- Causa raiz: dispatch-engine lê drivers.lat/lng (legacy), mas:
--   • DriverLocationPingService só escreve em driver_locations (RPC driver_update_location)
--   • DriverStore.setOnline escreve só drivers.is_online (direct UPDATE)
--   • Resultado: drivers.lat/lng STALE (default Lisboa) → driver fora do raio Guarda
--                → não recebe oferta dispatch.
--
-- Fix em 2 partes:
--   1. RPC driver_update_location: escreve AMBAS as tabelas atomicamente.
--   2. Trigger AFTER UPDATE ON drivers: sincroniza driver_locations quando
--      o setOnline (ou outras escritas legacy) tocam drivers directamente.
--      Guard com pg_trigger_depth() = 1 para evitar loop infinito caso
--      um futuro trigger seja adicionado em driver_locations → drivers.

BEGIN;

-- ── 1. Estender RPC driver_update_location ───────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_update_location(
  p_latitude NUMERIC,
  p_longitude NUMERIC,
  p_heading NUMERIC DEFAULT NULL,
  p_speed_kmh NUMERIC DEFAULT NULL,
  p_is_online BOOLEAN DEFAULT TRUE
)
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

  -- A. UPSERT driver_locations (admin live map + future dispatch source).
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

  -- B. UPDATE drivers (legacy — dispatch-engine ainda lê daqui).
  --    BUG 12 fix: sem isto, dispatch nunca encontra driver real.
  UPDATE public.drivers
  SET lat = p_latitude,
      lng = p_longitude,
      is_online = COALESCE(p_is_online, is_online),
      updated_at = NOW()
  WHERE id = v_uid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.driver_update_location(numeric, numeric, numeric, numeric, boolean) TO authenticated;

-- ── 2. Trigger AFTER UPDATE ON drivers → sync driver_locations ────────────
-- Cobre o path legacy: DriverStore.setOnline / updateDriverLocation que
-- escrevem directamente em drivers, sem passar pela RPC.
-- Guard pg_trigger_depth()=1 impede loops se algum trigger futuro inverter.
CREATE OR REPLACE FUNCTION public.fn_sync_drivers_to_driver_locations()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  -- Só sync se vier de uma escrita directa em drivers (não de outro trigger).
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  -- Se nada relevante mudou, skip.
  IF NEW.lat IS NOT DISTINCT FROM OLD.lat
     AND NEW.lng IS NOT DISTINCT FROM OLD.lng
     AND NEW.is_online IS NOT DISTINCT FROM OLD.is_online THEN
    RETURN NEW;
  END IF;

  -- Cast id (TEXT em prod) → UUID; se falhar (id legacy não-UUID), skip silently.
  BEGIN
    INSERT INTO public.driver_locations (
      driver_id, latitude, longitude, is_online, last_updated
    ) VALUES (
      NEW.id::UUID,
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
  EXCEPTION
    WHEN invalid_text_representation THEN
      -- Driver id não é UUID válido (legacy). Não bloquear escrita em drivers.
      RAISE NOTICE 'fn_sync_drivers_to_driver_locations: skip non-UUID id=%', NEW.id;
  END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_drivers_to_driver_locations ON public.drivers;

CREATE TRIGGER trg_sync_drivers_to_driver_locations
AFTER UPDATE OF lat, lng, is_online ON public.drivers
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_drivers_to_driver_locations();

-- ── 3. Backfill: copy active drivers para driver_locations (one-shot) ────
-- Evita drivers online "invisíveis" no admin live map até próximo ping.
INSERT INTO public.driver_locations (
  driver_id, latitude, longitude, is_online, last_updated
)
SELECT id::UUID, lat, lng, is_online, NOW()
FROM public.drivers
WHERE is_online = true
  AND lat IS NOT NULL
  AND lng IS NOT NULL
  AND id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
ON CONFLICT (driver_id) DO UPDATE SET
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude,
  is_online = EXCLUDED.is_online,
  last_updated = NOW();

COMMIT;
