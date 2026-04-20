-- ============================================================================
-- BORA — Client cancel fields (BR §8.3)
-- ============================================================================
-- Only adds columns. Never removes or modifies existing ones.
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancelled_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancel_fee    NUMERIC(10,2);

COMMENT ON COLUMN public.orders.cancel_reason IS
  'Free-text reason provided by the client when cancelling (BR §8.3).';
COMMENT ON COLUMN public.orders.cancelled_at IS
  'UTC timestamp at which the order was cancelled by the client.';
COMMENT ON COLUMN public.orders.cancel_fee IS
  'Fee retained from the customer upon cancellation, in EUR. 1.00 before dispatch / 2.50 after driver accept / full total after pickup.';

COMMIT;
