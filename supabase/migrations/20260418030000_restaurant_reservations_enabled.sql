-- ============================================================================
-- BORA — Partner opt-in for table reservations (BR §14.10)
-- ============================================================================
-- Additive only. Default false — reservations are opt-in per partner.
-- Does NOT modify pricing, dispatch, financial tables, or bora_tokens triggers.
-- ============================================================================

BEGIN;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS reservations_enabled BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.restaurants.reservations_enabled IS
  'BR §14.10 — partner opts in to show "Reservar mesa" button to clients. Default false.';

COMMIT;
