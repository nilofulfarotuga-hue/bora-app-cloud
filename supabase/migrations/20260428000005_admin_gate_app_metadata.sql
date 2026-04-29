-- ============================================================================
-- BORA — FASE 2 · PARTE B · M2
-- ============================================================================
-- Migrate server-side admin gates from `user_metadata.bora_role` to
-- `app_metadata.role`. Server is STRICT (only the canonical claim) to
-- close the escalation vector where a malicious client could set
-- `bora_role='admin'` via `auth.updateUser({data:…})` and pass a guard
-- that fell back to user_metadata.
--
-- The Dart helper (`AuthAdminService.isAdmin()`) keeps the 3-tier
-- fallback (app_metadata.role → bora_role → email allowlist) for UI
-- gates only — UX-permissive, but every server-side action goes
-- through `_admin_op_guard()` which only honours app_metadata.role.
--
-- Plan: .claude/.ai/reports/2026-04-28-fase2B-plan-S2.md §2 (refined)
-- ============================================================================

BEGIN;

-- 2.1 Re-define _admin_op_guard — STRICT app_metadata.role only.
CREATE OR REPLACE FUNCTION public._admin_op_guard()
RETURNS TABLE (admin_id UUID, admin_email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID;
  v_email    TEXT;
  v_app_role TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'admin_required: not authenticated' USING ERRCODE = '42501';
  END IF;

  v_email := COALESCE(
    auth.jwt() ->> 'email',
    auth.jwt() -> 'user_metadata' ->> 'email'
  );

  -- Canonical claim: app_metadata.role (immutable by client; only
  -- service_role can write raw_app_meta_data via the auth admin API).
  v_app_role := auth.jwt() -> 'app_metadata' ->> 'role';

  IF v_app_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION
      'admin_required: app_metadata.role=% (need admin)',
      COALESCE(v_app_role, 'NULL')
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT v_uid, v_email;
END;
$$;

REVOKE ALL ON FUNCTION public._admin_op_guard() FROM public, anon;
GRANT EXECUTE ON FUNCTION public._admin_op_guard() TO authenticated;

COMMENT ON FUNCTION public._admin_op_guard() IS
  'Phase-2-B M2: STRICT gate on app_metadata.role=admin. No fallback to user_metadata.bora_role (closes escalation vector via auth.updateUser).';

-- 2.2 RLS policy admin_audit_log_select_admin → app_metadata.role only.
DROP POLICY IF EXISTS "admin_audit_log_select_admin" ON public.admin_audit_log;
CREATE POLICY "admin_audit_log_select_admin"
  ON public.admin_audit_log
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- 2.3 Storage policy admin_read_all_driver_docs uses DB join — switch to
-- raw_app_meta_data->>'role'.
DROP POLICY IF EXISTS "admin_read_all_driver_docs" ON storage.objects;
CREATE POLICY "admin_read_all_driver_docs"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'driver-documents'
    AND EXISTS (
      SELECT 1 FROM auth.users
      WHERE users.id = auth.uid()
        AND (users.raw_app_meta_data ->> 'role') = 'admin'
    )
  );

-- 2.4 Add gate to admin_dashboard_metrics (was unguarded — gap in Phase-1).
-- Convert from LANGUAGE sql to plpgsql so we can call _admin_op_guard().
CREATE OR REPLACE FUNCTION public.admin_dashboard_metrics()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin  RECORD;
  v_result JSON;
BEGIN
  -- Gate: bora admin only
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  -- Aggregate read-only KPIs (unchanged body, only gate added)
  SELECT json_build_object(
    'platform_revenue', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'platform'
    ),
    'orders_today', (
      SELECT COUNT(*)
      FROM public.orders
      WHERE created_at >= date_trunc('day', now())
    ),
    'drivers_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'driver' AND amount > 0
    ),
    'restaurants_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'restaurant' AND amount > 0
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_metrics() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_metrics() TO authenticated;

COMMENT ON FUNCTION public.admin_dashboard_metrics() IS
  'Aggregated read-only KPIs for the in-app admin dashboard. SECURITY DEFINER + admin gate (Phase-2-B M2). Returns aggregates only — never row-level data.';

COMMIT;
