-- ============================================================================
-- BORA — Orders: refund_method column (Feature 1)
-- ============================================================================
-- Captura escolha do cliente entre 'stripe' e 'wallet' no cancelamento.
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refund_method TEXT
    CHECK (refund_method IN ('stripe','wallet','none'));

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refund_status TEXT
    CHECK (refund_status IN ('pending','completed','failed'));

CREATE INDEX IF NOT EXISTS idx_orders_refund_method
  ON public.orders (refund_method) WHERE refund_method IS NOT NULL;

COMMIT;
