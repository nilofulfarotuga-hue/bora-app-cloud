-- ============================================================================
-- BORA — GAP-4 fix: cancel_fee = 0 in admin_cancel_order (FASE 4 · M2.6)
-- ============================================================================
-- Before this fix: admin cancel left cancel_fee = NULL (semantically
-- "undefined"). NULL ≠ 0: queries that aggregate cancel_fee produce
-- incorrect sums and skip admin-cancelled rows.
--
-- After this fix: cancel_fee = 0 explicitly signals "admin-initiated
-- cancellation has no customer-facing fee" (BR §11: Bora absorbs).
--
-- Only change vs previous version: add `cancel_fee = 0` to the UPDATE.
-- All logic (idempotency, guards, audit, refund_status CASE) is preserved.
--
-- Validated by: validation report 2026-04-29-fase4-bug3-validation-business-rules.md (GAP-4)
-- ============================================================================

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
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: cancellation needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;
  IF p_reason_code IS NULL THEN
    RAISE EXCEPTION 'reason_code_required: cancellation needs a canonical reason_code'
      USING ERRCODE = '23502';
  END IF;

  -- orders.id is TEXT (legacy) — cast p_order_id (UUID) for safe compare.
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id::text FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency: already cancelled → silent success
  IF v_order.status = 'cancelled' THEN
    BEGIN
      PERFORM public.log_admin_action(
        'order_cancel_idempotent', 'order', p_order_id,
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
      'success', true, 'idempotent', true, 'order_id', p_order_id,
      'previous_status', 'cancelled',
      'cancelled_at', v_order.cancelled_at,
      'cancellation_initiator', v_order.cancellation_initiator,
      'cancellation_reason_code', v_order.cancellation_reason_code,
      'cancel_reason', v_order.cancel_reason,
      'refund_status', v_order.refund_status,
      'refund_id', v_order.refund_id,
      'refund_amount', v_order.refund_amount,
      'payment_method', v_order.payment_method,
      'payment_status', v_order.payment_status,
      'payment_intent_id', v_order.payment_intent_id,
      'total', v_order.total,
      'user_id', v_order.user_id,
      'assigned_driver_id', v_order.assigned_driver_id
    );
  END IF;

  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'order_already_delivered: % cannot be cancelled (ledger posted, irreversible)',
      p_order_id USING ERRCODE = '23514';
  END IF;
  IF v_order.status = 'rejected' THEN
    RAISE EXCEPTION 'order_already_terminal: % is rejected (use a different flow if needed)',
      p_order_id USING ERRCODE = '23514';
  END IF;

  v_prev_status := v_order.status;  -- capture BEFORE the UPDATE (lesson from Fase 3 M3)

  UPDATE public.orders SET
    status                   = 'cancelled',
    cancelled_at             = now(),
    cancelled_by             = v_admin.admin_id,
    cancellation_initiator   = 'admin',
    cancellation_reason_code = p_reason_code,
    cancel_reason            = trim(p_reason),
    cancel_fee               = 0,            -- GAP-4 fix: explicit 0 (not NULL) — admin never charges client a cancellation fee
    refund_status            = CASE
                                 WHEN payment_method = 'cash' THEN 'not_applicable'
                                 WHEN payment_status IS DISTINCT FROM 'paid' THEN 'not_applicable'
                                 WHEN payment_intent_id IS NULL THEN 'not_applicable'
                                 ELSE 'pending'
                               END,
    current_driver_offer_id  = NULL,
    driver_offer_expires_at  = NULL
  WHERE id = p_order_id::text;

  BEGIN
    PERFORM public.log_admin_action(
      'order_cancel', 'order', p_order_id,
      jsonb_build_object(
        'previous_status',              v_prev_status,
        'reason_code',                  p_reason_code::text,
        'reason',                       trim(p_reason),
        'payment_method',               v_order.payment_method,
        'payment_status',               v_order.payment_status,
        'payment_intent_id',            v_order.payment_intent_id,
        'total',                        v_order.total,
        'assigned_driver_id_at_cancel', v_order.assigned_driver_id,
        'user_id',                      v_order.user_id,
        'vendor_name',                  v_order.vendor_name,
        'refund_status_initial',        CASE
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

  RETURN jsonb_build_object(
    'success', true, 'idempotent', false, 'order_id', p_order_id,
    'previous_status', v_prev_status,
    'cancelled_at', now(),
    'cancellation_initiator', 'admin',
    'cancellation_reason_code', p_reason_code::text,
    'cancel_reason', trim(p_reason),
    'refund_status', CASE
                       WHEN v_order.payment_method = 'cash' THEN 'not_applicable'
                       WHEN v_order.payment_status IS DISTINCT FROM 'paid' THEN 'not_applicable'
                       WHEN v_order.payment_intent_id IS NULL THEN 'not_applicable'
                       ELSE 'pending'
                     END,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'payment_intent_id', v_order.payment_intent_id,
    'total', v_order.total,
    'user_id', v_order.user_id,
    'assigned_driver_id', v_order.assigned_driver_id,
    'vendor_name', v_order.vendor_name
  );
END;
$$;
