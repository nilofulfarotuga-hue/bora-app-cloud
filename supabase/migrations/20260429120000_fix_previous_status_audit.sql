-- ============================================================================
-- BORA — Fix previous_status capture in admin RPCs (FASE 3 · BUG 2 · M3 sidecar)
-- ============================================================================
-- M2 smoke tests revealed that admin_ban_driver and admin_soft_delete_driver
-- were calling driver_effective_status(p_driver_id) AFTER the UPDATE, which
-- meant `details.previous_status` reflected the NEW state, not the previous one.
-- E.g. banning Dan recorded previous_status='banned' instead of 'active'.
--
-- This migration recreates both functions, capturing the prior status into a
-- local variable BEFORE the UPDATE and using that value in log_admin_action.
--
-- No signature changes. CREATE OR REPLACE — backwards-compatible.
-- ============================================================================

BEGIN;

-- ─── admin_ban_driver — fixed previous_status capture ──────────────────────
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
  v_admin       RECORD;
  v_driver      RECORD;
  v_was_online  BOOLEAN;
  v_prev_status TEXT;
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

  v_was_online  := COALESCE(v_driver.is_online, false);
  -- Capture BEFORE the UPDATE so we record the truly previous status.
  v_prev_status := public.driver_effective_status(p_driver_id);

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
        'previous_status', v_prev_status
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_ban_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',         true,
    'driver_id',       p_driver_id,
    'driver_name',     v_driver.name,
    'reason_code',     p_reason_code::text,
    'reason',          trim(p_reason),
    'banned_until',    p_banned_until,
    'is_temporary',    p_banned_until IS NOT NULL,
    'banned_at',       now(),
    'previous_status', v_prev_status
  );
END;
$$;

-- ─── admin_soft_delete_driver — fixed previous_status capture ──────────────
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
  v_admin           RECORD;
  v_driver          RECORD;
  v_active_orders   INTEGER;
  v_balance         NUMERIC(10,2);
  v_pending_settle  INTEGER;
  v_prev_status     TEXT;
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

  -- Guard 1: active orders
  SELECT COUNT(*) INTO v_active_orders
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status NOT IN ('delivered', 'cancelled', 'rejected');

  IF v_active_orders > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % active order(s)', v_active_orders
      USING ERRCODE = '23514';
  END IF;

  -- Guard 2: non-zero balance
  SELECT COALESCE(balance, 0) INTO v_balance
  FROM public.driver_balances
  WHERE driver_id = p_driver_id;

  IF v_balance IS NOT NULL AND v_balance <> 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has non-zero balance of EUR %',
      to_char(v_balance, 'FM999990.00') USING ERRCODE = '23514';
  END IF;

  -- Guard 3: pending settlements
  SELECT COUNT(*) INTO v_pending_settle
  FROM public.driver_transactions
  WHERE driver_id = p_driver_id
    AND status = 'pending';

  IF v_pending_settle > 0 THEN
    RAISE EXCEPTION 'Cannot delete: driver has % pending cash settlement(s)',
      v_pending_settle USING ERRCODE = '23514';
  END IF;

  -- Capture BEFORE the UPDATE so previous_status reflects pre-delete state.
  v_prev_status := public.driver_effective_status(p_driver_id);

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
        'driver_name',           v_driver.name,
        'driver_email',          v_driver.email,
        'reason',                trim(p_reason),
        'balance_at_delete',     COALESCE(v_balance, 0),
        'previous_status',       v_prev_status,
        'guards_active_orders',  v_active_orders,
        'guards_pending_settle', v_pending_settle
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_soft_delete_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',         true,
    'driver_id',       p_driver_id,
    'driver_name',     v_driver.name,
    'reason',          trim(p_reason),
    'deleted_at',      now(),
    'previous_status', v_prev_status
  );
END;
$$;

COMMIT;
