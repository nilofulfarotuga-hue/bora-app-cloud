-- ============================================================================
-- BORA — Auto Ledger Settlement
-- 1. Recompute snapshot on every ledger INSERT
-- 2. auto_payout_pending() — batch payout all users with balance >= threshold
-- 3. pg_cron weekly job (skipped if extension absent)
-- ============================================================================

BEGIN;

-- ─── 1. Auto-recompute snapshot after each ledger INSERT ─────────────────────
CREATE OR REPLACE FUNCTION public.ledger_after_insert_recompute()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.user_type = 'platform' THEN RETURN NEW; END IF;
  PERFORM public.recompute_user_balance(NEW.user_id, NEW.user_type);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ledger_recompute_on_insert ON public.ledger_entries;
CREATE TRIGGER ledger_recompute_on_insert
  AFTER INSERT ON public.ledger_entries
  FOR EACH ROW EXECUTE FUNCTION public.ledger_after_insert_recompute();

COMMENT ON FUNCTION public.ledger_after_insert_recompute() IS
  'Keeps user_balance_snapshots current after each ledger INSERT. Skips platform rows.';

-- ─── 2. Batch auto-payout function ───────────────────────────────────────────
-- Safe to call repeatedly: create_payout() is atomic and ledger is idempotent.
CREATE OR REPLACE FUNCTION public.auto_payout_pending(
  p_min_balance NUMERIC DEFAULT 10.0
) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r           RECORD;
  v_balance   NUMERIC(12, 2);
  v_count     INT := 0;
BEGIN
  IF p_min_balance <= 0 THEN
    RAISE EXCEPTION 'auto_payout_pending: p_min_balance must be > 0';
  END IF;

  FOR r IN
    SELECT user_id, user_type
    FROM public.user_balance_snapshots
    WHERE user_type IN ('driver', 'restaurant')
      AND balance >= p_min_balance
  LOOP
    -- Re-verify from ledger (snapshot is a cache, not source of truth)
    SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      INTO v_balance
    FROM public.ledger_entries
    WHERE user_id = r.user_id AND user_type = r.user_type;

    IF v_balance >= p_min_balance THEN
      PERFORM public.create_payout(r.user_id, r.user_type, v_balance);
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'auto_payout_pending: % payout(s) created (threshold=€%)', v_count, p_min_balance;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.auto_payout_pending(NUMERIC) IS
  'Batch-creates payouts for every user whose confirmed ledger balance >= p_min_balance. Verifies from ledger before acting. Default threshold €10. Safe to call repeatedly.';

GRANT EXECUTE ON FUNCTION public.auto_payout_pending(NUMERIC) TO service_role;
REVOKE EXECUTE ON FUNCTION public.auto_payout_pending(NUMERIC) FROM public, anon, authenticated;

-- ─── 3. pg_cron weekly job (no-op if extension not installed) ────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'bora_weekly_auto_payout',
      '0 3 * * 1',  -- Every Monday 03:00 UTC
      $$SELECT public.auto_payout_pending(10.0)$$
    );
    RAISE NOTICE 'pg_cron job bora_weekly_auto_payout scheduled (Mondays 03:00 UTC)';
  ELSE
    RAISE NOTICE 'pg_cron not installed — call auto_payout_pending() manually or via Edge Function';
  END IF;
END;
$$;

COMMIT;
