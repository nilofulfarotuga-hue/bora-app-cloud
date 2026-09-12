-- B1: driver_locations table + RLS for the admin live ops map.
-- Real-time GPS feed for the admin live ops map. Replaces the legacy fields
-- on `orders` (driver_lat/driver_lng) which were intentionally deprecated.
--
-- One row per driver. Updated by driver_update_location RPC (called every
-- ~10s by the driver app while online). Read by admin_live_drivers /
-- admin_live_orders.

CREATE TABLE IF NOT EXISTS public.driver_locations (
  driver_id uuid PRIMARY KEY,
  latitude numeric NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude numeric NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  heading numeric CHECK (heading IS NULL OR heading BETWEEN 0 AND 360),
  speed_kmh numeric CHECK (speed_kmh IS NULL OR speed_kmh >= 0),
  is_online boolean NOT NULL DEFAULT true,
  last_updated timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_driver_locations_online
  ON public.driver_locations (is_online, last_updated DESC);

CREATE INDEX IF NOT EXISTS idx_driver_locations_recent
  ON public.driver_locations (last_updated DESC) WHERE is_online = true;

ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "drivers_own_location_select" ON public.driver_locations;
CREATE POLICY "drivers_own_location_select"
  ON public.driver_locations FOR SELECT
  USING (driver_id = auth.uid());

DROP POLICY IF EXISTS "drivers_own_location_insert" ON public.driver_locations;
CREATE POLICY "drivers_own_location_insert"
  ON public.driver_locations FOR INSERT
  WITH CHECK (driver_id = auth.uid());

DROP POLICY IF EXISTS "drivers_own_location_update" ON public.driver_locations;
CREATE POLICY "drivers_own_location_update"
  ON public.driver_locations FOR UPDATE
  USING (driver_id = auth.uid())
  WITH CHECK (driver_id = auth.uid());

COMMENT ON TABLE public.driver_locations IS
  'Real-time GPS feed for admin live ops (B1). One row per driver, written by driver_update_location RPC.';

-- ── driver_update_location RPC ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_update_location(
  p_latitude numeric,
  p_longitude numeric,
  p_heading numeric DEFAULT NULL,
  p_speed_kmh numeric DEFAULT NULL,
  p_is_online boolean DEFAULT true
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    v_uid, p_latitude, p_longitude, p_heading, p_speed_kmh, COALESCE(p_is_online, true), NOW()
  )
  ON CONFLICT (driver_id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    heading = EXCLUDED.heading,
    speed_kmh = EXCLUDED.speed_kmh,
    is_online = EXCLUDED.is_online,
    last_updated = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_update_location(numeric, numeric, numeric, numeric, boolean) TO authenticated;
COMMENT ON FUNCTION public.driver_update_location IS
  'Driver app pings location (~10s). Upserts driver_locations for auth.uid().';

-- ── admin_live_orders RPC ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_live_orders()
RETURNS TABLE (
  id text,
  status text,
  service_type text,
  vendor_name text,
  customer_name text,
  total numeric,
  created_at timestamptz,
  pickup_lat numeric,
  pickup_lng numeric,
  dropoff_lat numeric,
  dropoff_lng numeric,
  pickup_address text,
  dropoff_address text,
  assigned_driver_id text,
  is_partner_store boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT
    o.id,
    o.status,
    o.service_type,
    o.vendor_name,
    o.customer_name,
    COALESCE(o.price, 0)::numeric,
    o.created_at,
    o.pickup_lat::numeric,
    o.pickup_lng::numeric,
    o.dropoff_lat::numeric,
    o.dropoff_lng::numeric,
    o.pickup_address,
    o.dropoff_address,
    o.assigned_driver_id,
    COALESCE(o.is_partner_store, false)
  FROM public.orders o
  WHERE o.status IN ('created', 'preparing', 'callingDriver',
                     'driverAccepted', 'pickedUp', 'onTheWay')
  ORDER BY o.created_at DESC
  LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_live_orders() TO authenticated;

-- ── admin_live_drivers RPC ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_live_drivers()
RETURNS TABLE (
  driver_id uuid,
  driver_name text,
  driver_phone text,
  latitude numeric,
  longitude numeric,
  heading numeric,
  speed_kmh numeric,
  last_updated timestamptz,
  active_order_id text,
  vehicle_type text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT
    dl.driver_id,
    d.full_name,
    d.phone,
    dl.latitude,
    dl.longitude,
    dl.heading,
    dl.speed_kmh,
    dl.last_updated,
    (SELECT o.id FROM public.orders o
       WHERE o.assigned_driver_id::text = dl.driver_id::text
         AND o.status IN ('driverAccepted','pickedUp','onTheWay')
       ORDER BY o.created_at DESC LIMIT 1) AS active_order_id,
    d.vehicle_type
  FROM public.driver_locations dl
  LEFT JOIN public.drivers d ON d.id = dl.driver_id
  WHERE dl.is_online = true
    AND dl.last_updated > NOW() - INTERVAL '5 minutes';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_live_drivers() TO authenticated;
