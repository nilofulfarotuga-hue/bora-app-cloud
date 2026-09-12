-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO 3.8 — RPCs admin: mark_receipt_paid + reject_receipt
-- Pattern: is_admin() guard, audit log, idempotency
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_mark_receipt_paid(
  p_receipt_id  uuid,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
DECLARE
  v_receipt RECORD;
  v_order   RECORD;
  v_admin   uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;

  SELECT * INTO v_receipt FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_receipt.reimbursement_status <> 'pending_admin' THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_receipt.reimbursement_status;
  END IF;

  SELECT user_id, assigned_driver_id INTO v_order FROM public.orders WHERE id = v_receipt.order_id;

  UPDATE public.order_receipts_v2
     SET reimbursement_status = 'admin_paid',
         reimbursement_processed_at = now(),
         reimbursement_admin_id = v_admin,
         reimbursement_admin_notes = p_admin_notes
   WHERE id = p_receipt_id;

  IF v_order.assigned_driver_id IS NOT NULL THEN
    INSERT INTO public.wallet_transactions (
      user_id, amount_cents, kind, reason, related_order_id, related_admin_id, idempotency_key
    ) VALUES (
      v_order.assigned_driver_id::uuid,
      v_receipt.driver_typed_total_cents,
      'reimbursement_storeshopping',
      'admin_approved_v2',
      v_receipt.order_id,
      v_admin,
      'reimb_paid_' || p_receipt_id::text
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (v_admin, 'receipt_paid', 'order_receipts_v2', p_receipt_id::text,
    jsonb_build_object('order_id', v_receipt.order_id, 'amount_cents', v_receipt.driver_typed_total_cents, 'notes', p_admin_notes));

  RETURN jsonb_build_object('success', true, 'receipt_id', p_receipt_id, 'driver_credited_cents', v_receipt.driver_typed_total_cents);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_mark_receipt_paid(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_receipt_paid(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reject_receipt(
  p_receipt_id uuid,
  p_motivo     text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, auth
AS $fn$
DECLARE
  v_receipt RECORD;
  v_admin   uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN RAISE EXCEPTION 'MOTIVO_REQUIRED'; END IF;

  SELECT * INTO v_receipt FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_receipt.reimbursement_status <> 'pending_admin' THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_receipt.reimbursement_status;
  END IF;

  UPDATE public.order_receipts_v2
     SET reimbursement_status = 'rejected',
         reimbursement_admin_notes = p_motivo,
         reimbursement_processed_at = now(),
         reimbursement_admin_id = v_admin
   WHERE id = p_receipt_id;

  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (v_admin, 'receipt_rejected', 'order_receipts_v2', p_receipt_id::text,
    jsonb_build_object('order_id', v_receipt.order_id, 'amount_cents', v_receipt.driver_typed_total_cents, 'motivo', p_motivo));

  RETURN jsonb_build_object('success', true, 'receipt_id', p_receipt_id);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_reject_receipt(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_receipt(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_mark_receipt_paid(uuid, text) IS
  '5G — Admin marca reembolso pago. Credita carteira estafeta + audit log. Idempotente.';
COMMENT ON FUNCTION public.admin_reject_receipt(uuid, text) IS
  '5G — Admin rejeita reembolso (motivo obrigatório). Audit log.';
