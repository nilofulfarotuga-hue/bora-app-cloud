-- 2026-09-20 — Talão pago EXTERNAMENTE (sem crédito de wallet).
--
-- Pedido 9cba3644-5733-4fe4-9898-d24b896ff3f9 — McDonald's p/ Lariza, entregue
-- por Valdemir Vasconcelos. O talão (8,20 € / 820 cêntimos) já foi pago FORA
-- da plataforma: MB Way direto do Danilo ao Valdemir.
--
-- Porque existe: admin_mark_receipt_paid CREDITA o valor na wallet do estafeta
-- (wallet_transactions). Usá-la aqui duplicaria o pagamento. Esta RPC marca o
-- reembolso como pago e regista o meio, o valor e a observação, SEM criar
-- wallet_transactions, SEM tocar ledger/driver_balances/payouts e SEM alterar
-- ganhos da entrega (driver_transactions fica intacto).
--
-- Guard: _admin_op_guard() (app_metadata.role='admin' estrito — o guard dos
-- RPCs admin atuais). Idempotente: só aceita talão em pending_admin; repetir
-- numa chamada já processada levanta INVALID_STATUS e não duplica nada.

ALTER TABLE public.order_receipts_v2
  ADD COLUMN IF NOT EXISTS reimbursement_method text;

COMMENT ON COLUMN public.order_receipts_v2.reimbursement_method IS
  '5G — Meio do reembolso pago fora da plataforma ("MB Way", "Transferência", etc.).';

CREATE OR REPLACE FUNCTION public.admin_mark_receipt_paid_external(
  p_receipt_id   uuid,
  p_method       text,
  p_amount_cents integer,
  p_notes        text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
DECLARE
  v_admin_id    uuid;
  v_admin_email text;
  v_receipt     RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin_id, v_admin_email FROM public._admin_op_guard();

  IF p_receipt_id IS NULL THEN RAISE EXCEPTION 'RECEIPT_REQUIRED'; END IF;
  IF p_method IS NULL OR length(trim(p_method)) = 0 THEN RAISE EXCEPTION 'METHOD_REQUIRED'; END IF;
  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_notes IS NULL OR length(trim(p_notes)) < 3 THEN RAISE EXCEPTION 'NOTES_REQUIRED'; END IF;

  SELECT * INTO v_receipt FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_receipt.reimbursement_status <> 'pending_admin' THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_receipt.reimbursement_status;
  END IF;
  IF p_amount_cents <> v_receipt.driver_typed_total_cents THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: talao=% recebido=%', v_receipt.driver_typed_total_cents, p_amount_cents;
  END IF;

  UPDATE public.order_receipts_v2
     SET reimbursement_status       = 'admin_paid',
         reimbursement_amount_cents = p_amount_cents,
         reimbursement_method       = trim(p_method),
         reimbursement_processed_at = now(),
         reimbursement_admin_id     = v_admin_id,
         reimbursement_admin_notes  = trim(p_notes)
   WHERE id = p_receipt_id;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin_id, v_admin_email, 'receipt_paid_external', 'order_receipts_v2', p_receipt_id::text,
          jsonb_build_object('order_id', v_receipt.order_id, 'amount_cents', p_amount_cents,
                             'method', trim(p_method), 'notes', trim(p_notes)));

  RETURN jsonb_build_object('ok', true, 'receipt_id', p_receipt_id,
                            'amount_cents', p_amount_cents, 'method', trim(p_method));
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, integer, text) TO authenticated;

COMMENT ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, integer, text) IS
  '5G — Admin marca reembolso de talão pago EXTERNAMENTE (ex.: MB Way direto do Danilo ao estafeta). Sem wallet_transactions, sem alterar ganhos da entrega. Auditado em admin_audit_log. Idempotente (só aceita pending_admin).';

-- Execução para o talão do pedido 9cba3644-5733-4fe4-9898-d24b896ff3f9
-- (receipt b89e66d2-c815-4c72-b64d-94879c2cced6, value 820 cêntimos):
--
-- select public.admin_mark_receipt_paid_external(
--   'b89e66d2-c815-4c72-b64d-94879c2cced6',
--   'MB Way',
--   820,
--   'Transferência feita diretamente pelo Danilo ao Valdemir'
-- );