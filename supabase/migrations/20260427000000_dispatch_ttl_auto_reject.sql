-- =============================================================================
-- Migration: Dispatch TTL — auto-reject orders stuck >30min in callingDriver
-- =============================================================================
-- WHY: prevent orphaned orders from creating an infinite redispatch loop
--      (5 zombie orders from 2026-04-21..04-26 caused ~12 invocations/min
--      sustained, eventually triggering 503s on dispatch-engine).
--
-- HOW: bora_dispatch_maintenance() now runs Step 0 BEFORE the existing logic:
--      any order in callingDriver, unassigned, older than 30 minutes is
--      auto-rejected. This breaks the loop at the source.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_rejected_count int;
BEGIN
  -- Step 0: TTL — auto-reject orders stuck in callingDriver > 30 minutes.
  -- Prevents infinite redispatch loop on orphaned orders (no online drivers,
  -- missing pickup coords, etc.).
  WITH expired AS (
    UPDATE public.orders
    SET status                  = 'rejected',
        current_driver_offer_id = NULL,
        driver_offer_expires_at = NULL
    WHERE status            = 'callingDriver'
      AND assigned_driver_id IS NULL
      AND created_at < NOW() - INTERVAL '30 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_rejected_count FROM expired;

  IF v_rejected_count > 0 THEN
    RAISE NOTICE '[bora_dispatch_maintenance] auto-rejected % stale order(s)',
                 v_rejected_count;
  END IF;

  -- Step 1: Move expired offer driver into tried_driver_ids and clear offer fields.
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

  -- Step 2: Invoke dispatch engine for every order with no active offer.
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
