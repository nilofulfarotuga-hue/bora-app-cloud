-- ============================================================================
-- BORA — Fix bora_dispatch_maintenance type mismatch (FASE 5 · BUG 5)
-- ============================================================================
-- BUG: Step 1 of bora_dispatch_maintenance() failed every cron run since
--      2026-04-27 11:00 UTC with:
--        ERROR: COALESCE could not convert type uuid[] to text[]
--
-- ROOT CAUSE: Migration 20260427000000_dispatch_ttl_auto_reject.sql redefined
--             this function assuming `tried_driver_ids` was uuid[] and
--             `current_driver_offer_id` was uuid. Both are actually TEXT
--             (legacy schema, same family as orders.id and assigned_driver_id).
--
--             1526 failed runs in 7 days. Step 1 (clear expired offers) and
--             Step 2 (re-invoke dispatch) never ran. Steps -1 (auto-cancel
--             abandoned payment) and 0 (TTL 30min auto-reject) ran fine
--             because they're before Step 1.
--
-- FIX (surgical, 2 expressions):
--   1. COALESCE fallback: '{}'::uuid[]  →  '{}'::text[]
--   2. Remove ::uuid cast on current_driver_offer_id (already text, no cast needed)
--
-- No schema change. dispatch-engine Edge Function reads tried_driver_ids as
-- string[] (TypeScript), so text[] is the correct ongoing type.
--
-- Tech-debt logged for post-launch:
--   - Consolidate types (tried_driver_ids → uuid[] OR keep text[] everywhere)
--   - Historical migration 20260415140000 has the same latent bug (no longer
--     active because 20260427 overrode it; doesn't need fixing in source)
--
-- Investigation: .claude/.ai/reports/2026-04-29-fase5-bug5-investigation.md
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_rejected_count int;
  v_cancelled_count int;
BEGIN
  -- Step -1: Auto-cancel unpaid card/mbway orders older than 10 minutes.
  -- These are abandoned checkouts (Stripe never confirmed nor failed).
  WITH abandoned AS (
    UPDATE public.orders
    SET status         = 'cancelled',
        payment_status = 'failed',
        cancel_reason  = 'payment_abandoned'
    WHERE status              = 'created'
      AND payment_status      = 'pending'
      AND payment_method      IN ('card', 'mbway')
      AND created_at          < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;

  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[bora_dispatch_maintenance] auto-cancelled % abandoned payment(s)',
                 v_cancelled_count;
  END IF;

  -- Step 0: TTL — auto-reject orders stuck in callingDriver > 30 minutes.
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
  -- ⚠️ FIX FASE 5 BUG 5: tried_driver_ids and current_driver_offer_id are TEXT,
  -- not UUID. Use text[] in COALESCE and drop the ::uuid cast.
  UPDATE public.orders
  SET
    tried_driver_ids        = array_append(
                                COALESCE(tried_driver_ids, '{}'::text[]),  -- was '{}'::uuid[]
                                current_driver_offer_id                    -- was current_driver_offer_id::uuid
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
