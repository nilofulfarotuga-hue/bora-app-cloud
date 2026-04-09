-- ============================================================
-- BORA APP — DB trigger: auto-dispatch when order → callingDriver
-- Run this in the Supabase SQL Editor.
--
-- Auth key used below: the project's ANON key (public — safe to embed).
-- The Edge Function uses its own SUPABASE_SERVICE_ROLE_KEY env-var for
-- DB access; the trigger only needs a valid JWT to call the function.
--
-- If you prefer the service role key for tighter security, replace the
-- Bearer value with the key from:
--   Dashboard → Project Settings → API → service_role (secret)
-- ============================================================

-- ── Step 1: pg_net ───────────────────────────────────────────
-- If not already enabled:
--   Dashboard → Database → Extensions → search "pg_net" → Enable
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── Step 2: Ensure all required columns exist ───────────────
-- Dispatch columns (backend-owned)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS current_driver_offer_id  TEXT,
  ADD COLUMN IF NOT EXISTS driver_offer_expires_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS tried_driver_ids         TEXT[]   NOT NULL DEFAULT '{}';

-- Flutter model columns that toSupabase() always sends
-- (missing from schema.sql causes every INSERT to fail with a 400)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS requires_car           BOOLEAN  NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_distance_estimated  BOOLEAN  NOT NULL DEFAULT FALSE;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE;

-- ── Step 3: Dispatch index ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_dispatch
  ON public.orders (status, current_driver_offer_id, driver_offer_expires_at)
  WHERE status = 'callingDriver';

-- ── Step 4: Trigger function ─────────────────────────────────
-- Uses the project anon key — a valid Supabase JWT that the Edge Function
-- runtime accepts. The function itself uses SUPABASE_SERVICE_ROLE_KEY from
-- its environment for all database operations.
CREATE OR REPLACE FUNCTION public.fn_dispatch_on_calling_driver()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Fire only when status transitions INTO 'callingDriver' with no driver yet
  IF NEW.status = 'callingDriver'
     AND NEW.assigned_driver_id IS NULL
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'callingDriver')
  THEN
    PERFORM net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"}'::jsonb,
      body    := jsonb_build_object('orderId', NEW.id::text)
    );

    RAISE LOG '[dispatch-trigger] Fired for order % (% → callingDriver)',
      NEW.id, COALESCE(OLD.status, 'INSERT');
  END IF;

  RETURN NEW;
END;
$$;

-- ── Step 5: Attach trigger ───────────────────────────────────
DROP TRIGGER IF EXISTS trg_dispatch_on_calling_driver ON public.orders;

CREATE TRIGGER trg_dispatch_on_calling_driver
  AFTER INSERT OR UPDATE OF status
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_dispatch_on_calling_driver();

-- ── Verify ───────────────────────────────────────────────────
-- SELECT tgname, tgenabled
-- FROM   pg_trigger
-- WHERE  tgrelid = 'public.orders'::regclass;

-- ── Check trigger is using correct key (not the old placeholder) ──
-- SELECT prosrc FROM pg_proc WHERE proname = 'fn_dispatch_on_calling_driver';
