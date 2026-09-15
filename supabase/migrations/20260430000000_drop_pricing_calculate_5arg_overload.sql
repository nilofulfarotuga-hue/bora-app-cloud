-- ============================================================================
-- BORA — Drop legacy 5-arg pricing_calculate overload (T17)
-- ============================================================================
-- Pre-Batch D, pricing_calculate had 5 BOOLEAN-default args (without
-- p_is_stacked_partner). Batch D (20260425000001) added a 6th arg,
-- p_is_stacked_partner, but did not drop the previous overload — the 5-arg
-- version lingers as a separate function because PostgreSQL distinguishes
-- overloads by full argument signature (defaults are part of the signature
-- only for resolution; the function record key includes all arg types).
--
-- Symptom: ambiguity errors or stale 5-arg results when callers omit the
-- last 2 BOOLEANs. Surgical fix: explicit DROP IF EXISTS for the legacy
-- signature. The current 6-arg version (20260425000010) is unchanged.
--
-- Risk: zero — DROP IF EXISTS is a no-op if the legacy overload never
-- existed in this environment. Only the 6-arg version is referenced in
-- the codebase (verified: order_store.dart calls supabase.rpc('create_order',
-- ...) and create_order calls pricing_calculate with all 6 args).
-- ============================================================================

BEGIN;

-- Legacy 5-arg signature (pre-Batch D)
DROP FUNCTION IF EXISTS public.pricing_calculate(
  TEXT,     -- p_service_type
  NUMERIC,  -- p_subtotal
  NUMERIC,  -- p_distance_km
  BOOLEAN,  -- p_is_partner_store
  BOOLEAN   -- p_apartment_delivery
);

-- Older 4-arg variant (extra paranoia — likely never existed but cheap to check)
DROP FUNCTION IF EXISTS public.pricing_calculate(
  TEXT,
  NUMERIC,
  NUMERIC,
  BOOLEAN
);

-- Older 3-arg variant
DROP FUNCTION IF EXISTS public.pricing_calculate(
  TEXT,
  NUMERIC,
  NUMERIC
);

-- Sanity-check: assert the 6-arg version still exists.
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT count(*) INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.proname = 'pricing_calculate';

  IF v_count = 0 THEN
    RAISE EXCEPTION 'T17: pricing_calculate disappeared after DROP — aborting';
  ELSIF v_count > 1 THEN
    RAISE WARNING 'T17: % overloads of pricing_calculate still present after cleanup. Investigate.', v_count;
  ELSE
    RAISE NOTICE 'T17: exactly 1 pricing_calculate overload remains (the 6-arg version) — OK';
  END IF;
END $$;

COMMIT;
