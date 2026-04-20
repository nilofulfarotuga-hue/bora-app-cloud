-- ============================================================================
-- BORA — Drop duplicate tip_cents column (BR §4.5 consolidation)
-- ============================================================================
-- `tip_cents` was added on 2026-04-18 but duplicates the pre-existing
-- `tip_amount_cents` (migration 20260418002108_order_tips) which is already
-- used by rating_screen.dart. Zero data in tip_cents (column just created).
-- Zero triggers reference it. Safe to drop.
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  DROP COLUMN IF EXISTS tip_cents;

COMMIT;
