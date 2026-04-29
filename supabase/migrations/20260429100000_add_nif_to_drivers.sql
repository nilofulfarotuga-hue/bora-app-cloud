-- ============================================================================
-- BORA — Add NIF column to drivers (FASE 3 · BUG 2 · M1.5)
-- ============================================================================
-- Adds the Portuguese tax identifier (NIF) field to drivers, required by
-- M2 admin_update_driver whitelist. Format validation lives in Flutter,
-- not in the DB (admin may need to enter foreign drivers in the future).
--
-- DESIGN:
--   - TEXT, NULL allowed (existing rows backfill not required).
--   - UNIQUE partial index (only enforced where NIF is set) — prevents the
--     same NIF being assigned to two distinct drivers without blocking
--     rows that legitimately have NULL.
--   - No CHECK constraint on format. Validation in Flutter input.
--
-- Plan reference: .claude/.ai/reports/2026-04-29-fase3-bug2-b2-plano.md
-- Decision: Danilo 2026-04-29 (Option A: create column before M2).
-- ============================================================================

BEGIN;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS nif TEXT;

COMMENT ON COLUMN public.drivers.nif IS
  'Portuguese tax identifier (Número de Identificação Fiscal). Format validation lives in Flutter. Sensitive — flagged is_sensitive=true in admin_audit_log.';

-- Partial UNIQUE index: enforces uniqueness only where NIF is set.
CREATE UNIQUE INDEX IF NOT EXISTS idx_drivers_nif_unique
  ON public.drivers (nif)
  WHERE nif IS NOT NULL;

COMMIT;
