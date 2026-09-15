-- 2026-09-13 -- painel admin (PT-BR): corrigir a mao o valor do talao, com auditoria.
--
-- Regra 2.6 da ordem de 13/09: o admin ve o talao, o valor, quem registou, e
-- pode corrigir o valor a mao. Cada correcao fica em admin_audit_log (quem,
-- quando, de quanto para quanto, porque) e na nota do proprio talao.
-- So corrige talao ainda nao processado (pending_admin ou cash_settled).
-- Nao mexe em orders: o valor do talao e' o reembolso do estafeta, nao o que o
-- cliente paga (regra de 09/09 -- o cliente nunca ve o talao real).

CREATE OR REPLACE FUNCTION public.admin_corrigir_talao(p_receipt_id uuid, p_novo_total_cents integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin uuid := auth.uid();
  v_r     public.order_receipts_v2;
  v_antes integer;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
  IF p_novo_total_cents IS NULL OR p_novo_total_cents <= 0 THEN RAISE EXCEPTION 'INVALID_TOTAL'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN RAISE EXCEPTION 'MOTIVO_OBRIGATORIO'; END IF;

  SELECT * INTO v_r FROM public.order_receipts_v2 WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;
  IF v_r.reimbursement_status IN ('admin_paid', 'rejected') THEN
    RAISE EXCEPTION 'INVALID_STATUS: % (ja processado; nao se corrige depois de pago ou rejeitado)', v_r.reimbursement_status;
  END IF;

  v_antes := v_r.driver_typed_total_cents;
  UPDATE public.order_receipts_v2
     SET driver_typed_total_cents   = p_novo_total_cents,
         reimbursement_amount_cents = p_novo_total_cents,
         reimbursement_admin_id     = v_admin,
         reimbursement_admin_notes  = concat_ws(' | ', reimbursement_admin_notes,
             'Corrigido pelo admin de ' || v_antes || ' para ' || p_novo_total_cents || ' cent: ' || trim(p_motivo))
   WHERE id = p_receipt_id;

  INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  VALUES (v_admin, 'receipt_corrected', 'order_receipts_v2', p_receipt_id::text,
          jsonb_build_object('order_id', v_r.order_id, 'antes_cents', v_antes,
                             'depois_cents', p_novo_total_cents, 'motivo', trim(p_motivo)));

  RETURN jsonb_build_object('ok', true, 'receipt_id', p_receipt_id,
                            'antes_cents', v_antes, 'depois_cents', p_novo_total_cents);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_corrigir_talao(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_corrigir_talao(uuid, integer, text) TO authenticated;
