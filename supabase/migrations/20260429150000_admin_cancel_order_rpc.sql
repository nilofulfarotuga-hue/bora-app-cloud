-- ============================================================================
-- BORA — admin_cancel_order RPC (FASE 4 · BUG 3 · M2)
-- ============================================================================
-- SECURITY DEFINER RPC for admin-initiated order cancellation. Marks the
-- order atomically and records audit; does NOT call Stripe nor notify —
-- those side effects are orchestrated by the admin-cancel-order Edge
-- Function (M3) which calls this RPC and then completes the flow.
--
-- IDEMPOTENCY (Danilo melhoria #1, 2026-04-29):
--   - SELECT FOR UPDATE locks the row for the duration of the txn
--   - If status is already 'cancelled' → returns the EXISTING row payload
--     (silent success, no re-marking, no duplicate audit_cancel row).
--     A separate 'order_cancel_idempotent' audit row IS recorded so we
--     can trace duplicate clicks in production.
--   - 'delivered' / 'rejected' continue to RAISE.
--
-- Pattern reference: 20260429110000_admin_driver_rpcs_management.sql
-- Plan: .claude/.ai/reports/2026-04-29-fase4-bug3-b2-plano.md
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_cancel_order(
  p_order_id    UUID,
  p_reason_code public.cancellation_reason_code,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin       RECORD;
  v_order       RECORD;
  v_prev_status TEXT;
BEGIN
  -- ── 1. Admin gate ───────────────────────────────────────────────────────
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  -- ── 2. Input validation ────────────────────────────────────────────────
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: cancellation needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;

  IF p_reason_code IS NULL THEN
    RAISE EXCEPTION 'reason_code_required: cancellation needs a canonical reason_code'
      USING ERRCODE = '23502';
  END IF;

  -- ── 3. Lock the row + load (FOR UPDATE prevents concurrent admin clicks) ─
  -- NOTE: orders.id is TEXT (legacy) — cast p_order_id (UUID) for safe compare.
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id::text
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  -- ── 4. Idempotency: already cancelled → silent success ─────────────────
  IF v_order.status = 'cancelled' THEN
    -- Best-effort audit of the duplicate attempt so we can trace it
    BEGIN
      PERFORM public.log_admin_action(
        'order_cancel_idempotent',
        'order',
        p_order_id,
        jsonb_build_object(
          'attempted_reason_code', p_reason_code::text,
          'attempted_reason',      trim(p_reason),
          'existing_cancelled_at', v_order.cancelled_at,
          'existing_initiator',    v_order.cancellation_initiator,
          'existing_reason_code',  v_order.cancellation_reason_code,
          'existing_refund_status',v_order.refund_status
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'admin_cancel_order: idempotent audit failed: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
      'success',                true,
      'idempotent',             true,
      'order_id',               p_order_id,
      'previous_status',        'cancelled',
      'cancelled_at',           v_order.cancelled_at,
      'cancellation_initiator', v_order.cancellation_initiator,
      'cancellation_reason_code', v_order.cancellation_reason_code,
      'cancel_reason',          v_order.cancel_reason,
      'refund_status',          v_order.refund_status,
      'refund_id',              v_order.refund_id,
      'refund_amount',          v_order.refund_amount,
      'payment_method',         v_order.payment_method,
      'payment_status',         v_order.payment_status,
      'payment_intent_id',      v_order.payment_intent_id,
      'total',                  v_order.total,
      'user_id',                v_order.user_id,
      'assigned_driver_id',     v_order.assigned_driver_id
    );
  END IF;

  -- ── 5. Hard guards ─────────────────────────────────────────────────────
  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'order_already_delivered: % cannot be cancelled (ledger posted, irreversible)',
      p_order_id USING ERRCODE = '23514';
  END IF;

  IF v_order.status = 'rejected' THEN
    RAISE EXCEPTION 'order_already_terminal: % is rejected (use a different flow if needed)',
      p_order_id USING ERRCODE = '23514';
  END IF;

  -- ── 6. Capture previous_status BEFORE the UPDATE (lesson FASE 3 M3 fix) ─
  v_prev_status := v_order.status;

  -- ── 7. Atomic update ───────────────────────────────────────────────────
  UPDATE public.orders SET
    status                   = 'cancelled',
    cancelled_at             = now(),
    cancelled_by             = v_admin.admin_id,
    cancellation_initiator   = 'admin',
    cancellation_reason_code = p_reason_code,
    cancel_reason            = trim(p_reason),
    refund_status            = CASE
                                 WHEN payment_method = 'cash' THEN 'not_applicable'
                                 WHEN payment_status IS DISTINCT FROM 'paid' THEN 'not_applicable'
                                 WHEN payment_intent_id IS NULL THEN 'not_applicable'
                                 ELSE 'pending'
                               END,
    -- Cleanup dispatch state to prevent ghost offers
    current_driver_offer_id  = NULL,
    driver_offer_expires_at  = NULL
    -- assigned_driver_id is preserved as historical audit (who was on this order)
  WHERE id = p_order_id::text;

  -- ── 8. Audit log (best-effort) ─────────────────────────────────────────
  BEGIN
    PERFORM public.log_admin_action(
      'order_cancel',
      'order',
      p_order_id,
      jsonb_build_object(
        'previous_status',             v_prev_status,
        'reason_code',                 p_reason_code::text,
        'reason',                      trim(p_reason),
        'payment_method',              v_order.payment_method,
        'payment_status',              v_order.payment_status,
        'payment_intent_id',           v_order.payment_intent_id,
        'total',                       v_order.total,
        'assigned_driver_id_at_cancel',v_order.assigned_driver_id,
        'user_id',                     v_order.user_id,
        'vendor_name',                 v_order.vendor_name,
        'refund_status_initial',       CASE
                                         WHEN v_order.payment_method = 'cash' THEN 'not_applicable'
                                         WHEN v_order.payment_status IS DISTINCT FROM 'paid' THEN 'not_applicable'
                                         WHEN v_order.payment_intent_id IS NULL THEN 'not_applicable'
                                         ELSE 'pending'
                                       END
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_cancel_order: audit log failed: %', SQLERRM;
  END;

  -- ── 9. Return payload (Edge Function uses these fields for refund + notify) ─
  RETURN jsonb_build_object(
    'success',                  true,
    'idempotent',               false,
    'order_id',                 p_order_id,
    'previous_status',          v_prev_status,
    'cancelled_at',             now(),
    'cancellation_initiator',   'admin',
    'cancellation_reason_code', p_reason_code::text,
    'cancel_reason',            trim(p_reason),
    'refund_status',            CASE
                                  WHEN v_order.payment_method = 'cash' THEN 'not_applicable'
                                  WHEN v_order.payment_status IS DISTINCT FROM 'paid' THEN 'not_applicable'
                                  WHEN v_order.payment_intent_id IS NULL THEN 'not_applicable'
                                  ELSE 'pending'
                                END,
    'payment_method',           v_order.payment_method,
    'payment_status',           v_order.payment_status,
    'payment_intent_id',        v_order.payment_intent_id,
    'total',                    v_order.total,
    'user_id',                  v_order.user_id,
    'assigned_driver_id',       v_order.assigned_driver_id,
    'vendor_name',              v_order.vendor_name
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_cancel_order(UUID, public.cancellation_reason_code, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_order(UUID, public.cancellation_reason_code, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_cancel_order(UUID, public.cancellation_reason_code, TEXT) IS
  'Admin cancels an order. SECURITY DEFINER bypasses RLS. Idempotent: if status already cancelled, returns existing row payload silently (logs order_cancel_idempotent for tracing). Blocks delivered/rejected. Records order_cancel in admin_audit_log. Does NOT call Stripe nor notify — those are orchestrated by admin-cancel-order Edge Function (M3) using the JSONB payload returned here.';

COMMIT;
