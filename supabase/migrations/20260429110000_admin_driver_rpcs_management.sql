-- ============================================================================
-- BORA — Admin driver management RPCs (FASE 3 · BUG 2 · M2)
-- ============================================================================
-- Four SECURITY DEFINER RPCs for admin actions on approved drivers. All
-- bypass drivers_update_own RLS via SECURITY DEFINER, validate the caller
-- via _admin_op_guard(), and append to admin_audit_log via log_admin_action().
--
-- Pattern reference: 20260428000003_admin_driver_rpcs.sql (Fase 2B).
--
-- RPCs in this migration:
--   1. admin_ban_driver           — soft ban, optional banned_until = suspension
--   2. admin_reactivate_driver    — clears ban / suspension state
--   3. admin_update_driver        — whitelisted edits (7 typed params)
--   4. admin_soft_delete_driver   — soft delete with 3 guards
--
-- Plan: .claude/.ai/reports/2026-04-29-fase3-bug2-b2-plano.md
-- Schema deps: 20260429000000_admin_driver_management.sql (M1)
--              20260429100000_add_nif_to_drivers.sql        (M1.5)
-- ============================================================================

BEGIN;

-- ─── 1. admin_ban_driver ────────────────────────────────────────────────────
-- Soft ban: sets is_banned=true and ancillary columns. Optional p_banned_until
-- expresses a temporary suspension (NULL = permanent).
--
-- IMPORTANT: ban does NOT touch orders. Active orders continue. The Edge
-- Function admin-force-driver-logout (M3) is called in sequence by the UI to
-- revoke sessions; the driver loses the app, the order falls into SLA, and
-- dispatch-engine re-assigns via the normal flow. Do NOT cancel active orders
-- manually here — keeps responsibilities clean and avoids double-cancel races.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_ban_driver(
  p_driver_id     UUID,
  p_reason_code   public.ban_reason_code,
  p_reason        TEXT,
  p_banned_until  TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_driver   RECORD;
  v_was_online BOOLEAN;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: ban needs a free-form reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;

  IF p_reason_code IS NULL THEN
    RAISE EXCEPTION 'reason_code_required: ban needs a canonical ban_reason_code'
      USING ERRCODE = '23502';
  END IF;

  IF p_banned_until IS NOT NULL AND p_banned_until <= now() THEN
    RAISE EXCEPTION 'banned_until_in_past: % must be in the future (now=%)',
      p_banned_until, now() USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_deleted: cannot ban a soft-deleted driver (reactivate first)'
      USING ERRCODE = '23514';
  END IF;

  IF v_driver.is_banned THEN
    RAISE EXCEPTION 'driver_already_banned: % is already banned (reactivate first to change reason/until)',
      p_driver_id USING ERRCODE = '23514';
  END IF;

  v_was_online := COALESCE(v_driver.is_online, false);

  UPDATE public.drivers
     SET is_banned       = true,
         banned_at       = now(),
         banned_by       = v_admin.admin_id,
         banned_until    = p_banned_until,
         ban_reason_code = p_reason_code,
         ban_reason      = trim(p_reason),
         is_online       = false
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      CASE WHEN p_banned_until IS NULL THEN 'driver_ban' ELSE 'driver_suspend' END,
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',     v_driver.name,
        'driver_email',    v_driver.email,
        'reason_code',     p_reason_code::text,
        'reason',          trim(p_reason),
        'banned_until',    p_banned_until,
        'is_temporary',    p_banned_until IS NOT NULL,
        'was_online',      v_was_online,
        'previous_status', public.driver_effective_status(p_driver_id)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_ban_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',      true,
    'driver_id',    p_driver_id,
    'driver_name',  v_driver.name,
    'reason_code',  p_reason_code::text,
    'reason',       trim(p_reason),
    'banned_until', p_banned_until,
    'is_temporary', p_banned_until IS NOT NULL,
    'banned_at',    now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_ban_driver(UUID, public.ban_reason_code, TEXT, TIMESTAMPTZ) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_ban_driver(UUID, public.ban_reason_code, TEXT, TIMESTAMPTZ) TO authenticated;

COMMENT ON FUNCTION public.admin_ban_driver(UUID, public.ban_reason_code, TEXT, TIMESTAMPTZ) IS
  'Soft-bans a driver. p_banned_until NULL = permanent, future timestamp = temporary suspension. SECURITY DEFINER bypasses RLS. Records driver_ban or driver_suspend in admin_audit_log. Does NOT cancel active orders — those are handled by force-logout + SLA + dispatch-engine re-assignment.';

-- ─── 2. admin_reactivate_driver ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reactivate_driver(
  p_driver_id UUID,
  p_note      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin   RECORD;
  v_driver  RECORD;
  v_cleared TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.is_banned THEN v_cleared := array_append(v_cleared, 'ban'); END IF;
  IF v_driver.deleted_at IS NOT NULL THEN v_cleared := array_append(v_cleared, 'soft_delete'); END IF;

  IF array_length(v_cleared, 1) IS NULL THEN
    RAISE EXCEPTION 'driver_already_active: % has no ban/delete state to clear',
      p_driver_id USING ERRCODE = '23514';
  END IF;

  -- Clears the FULL set: ban, suspension, soft-delete. Reactivate is a single
  -- "make this driver operational again" action, regardless of how they got here.
  UPDATE public.drivers
     SET is_banned        = false,
         banned_at        = NULL,
         banned_by        = NULL,
         banned_until     = NULL,
         ban_reason_code  = NULL,
         ban_reason       = NULL,
         deleted_at       = NULL,
         deleted_by       = NULL,
         deletion_reason  = NULL
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      'driver_reactivate',
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',          v_driver.name,
        'driver_email',         v_driver.email,
        'cleared_states',       to_jsonb(v_cleared),
        'previous_ban_reason',  v_driver.ban_reason,
        'previous_ban_code',    v_driver.ban_reason_code,
        'previous_banned_until',v_driver.banned_until,
        'previous_deleted_at',  v_driver.deleted_at,
        'note',                 p_note
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_reactivate_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',        true,
    'driver_id',      p_driver_id,
    'driver_name',    v_driver.name,
    'cleared_states', v_cleared,
    'reactivated_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reactivate_driver(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reactivate_driver(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_reactivate_driver(UUID, TEXT) IS
  'Clears ban, suspension, and soft-delete state. Single "make operational" action. SECURITY DEFINER bypasses RLS. Records driver_reactivate in admin_audit_log.';

-- ─── 3a. Helper privado: log per-field change ──────────────────────────────
-- Postgres não permite procedures aninhadas dentro de DECLARE de uma função.
-- Extraímos para função separada chamada via PERFORM. Underscore-prefix para
-- sinalizar privado (apenas chamado por admin_update_driver).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._admin_log_driver_field_change(
  p_driver_id   UUID,
  p_driver_name TEXT,
  p_field       TEXT,
  p_old         TEXT,
  p_new         TEXT,
  p_sensitive   BOOLEAN,
  p_reason      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    PERFORM public.log_admin_action(
      'driver_update_' || p_field,
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',  p_driver_name,
        'field',        p_field,
        'old_value',    CASE WHEN p_sensitive THEN '[REDACTED]' ELSE p_old END,
        'new_value',    CASE WHEN p_sensitive THEN '[REDACTED]' ELSE p_new END,
        'is_sensitive', p_sensitive,
        'reason',       p_reason
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_admin_log_driver_field_change: audit for field % failed: %', p_field, SQLERRM;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public._admin_log_driver_field_change(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT) FROM public, anon, authenticated;
-- Não é necessário GRANT — só é chamada via SECURITY DEFINER de admin_update_driver

COMMENT ON FUNCTION public._admin_log_driver_field_change(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT) IS
  'Internal helper. Records a single field-change audit entry. Best-effort: catches and warns instead of failing the parent UPDATE. Sensitive fields have values redacted in audit JSON.';

-- ─── 3b. admin_update_driver ───────────────────────────────────────────────
-- Typed whitelist: name, phone, vehicle_type, license_plate, iban, nif.
-- NULL parameter = no change. Each changed field gets its OWN audit log entry
-- with action = driver_update_<field>, before/after values, is_sensitive flag.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_driver(
  p_driver_id      UUID,
  p_reason         TEXT,
  p_name           TEXT DEFAULT NULL,
  p_phone          TEXT DEFAULT NULL,
  p_vehicle_type   TEXT DEFAULT NULL,
  p_license_plate  TEXT DEFAULT NULL,
  p_iban           TEXT DEFAULT NULL,
  p_nif            TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin     RECORD;
  v_driver    RECORD;
  v_changed   TEXT[] := ARRAY[]::TEXT[];
  v_reason_t  TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: update needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;
  v_reason_t := trim(p_reason);

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_deleted: cannot edit soft-deleted driver (reactivate first)'
      USING ERRCODE = '23514';
  END IF;

  -- vehicle_type whitelist (matches Flutter VehicleType enum)
  IF p_vehicle_type IS NOT NULL
     AND p_vehicle_type NOT IN ('motorcycle', 'car', 'bicycle') THEN
    RAISE EXCEPTION 'invalid_vehicle_type: % (allowed: motorcycle, car, bicycle)',
      p_vehicle_type USING ERRCODE = '22023';
  END IF;

  -- Apply each field separately so we can audit per-field
  IF p_name IS NOT NULL AND p_name IS DISTINCT FROM v_driver.name THEN
    UPDATE public.drivers SET name = trim(p_name) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'name',
      v_driver.name, trim(p_name), false, v_reason_t);
    v_changed := array_append(v_changed, 'name');
  END IF;

  IF p_phone IS NOT NULL AND p_phone IS DISTINCT FROM v_driver.phone THEN
    UPDATE public.drivers SET phone = trim(p_phone) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'phone',
      v_driver.phone, trim(p_phone), false, v_reason_t);
    v_changed := array_append(v_changed, 'phone');
  END IF;

  IF p_vehicle_type IS NOT NULL AND p_vehicle_type IS DISTINCT FROM v_driver.vehicle_type THEN
    UPDATE public.drivers SET vehicle_type = p_vehicle_type WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'vehicle_type',
      v_driver.vehicle_type, p_vehicle_type, false, v_reason_t);
    v_changed := array_append(v_changed, 'vehicle_type');
  END IF;

  IF p_license_plate IS NOT NULL AND p_license_plate IS DISTINCT FROM v_driver.license_plate THEN
    UPDATE public.drivers SET license_plate = trim(p_license_plate) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'license_plate',
      v_driver.license_plate, trim(p_license_plate), false, v_reason_t);
    v_changed := array_append(v_changed, 'license_plate');
  END IF;

  -- Sensitive: IBAN
  IF p_iban IS NOT NULL AND p_iban IS DISTINCT FROM v_driver.iban THEN
    UPDATE public.drivers SET iban = trim(p_iban) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'iban',
      v_driver.iban, trim(p_iban), true, v_reason_t);
    v_changed := array_append(v_changed, 'iban');
  END IF;

  -- Sensitive: NIF
  IF p_nif IS NOT NULL AND p_nif IS DISTINCT FROM v_driver.nif THEN
    UPDATE public.drivers SET nif = trim(p_nif) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'nif',
      v_driver.nif, trim(p_nif), true, v_reason_t);
    v_changed := array_append(v_changed, 'nif');
  END IF;

  IF array_length(v_changed, 1) IS NULL THEN
    RAISE EXCEPTION 'no_changes: all provided fields equal current values'
      USING ERRCODE = '23514';
  END IF;

  RETURN jsonb_build_object(
    'success',        true,
    'driver_id',      p_driver_id,
    'fields_changed', v_changed,
    'reason',         trim(p_reason),
    'updated_at',     now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_driver(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_driver(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_update_driver(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Whitelisted typed update of driver fields (name, phone, vehicle_type, license_plate, iban, nif). NULL param = no change. Each changed field gets its own driver_update_<field> audit entry; iban and nif are flagged is_sensitive=true (values redacted in audit). SECURITY DEFINER bypasses RLS.';

-- ─── 4. admin_soft_delete_driver ───────────────────────────────────────────
-- Three guards, evaluated in order. First failure aborts with a message
-- containing the actual numbers so the admin sees in the toast WHY it failed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_soft_delete_driver(
  p_driver_id UUID,
  p_reason    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_driver   RECORD;
  v_active_orders   INTEGER;
  v_balance         NUMERIC(10,2);
  v_pending_settle  INTEGER;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: soft delete needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_already_deleted: % (reactivate first if needed)',
      p_driver_id USING ERRCODE = '23514';
  END IF;

  -- ── Guard 1: active orders ───────────────────────────────────────────────
  -- orders.assigned_driver_id is TEXT (legacy) — cast for safe comparison.
  -- Active = anything not yet terminal (delivered/cancelled/rejected).
  SELECT COUNT(*) INTO v_active_orders
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status NOT IN ('delivered', 'cancelled', 'rejected');

  IF v_active_orders > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % active order(s)', v_active_orders
      USING ERRCODE = '23514';
  END IF;

  -- ── Guard 2: non-zero cash balance ───────────────────────────────────────
  SELECT COALESCE(balance, 0) INTO v_balance
  FROM public.driver_balances
  WHERE driver_id = p_driver_id;

  IF v_balance IS NOT NULL AND v_balance <> 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has non-zero balance of EUR %',
      to_char(v_balance, 'FM999990.00') USING ERRCODE = '23514';
  END IF;

  -- ── Guard 3: pending cash settlements ────────────────────────────────────
  -- driver_transactions.status: settlements awaiting reconciliation.
  SELECT COUNT(*) INTO v_pending_settle
  FROM public.driver_transactions
  WHERE driver_id = p_driver_id
    AND status = 'pending';

  IF v_pending_settle > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % pending cash settlement(s)',
      v_pending_settle USING ERRCODE = '23514';
  END IF;

  -- All guards passed — apply soft delete + force offline
  UPDATE public.drivers
     SET deleted_at      = now(),
         deleted_by      = v_admin.admin_id,
         deletion_reason = trim(p_reason),
         is_online       = false
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      'driver_soft_delete',
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',         v_driver.name,
        'driver_email',        v_driver.email,
        'reason',              trim(p_reason),
        'balance_at_delete',   COALESCE(v_balance, 0),
        'previous_status',     public.driver_effective_status(p_driver_id),
        'guards_active_orders',  v_active_orders,
        'guards_pending_settle', v_pending_settle
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_soft_delete_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',     true,
    'driver_id',   p_driver_id,
    'driver_name', v_driver.name,
    'reason',      trim(p_reason),
    'deleted_at',  now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_soft_delete_driver(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_soft_delete_driver(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_soft_delete_driver(UUID, TEXT) IS
  'Soft-deletes a driver if all 3 guards pass: no active orders, balance=0, no pending settlements. Sets deleted_at + deleted_by + deletion_reason + is_online=false. Records driver_soft_delete in admin_audit_log. SECURITY DEFINER bypasses RLS.';

COMMIT;
