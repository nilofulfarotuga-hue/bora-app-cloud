-- ============================================================================
-- BORA — Order tip (gorjeta) in cents (BR §4.5)
-- ============================================================================
-- Additive only. Clients may add a gratuity at checkout or at the rating screen.
-- Split 80% estafeta / 20% Bora is applied downstream (payout layer) — this
-- migration only stores the amount. Does NOT touch bora_tokens, pricing, or
-- finalizePurchase logic.
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_cents INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.orders.tip_cents IS
  'Client gratuity in EUR cents (BR §4.5). 80% driver / 20% Bora — split applied post-delivery in payout layer.';

COMMIT;
