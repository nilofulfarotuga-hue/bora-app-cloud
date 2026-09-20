-- 2026-09-20 — CONTAS CLARAS · Bloco 1.2 — o talão passa a ter DOIS caminhos, com nome.
--
-- O Danilo paga o reembolso do talão das duas maneiras, e as duas têm de ficar
-- escritas com o nome certo, para o extrato do estafeta dizer "reembolso creditado na
-- carteira a 19/09" ou "reembolso pago por MB Way a 19/09" — nunca só "pago".
--
--   A) "Pagar na carteira do estafeta"  → admin_mark_receipt_paid (já existia):
--      marca o talão pago, credita a carteira (o saldo acompanha o histórico desde o
--      Bloco 1, gatilho diferido) e agora grava reimbursement_method = 'wallet'.
--   B) "Já paguei por fora (MB Way / dinheiro / transferência)" → admin_mark_receipt_paid_external:
--      marca o talão pago, grava a forma, a data e a referência, NÃO credita a carteira.
--
-- Substitui a tentativa 20260920103000_admin_talao_pago_externamente_mbway.sql (nunca
-- aplicada em produção — confirmado por pg_proc e information_schema a 20/09), que fica
-- no repo vazia, marcada como superada.
--
-- Guard: is_admin() — o mesmo do caminho A, para os dois botões terem a mesma porta.
-- Auditoria: admin_audit_log, como no caminho A.

ALTER TABLE public.order_receipts_v2
  ADD COLUMN IF NOT EXISTS reimbursement_method text,
  ADD COLUMN IF NOT EXISTS reimbursement_external_paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS reimbursement_external_reference text;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'order_receipts_v2_reimbursement_method_check') THEN
    ALTER TABLE public.order_receipts_v2
      ADD CONSTRAINT order_receipts_v2_reimbursement_method_check
      CHECK (reimbursement_method IS NULL OR reimbursement_method IN ('wallet','mbway','cash','transfer'));
  END IF;
END
$do$;

COMMENT ON COLUMN public.order_receipts_v2.reimbursement_method IS
  'Como o reembolso do talão foi pago ao estafeta: wallet (crédito na carteira, caminho A) · mbway · cash · transfer (pago fora da app, caminho B). NULL = ainda não pago ou talão liquidado em dinheiro na entrega (cash_settled).';
COMMENT ON COLUMN public.order_receipts_v2.reimbursement_external_paid_at IS
  'Caminho B: data em que o Danilo pagou fora da app (o que o estafeta vê no extrato).';
COMMENT ON COLUMN public.order_receipts_v2.reimbursement_external_reference IS
  'Caminho B: referência opcional (nº da transferência MB Way, etc.).';

