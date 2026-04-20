-- =============================================================================
-- Migration: Dispatch trigger + pg_cron + unstick stuck orders + user_id fix
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Enable pg_net (HTTP calls from DB triggers)
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- 2. DB trigger: invoke dispatch-engine when status → callingDriver
--    Fires on INSERT (old.status = NULL) and on UPDATE to callingDriver.
--    Uses the public anon key — the edge function handles its own service key.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_dispatch_on_calling_driver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'callingDriver'
    AND (OLD.status IS DISTINCT FROM 'callingDriver')
    AND NEW.assigned_driver_id IS NULL
  THEN
    PERFORM extensions.net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"}'::jsonb,
      body    := jsonb_build_object('orderId', NEW.id::text)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_dispatch_on_calling_driver ON public.orders;
CREATE TRIGGER trigger_dispatch_on_calling_driver
  AFTER INSERT OR UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_dispatch_on_calling_driver();

-- ---------------------------------------------------------------------------
-- 3. Maintenance function: clean expired offers + re-invoke dispatch for
--    orphaned orders (self-scheduling chain died or was never started).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
BEGIN
  -- Step 1: Move expired offer driver into tried_driver_ids and clear offer fields.
  -- This unblocks processDispatch on the next invocation.
  UPDATE public.orders
  SET
    tried_driver_ids        = array_append(
                                COALESCE(tried_driver_ids, '{}'::uuid[]),
                                current_driver_offer_id::uuid
                              ),
    current_driver_offer_id = NULL,
    driver_offer_expires_at = NULL
  WHERE status            = 'callingDriver'
    AND assigned_driver_id IS NULL
    AND current_driver_offer_id IS NOT NULL
    AND driver_offer_expires_at IS NOT NULL
    AND driver_offer_expires_at < NOW();

  -- Step 2: Invoke dispatch engine for every order that has no active offer.
  -- Covers: offer just cleared above + orders stuck with offer_expires_at = NULL.
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status            = 'callingDriver'
      AND assigned_driver_id IS NULL
      AND current_driver_offer_id IS NULL
  LOOP
    PERFORM extensions.net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"}'::jsonb,
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. pg_cron: run maintenance every 2 minutes as a safety net.
--    Handles cases where the self-scheduling chain in the edge function dies.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('bora-dispatch-maintenance');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'bora-dispatch-maintenance',
  '*/2 * * * *',
  'SELECT public.bora_dispatch_maintenance()'
);

-- ---------------------------------------------------------------------------
-- 5. One-time: unstick the 8 orders currently stuck in callingDriver
--    with driver_offer_expires_at = NULL and no assigned driver.
--    Calling the maintenance function immediately invokes the edge function
--    for each of them.
-- ---------------------------------------------------------------------------
SELECT public.bora_dispatch_maintenance();

-- ---------------------------------------------------------------------------
-- 6. user_id column: ensure drivers.user_id mirrors drivers.id
--    (the id column already stores the Supabase auth UUID, but some rows
--    have a separate user_id column that was left NULL by older upserts).
-- ---------------------------------------------------------------------------
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill: set user_id = id for all drivers whose id is a valid auth user.
UPDATE public.drivers d
SET user_id = d.id::uuid
WHERE d.user_id IS NULL
  AND d.id IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.id::uuid);
