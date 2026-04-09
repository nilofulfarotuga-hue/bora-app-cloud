-- ============================================================
-- BORA APP — Dispatch Diagnostics
-- Run each block independently in the Supabase SQL Editor.
-- Work through them top-to-bottom to find the failure point.
-- ============================================================

-- ── 1. Is the trigger installed and enabled? ─────────────────
SELECT
  tgname        AS trigger_name,
  tgenabled     AS enabled,   -- 'O' = enabled, 'D' = disabled
  pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE tgrelid = 'public.orders'::regclass
  AND tgname = 'trg_dispatch_on_calling_driver';

-- Expected: one row, enabled = 'O'
-- If missing: run migration_trigger_dispatch.sql

-- ── 2. Is pg_net enabled and processing requests? ────────────
-- Shows the last 20 HTTP requests made by any trigger/function.
SELECT
  id,
  method,
  url,
  status_code,
  error_msg,
  created,
  left(response_body::text, 300) AS response_preview
FROM net._http_response
ORDER BY created DESC
LIMIT 20;

-- Expected: rows showing POST to /functions/v1/dispatch-engine
-- status_code = 200 means Edge Function ran successfully
-- status_code = 401 means the service role key in the trigger is wrong
-- status_code = 500 means Edge Function crashed (check function logs)
-- No rows at all: pg_net is not sending requests — see step 2b

-- ── 2b. Check pending (unsent) requests ──────────────────────
SELECT * FROM net.http_request_queue LIMIT 10;

-- If rows accumulate here but never appear in net._http_response,
-- the pg_net background worker is not running. Contact Supabase support
-- or toggle the extension off/on in Dashboard → Database → Extensions.

-- ── 3. Are there any online drivers? ────────────────────────
SELECT
  id,
  name,
  phone,
  vehicle_type,
  is_online,
  lat,
  lng
FROM public.drivers
ORDER BY is_online DESC;

-- Expected: at least one row with is_online = true
-- If is_online = false for all drivers:
--   The driver must toggle the Online switch in the app.
--   OR: run the fix below to set a driver online manually for testing.

-- ── 3b. Manually set a driver online for testing ─────────────
-- (Replace 'DRIVER_UUID_HERE' with a real driver id from step 3)
--
-- UPDATE public.drivers SET is_online = true WHERE id = 'DRIVER_UUID_HERE';

-- ── 4. Check recent callingDriver orders ─────────────────────
SELECT
  id,
  status,
  service_type,
  requires_car,
  current_driver_offer_id,
  driver_offer_expires_at,
  tried_driver_ids,
  assigned_driver_id,
  pickup_lat,
  pickup_lng,
  created_at
FROM public.orders
WHERE status = 'callingDriver'
ORDER BY created_at DESC
LIMIT 10;

-- Expected after working dispatch:
--   current_driver_offer_id = <driver uuid>
--   driver_offer_expires_at = some future timestamp

-- ── 5. Manually trigger dispatch for a stuck order ───────────
-- Use this to test the Edge Function directly without the trigger.
-- Replace values with real ones from step 4.
--
-- SELECT net.http_post(
--   url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
--   headers := '{"Content-Type":"application/json","Authorization":"Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
--   body    := '{"orderId":"PASTE_ORDER_ID_HERE"}'::jsonb
-- );
--
-- Then re-run step 4 to see if current_driver_offer_id was filled.
-- Check Edge Function logs at:
--   Dashboard → Edge Functions → dispatch-engine → Logs

-- ── 6. Verify driver coordinates vs order pickup ─────────────
-- Check if drivers are too far from a specific order's pickup.
-- Replace 'ORDER_ID_HERE' with a real order id.
--
-- WITH order_pos AS (
--   SELECT pickup_lat AS olat, pickup_lng AS olng
--   FROM orders WHERE id = 'ORDER_ID_HERE'
-- )
-- SELECT
--   d.id,
--   d.name,
--   d.is_online,
--   d.lat,
--   d.lng,
--   round(
--     6371 * 2 * asin(sqrt(
--       power(sin(radians((d.lat - o.olat) / 2)), 2) +
--       cos(radians(o.olat)) * cos(radians(d.lat)) *
--       power(sin(radians((d.lng - o.olng) / 2)), 2)
--     ))::numeric, 2
--   ) AS distance_km
-- FROM public.drivers d, order_pos o
-- ORDER BY distance_km;

-- ── 7. Check trigger function source ─────────────────────────
SELECT prosrc
FROM pg_proc
WHERE proname = 'fn_dispatch_on_calling_driver';

-- Check that the Bearer token does NOT still say YOUR_SERVICE_ROLE_KEY_HERE.
-- If it does, re-run migration_trigger_dispatch.sql with the real key.
