-- ============================================================================
-- BORA — Add restaurant_id FK to orders (FASE 4 · BUG 3 · M2.5)
-- ============================================================================
-- Adds the missing FK from orders to restaurants so we can:
--   • Notify partner correctly (M3 — admin-cancel-order Edge Function)
--   • Aggregate sales/cancellations/SLA per partner
--   • Stop relying on vendor_name string match for joins
--
-- TYPE DECISION (Danilo asked UUID, but constrained):
--   restaurants.id is TEXT (legacy, same family as orders.id and
--   orders.assigned_driver_id). FK columns must match the target type.
--   We use TEXT here — converting restaurants.id to UUID is a separate
--   project (touches every join in the codebase).
--
-- ON DELETE SET NULL (vs CASCADE):
--   Order history is sacred (10-year fiscal trail per BR §20.2). If a
--   restaurant is deleted, orders survive with restaurant_id = NULL,
--   and vendor_name is preserved as a textual record of the partner name
--   at the time of the order.
--
-- BACKFILL:
--   Match by orders.vendor_name = restaurants.name. Pre-flight checked
--   78/78 orders match (LEFT JOIN with no NULLs).
--
-- NOT NULL: NOT applied. Legacy data may have mismatches; future Flutter
--   change (CartStore.finishOrder) will populate it for new orders.
--
-- Plan: .claude/.ai/reports/2026-04-29-fase4-bug3-b2-plano.md (Q3 follow-up)
-- ============================================================================

BEGIN;

-- ─── 1. Add column with FK ─────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS restaurant_id TEXT
    REFERENCES public.restaurants(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.orders.restaurant_id IS
  'FK to restaurants.id (TEXT — legacy type). NULL allowed for legacy rows or post-deletion. vendor_name preserved as textual snapshot. Populated by CartStore.finishOrder for new orders + backfilled by migration 20260429160000.';

-- ─── 2. Index for partner-scoped queries (sales, cancellations, SLA) ──────
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_id
  ON public.orders (restaurant_id)
  WHERE restaurant_id IS NOT NULL;

-- ─── 3. Backfill via vendor_name match ─────────────────────────────────────
UPDATE public.orders o
SET restaurant_id = r.id
FROM public.restaurants r
WHERE o.vendor_name = r.name
  AND o.restaurant_id IS NULL;

COMMIT;
