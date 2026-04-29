-- ============================================================================
-- BORA — Legacy seed reconciliation (FASE 2 · BUG 1 · M1)
-- ============================================================================
-- Pre-existing approved drivers had approved_at/approved_by NULL because
-- the admin panel UPDATE path was silently blocked by the
-- `drivers_update_own` RLS policy (USING user_id = auth.uid()) since day one.
-- Those drivers were therefore approved via seed/manual SQL (postgres role
-- bypasses RLS) — there is no human admin record for them.
--
-- This migration:
--   1. Sets approved_at = created_at for those rows (only proxy we have).
--   2. Leaves approved_by = NULL on purpose: there was no human admin.
--   3. Records one row per driver in admin_audit_log with admin_email
--      'system@migration' and action 'driver_legacy_seed_marked' so we
--      can always tell these apart from real human approvals later.
--
-- Plan reference: .claude/.ai/reports/2026-04-28-fase2A-bug1-plan.md §2
-- ============================================================================

BEGIN;

-- 1) Reconcile approved_at for legacy seeds
UPDATE public.drivers
SET approved_at = created_at
WHERE approval_status = 'approved'
  AND approved_at IS NULL
  AND approved_by IS NULL
  AND created_at IS NOT NULL;

-- 2) Audit one row per reconciled driver (postgres role bypasses RLS)
INSERT INTO public.admin_audit_log
  (admin_id, admin_email, action, entity_type, entity_id, details)
SELECT
  NULL,
  'system@migration',
  'driver_legacy_seed_marked',
  'driver',
  d.id,
  jsonb_build_object(
    'driver_name', d.name,
    'approved_at_set_to', d.approved_at,
    'reason',
      'Pre-existing approved drivers had approved_at/approved_by NULL '
      'because the admin panel UPDATE path was silently blocked by RLS. '
      'Reconciled by migration 20260428000002.'
  )
FROM public.drivers d
WHERE d.approval_status = 'approved'
  AND d.approved_by IS NULL
  AND d.approved_at = d.created_at;  -- only the rows we just touched

COMMIT;