-- A) caminho da carteira — igual ao que estava, mais o nome do caminho -------------------
CREATE OR REPLACE FUNCTION public.admin_mark_receipt_paid(p_receipt_id uuid, p_admin_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt RECORD;
  v_order   RECORD;
  v_admin   uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  SELECT * INTO v_receipt FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_receipt.reimbursement_status <> 'pending_admin' THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_receipt.reimbursement_status;
  END IF;
  SELECT user_id, assigned_driver_id INTO v_order FROM public.orders WHERE id = v_receipt.order_id;
  IF v_order.assigned_driver_id IS NULL THEN
    RAISE EXCEPTION 'ORDER_WITHOUT_DRIVER: o pedido % não tem estafeta — não há carteira para creditar', v_receipt.order_id;
  END IF;

  UPDATE public.order_receipts_v2
     SET reimbursement_status       = 'admin_paid',
         reimbursement_amount_cents = v_receipt.driver_typed_total_cents,
         reimbursement_processed_at = now(),
         reimbursement_admin_id     = v_admin,
         reimbursement_admin_notes  = p_admin_notes,
         reimbursement_method       = 'wallet'
   WHERE id = p_receipt_id;

  -- Crédito na carteira do estafeta (o saldo acompanha o histórico pelo gatilho diferido)
  INSERT INTO public.wallet_transactions (
    user_id, amount_cents, kind, reason, related_order_id, related_admin_id, idempotency_key
  ) VALUES (
    v_order.assigned_driver_id::uuid,
    v_receipt.driver_typed_total_cents,
    'reimbursement_storeshopping',
    'Reembolso do talão creditado na carteira',
    v_receipt.order_id,
    v_admin,
    'reimb_paid_' || p_receipt_id::text
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (
    v_admin, 'receipt_paid', 'order_receipts_v2', p_receipt_id::text,
    jsonb_build_object(
      'order_id', v_receipt.order_id,
      'amount_cents', v_receipt.driver_typed_total_cents,
      'method', 'wallet',
      'notes', p_admin_notes
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'receipt_id', p_receipt_id,
    'method', 'wallet',
    'driver_credited_cents', v_receipt.driver_typed_total_cents
  );
END;
$$;

-- B) caminho "já paguei por fora" ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_mark_receipt_paid_external(
  p_receipt_id uuid,
  p_method     text,
  p_paid_at    timestamptz DEFAULT now(),
  p_reference  text        DEFAULT NULL,
  p_notes      text        DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt RECORD;
  v_order   RECORD;
  v_admin   uuid := auth.uid();
  v_method  text := lower(trim(coalesce(p_method, '')));
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF v_method NOT IN ('mbway', 'cash', 'transfer') THEN
    RAISE EXCEPTION 'METHOD_INVALID: % (esperado mbway | cash | transfer)', p_method;
  END IF;
  IF p_paid_at IS NULL OR p_paid_at > now() + interval '1 day' THEN
    RAISE EXCEPTION 'PAID_AT_INVALID';
  END IF;

  SELECT * INTO v_receipt FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_receipt.reimbursement_status <> 'pending_admin' THEN
    RAISE EXCEPTION 'INVALID_STATUS: %', v_receipt.reimbursement_status;
  END IF;
  SELECT user_id, assigned_driver_id INTO v_order FROM public.orders WHERE id = v_receipt.order_id;

  UPDATE public.order_receipts_v2
     SET reimbursement_status         = 'admin_paid',
         reimbursement_amount_cents   = v_receipt.driver_typed_total_cents,
         reimbursement_processed_at   = now(),
         reimbursement_admin_id       = v_admin,
         reimbursement_admin_notes    = p_notes,
         reimbursement_method         = v_method,
         reimbursement_external_paid_at = p_paid_at,
         reimbursement_external_reference = NULLIF(trim(coalesce(p_reference, '')), '')
   WHERE id = p_receipt_id;

  -- Sem crédito na carteira: o dinheiro já saiu por fora. Nada em wallet_transactions.

  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (
    v_admin, 'receipt_paid_external', 'order_receipts_v2', p_receipt_id::text,
    jsonb_build_object(
      'order_id', v_receipt.order_id,
      'driver_user_id', v_order.assigned_driver_id,
      'amount_cents', v_receipt.driver_typed_total_cents,
      'method', v_method,
      'paid_at', p_paid_at,
      'reference', p_reference,
      'notes', p_notes
    )
  );
  RETURN jsonb_build_object(
    'success', true,
    'receipt_id', p_receipt_id,
    'method', v_method,
    'paid_at', p_paid_at,
    'amount_cents', v_receipt.driver_typed_total_cents,
    'wallet_credited', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, timestamptz, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, timestamptz, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_mark_receipt_paid_external(uuid, text, timestamptz, text, text) IS
  'Caminho B do talão: o admin já pagou o reembolso FORA da app (mbway | cash | transfer). Marca pago, grava forma/data/referência, NÃO credita a carteira. Auditado. Só aceita pending_admin.';

-- Regularização do único caso já acontecido: talão b89e66d2 (Valdemir, pedido 9cba3644),
-- marcado admin_paid a 19/09 pelo caminho A com a nota "Pago via MBWay (painel admin)";
-- o crédito na carteira foi estornado a 20/09 (chave estorno_mbway_reimb_b89e66d2).
-- Fica escrito como o que foi: pago por MB Way a 19/09, fora da app.
UPDATE public.order_receipts_v2
   SET reimbursement_method = 'mbway',
       reimbursement_external_paid_at = '2026-09-19 23:53:13+00',
       reimbursement_external_reference = 'MB Way directo do Danilo ao Valdemir (confirmado 20/09); crédito na carteira estornado'
 WHERE id = 'b89e66d2-c815-4c72-b64d-94879c2cced6'
   AND reimbursement_status = 'admin_paid'
   AND reimbursement_method IS NULL;
