-- ============================================================================
-- BORA — Phase 1 backend fixes (BR §25.3 — additive, surgical)
-- ============================================================================
-- Fixes two production-blocking bugs reported 2026-04-19:
--   BUG #1: partner cannot INSERT into orders ("Chamar estafeta") → 42501 RLS
--   BUG #3: driver cannot convert tokens → 23502 NOT NULL on order_id
--
-- Out of scope (protected zones intact):
--   - pricing_service.dart, dispatch-engine, Stripe
--   - bora_tokens triggers, driver_capacity_service, finalizePurchase
--
-- Deferred to Phase 2 (Flutter):
--   BUG #2 (avatars 403): backend RLS is correct; root cause is client-side
--           upload path or demo account with null auth.uid().
--   BUG #5 (reservations_enabled): already present (migration 20260418030000).
--   BUG #6 (driver_transactions.notes): column already exists; UI will surface it.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- BUG #1 — Allow authenticated partners to INSERT orders for their restaurant
-- ----------------------------------------------------------------------------
-- Matches the existing orders_select_partner / orders_update_partner pattern:
-- the `orders` table has no restaurant_id FK, only a free-text `vendor_name`,
-- so membership is resolved via restaurants.name + restaurants.user_ (owner).
--
-- KNOWN RISK: if two distinct partners ever own restaurants with the exact
-- same name, both can INSERT orders tagged to the other's vendor_name.
-- Mitigation (future): add restaurant_id uuid FK on orders and migrate RLS
-- to reference the FK instead of the name. Tracked for post-launch hardening.
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "orders_insert_partner" ON public.orders;

CREATE POLICY "orders_insert_partner"
  ON public.orders
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.restaurants r
      WHERE r.user_ = auth.uid()
        AND r.name = orders.vendor_name
    )
  );

COMMENT ON POLICY "orders_insert_partner" ON public.orders IS
  'BR §25.3 Phase 1 — partners create orders for their own restaurant. Vendor match by name (no FK yet).';

-- ----------------------------------------------------------------------------
-- BUG #3 — driver_transactions: allow non-delivery rows with NULL order_id
-- ----------------------------------------------------------------------------
-- Current state: order_id uuid NOT NULL — blocks token_conversion and any
-- manual adjustment not tied to a specific order.
-- Existing type values: 'delivery_earning' (29), 'cash_adjustment' (11).
-- We keep order_id mandatory for 'delivery_earning' via CHECK so the
-- financial ledger link stays intact for real deliveries.
-- No rows are rewritten; existing data already satisfies the constraint.
-- ----------------------------------------------------------------------------

ALTER TABLE public.driver_transactions
  ALTER COLUMN order_id DROP NOT NULL;

ALTER TABLE public.driver_transactions
  DROP CONSTRAINT IF EXISTS driver_transactions_order_id_required_for_delivery;

ALTER TABLE public.driver_transactions
  ADD CONSTRAINT driver_transactions_order_id_required_for_delivery
  CHECK (
    (type = 'delivery_earning' AND order_id IS NOT NULL)
    OR (type <> 'delivery_earning')
  );

COMMENT ON CONSTRAINT driver_transactions_order_id_required_for_delivery
  ON public.driver_transactions IS
  'BR §25.3 Phase 1 — order_id required only when type=delivery_earning. Permits token_conversion and adjustments with NULL order_id.';

COMMIT;
