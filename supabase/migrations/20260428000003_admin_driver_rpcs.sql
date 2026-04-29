-- ============================================================================
-- BORA — Admin driver RPCs (FASE 2 · BUG 1 · M2)
-- ============================================================================
-- Resolves the silent failure of admin approve/reject:
--   - Layer 1 (Dart early return) — handled in the Flutter screens.
--   - Layer 2 (RLS drivers_update_own) — bypassed via SECURITY DEFINER.
--
-- Three new functions:
--   - public._admin_op_guard()        — internal guard, validates bora_role='admin'
--   - public.admin_approve_driver(...)— approve with optional force + justification
--   - public.admin_reject_driver(...) — reject with mandatory reason
--
-- All three log to admin_audit_log via log_admin_action() (Fase 1 infra).
-- Plan reference: .claude/.ai/reports/2026-04-28-fase2A-bug1-plan.md §3
-- ============================================================================

BEGIN;

-- ── 1. _admin_op_guard ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._admin_op_guard()
RETURNS TABLE (admin_id UUID, admin_email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID;
  v_email TEXT;
  v_role  TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'admin_required: not authenticated' USING ERRCODE = '42501';
  END IF;

  v_email := COALESCE(
    auth.jwt() ->> 'email',
    auth.jwt() -> 'user_metadata' ->> 'email'
  );

  v_role := COALESCE(
    auth.jwt() -> 'user_metadata' ->> 'bora_role',
    auth.jwt() ->> 'role'
  );

  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin_required: caller bora_role=% (need admin)',
      COALESCE(v_role, 'NULL') USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT v_uid, v_email;
END;
$$;

REVOKE ALL ON FUNCTION public._admin_op_guard() FROM public, anon;
GRANT EXECUTE ON FUNCTION public._admin_op_guard() TO authenticated;

COMMENT ON FUNCTION public._admin_op_guard() IS
  'Internal guard: ensures the caller is authenticated AND has bora_role=admin. Returns the admin uid + email for use by admin_* RPCs.';

-- ── 2. admin_approve_driver ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_approve_driver(
  p_driver_id     UUID,
  p_force         BOOLEAN DEFAULT FALSE,
  p_justification TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin       RECORD;
  v_driver      RECORD;
  v_missing     TEXT[] := ARRAY[]::TEXT[];
  v_was_forced  BOOLEAN := FALSE;
  v_action_name TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.approval_status = 'approved' THEN
    RAISE EXCEPTION 'driver_already_approved: %', p_driver_id USING ERRCODE = '23514';
  END IF;

  -- Validate documents
  IF v_driver.photo_url IS NULL OR length(v_driver.photo_url) = 0 THEN
    v_missing := array_append(v_missing, 'Foto pessoal');
  END IF;
  IF v_driver.document_photo_url IS NULL OR length(v_driver.document_photo_url) = 0 THEN
    v_missing := array_append(v_missing, 'Foto do documento');
  END IF;
  IF v_driver.document_number IS NULL OR length(v_driver.document_number) = 0 THEN
    v_missing := array_append(v_missing, 'Número do documento');
  END IF;
  IF COALESCE(v_driver.vehicle_type, '') <> 'bicycle'
     AND (v_driver.vehicle_photo_url IS NULL OR length(v_driver.vehicle_photo_url) = 0) THEN
    v_missing := array_append(v_missing, 'Foto do veículo');
  END IF;

  IF array_length(v_missing, 1) IS NOT NULL AND NOT p_force THEN
    RAISE EXCEPTION 'missing_docs: %', array_to_string(v_missing, ', ')
      USING ERRCODE = '23502';
  END IF;

  IF p_force AND array_length(v_missing, 1) IS NOT NULL THEN
    IF p_justification IS NULL OR length(trim(p_justification)) < 3 THEN
      RAISE EXCEPTION 'justification_required: force-approve needs justification (min 3 chars)'
        USING ERRCODE = '23502';
    END IF;
    v_was_forced := TRUE;
  END IF;

  -- Apply update (SECURITY DEFINER bypasses RLS drivers_update_own)
  UPDATE public.drivers
     SET approval_status  = 'approved',
         approved_at      = now(),
         approved_by      = v_admin.admin_id,
         rejection_reason = NULL
   WHERE id = p_driver_id;

  -- Best-effort audit
  v_action_name := CASE WHEN v_was_forced THEN 'driver_force_approve' ELSE 'driver_approve' END;
  BEGIN
    PERFORM public.log_admin_action(
      v_action_name,
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',   v_driver.name,
        'driver_email',  v_driver.email,
        'missing_docs',  to_jsonb(v_missing),
        'was_forced',    v_was_forced,
        'justification', p_justification
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_approve_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',       true,
    'driver_id',     p_driver_id,
    'driver_name',   v_driver.name,
    'was_forced',    v_was_forced,
    'missing_docs',  v_missing,
    'justification', p_justification,
    'approved_at',   now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) IS
  'Admin approves a driver. SECURITY DEFINER bypasses drivers_update_own RLS. Validates required docs server-side; if missing, requires p_force=true AND p_justification (>= 3 chars). Records driver_approve OR driver_force_approve in admin_audit_log.';

-- ── 3. admin_reject_driver ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reject_driver(
  p_driver_id UUID,
  p_reason    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin  RECORD;
  v_driver RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: rejection needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.approval_status = 'rejected' THEN
    RAISE EXCEPTION 'driver_already_rejected: %', p_driver_id USING ERRCODE = '23514';
  END IF;

  UPDATE public.drivers
     SET approval_status  = 'rejected',
         rejection_reason = trim(p_reason),
         approved_at      = NULL,
         approved_by      = NULL
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      'driver_reject',
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',     v_driver.name,
        'driver_email',    v_driver.email,
        'reason',          trim(p_reason),
        'previous_status', v_driver.approval_status
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_reject_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',     true,
    'driver_id',   p_driver_id,
    'driver_name', v_driver.name,
    'reason',      trim(p_reason)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_driver(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_driver(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_reject_driver(UUID, TEXT) IS
  'Admin rejects a driver candidacy. SECURITY DEFINER bypasses RLS. Reason required (>= 3 chars). Records driver_reject in admin_audit_log.';

COMMIT;
