-- ============================================================================
-- BORA — Admin driver management schema (FASE 3 · BUG 2 · M1)
-- ============================================================================
-- Schema for admin actions on approved drivers. Adds the columns and helper
-- function needed by the upcoming admin RPCs (M2) and Edge Function (M3).
--
-- ACTIONS THIS MIGRATION ENABLES (5):
--   1. Ban           — soft, permanent OR temporary (via banned_until).
--   2. Reactivate    — clears ban / suspension / soft-delete state.
--   3. Edit          — whitelisted column updates.
--   4. Soft delete   — preserves row for FK integrity (orders, transactions,
--                      audit). Hard delete is forbidden by policy.
--   5. Force logout  — Edge Function records the event in audit columns.
--
-- DESIGN DECISIONS (Danilo 2026-04-29):
--   - "Suspend" is unified into "ban with banned_until":
--       banned_until = NULL  → permanent ban
--       banned_until > now() → temporary suspension (auto-expires)
--     One column, one RPC, simpler UX. Avoids dual state machines.
--   - Soft-only deletes. Drivers have FKs across orders/transactions/audit;
--     hard delete would break history and legal trail.
--   - ban_reason_code ENUM enables aggregate reporting (Uber/Glovo pattern);
--     ban_reason TEXT preserves free-form detail for disputes / legal defense.
--
-- WHAT THIS MIGRATION DOES *NOT* DO:
--   - No RPCs                 → M2 (separate migration)
--   - No Edge Function        → M3 (admin-force-driver-logout)
--   - No driver_transactions  → action 7 "balance adjust" removed from scope
--   - No RLS changes          → admin writes go via SECURITY DEFINER (Fase 2B)
--   - No data backfill needed → all new columns default-safe (NULL or false)
--
-- Plan reference: .claude/.ai/reports/2026-04-29-fase3-bug2-b2-plano.md
-- Scope correction: Danilo message 2026-04-29 (7 → 5 actions).
-- ============================================================================

BEGIN;

-- ─── 1. ENUM: canonical ban reason categories ───────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'ban_reason_code' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.ban_reason_code AS ENUM (
      'fraud',
      'misconduct',
      'documents_invalid',
      'inactivity',
      'safety',
      'other'
    );
  END IF;
END $$;

COMMENT ON TYPE public.ban_reason_code IS
  'Canonical ban categories for aggregate reporting and legal defense. Free-form detail lives in drivers.ban_reason TEXT.';

-- ─── 2. Drivers — admin management columns ──────────────────────────────────
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS is_banned             BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS banned_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS banned_by             UUID,
  ADD COLUMN IF NOT EXISTS banned_until          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ban_reason_code       public.ban_reason_code,
  ADD COLUMN IF NOT EXISTS ban_reason            TEXT,
  ADD COLUMN IF NOT EXISTS deleted_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by            UUID,
  ADD COLUMN IF NOT EXISTS deletion_reason       TEXT,
  ADD COLUMN IF NOT EXISTS last_forced_logout_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_forced_logout_by UUID;

COMMENT ON COLUMN public.drivers.is_banned IS
  'Soft ban flag. TRUE = driver cannot operate. Cleared by admin_reactivate_driver. Must read via driver_effective_status() for canonical view.';
COMMENT ON COLUMN public.drivers.banned_until IS
  'NULL = permanent ban. Future timestamp = temporary suspension (auto-expires via driver_effective_status).';
COMMENT ON COLUMN public.drivers.ban_reason_code IS
  'Canonical category (ENUM ban_reason_code). Set by RPC alongside is_banned=true.';
COMMENT ON COLUMN public.drivers.ban_reason IS
  'Free-form admin note explaining the ban. Set by RPC (>= 3 chars enforced).';
COMMENT ON COLUMN public.drivers.deleted_at IS
  'Soft delete. Row is preserved for FK integrity (orders, driver_transactions, admin_audit_log). Hard delete is forbidden.';
COMMENT ON COLUMN public.drivers.last_forced_logout_at IS
  'Timestamp of most recent admin-triggered session revocation (Edge Function admin-force-driver-logout).';

-- ─── 3. Indexes — partial, scoped to hot admin queries ──────────────────────
-- Active drivers list (admin dashboard, dispatch eligibility filtering).
CREATE INDEX IF NOT EXISTS idx_drivers_active
  ON public.drivers (id)
  WHERE deleted_at IS NULL AND is_banned = false;

-- Suspensions to monitor / auto-expire surfaces.
CREATE INDEX IF NOT EXISTS idx_drivers_banned_until
  ON public.drivers (banned_until)
  WHERE banned_until IS NOT NULL;

-- ─── 4. Helper: canonical effective status ──────────────────────────────────
-- Single source of truth for "what state is this driver in?" — UI, dispatch,
-- and reports MUST use this instead of reading raw columns. Precedence:
--   deleted > banned (permanent) > suspended (banned_until>now())
--   > pending > rejected > active.
CREATE OR REPLACE FUNCTION public.driver_effective_status(p_driver_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN deleted_at IS NOT NULL THEN 'deleted'
    WHEN is_banned AND (banned_until IS NULL OR banned_until > now()) THEN
      CASE WHEN banned_until IS NULL THEN 'banned' ELSE 'suspended' END
    WHEN approval_status = 'pending'  THEN 'pending'
    WHEN approval_status = 'rejected' THEN 'rejected'
    ELSE 'active'
  END
  FROM public.drivers
  WHERE id = p_driver_id;
$$;

REVOKE ALL ON FUNCTION public.driver_effective_status(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.driver_effective_status(UUID) TO authenticated;

COMMENT ON FUNCTION public.driver_effective_status(UUID) IS
  'Canonical computed status. Use everywhere instead of reading raw is_banned/deleted_at/approval_status — keeps precedence consistent and handles auto-expired suspensions.';

COMMIT;
