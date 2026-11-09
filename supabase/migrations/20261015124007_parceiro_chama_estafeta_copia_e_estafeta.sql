-- 15/10/2026 — Parceiro chama estafeta (regras 2.4.1), parte 2: copia das funcoes + estafeta.
-- O estafeta paga o TOTAL a loja na recolha e cobra o mesmo ao cliente: fica a zeros e
-- recebe so a corrida no acerto. Autorizado pelo Danilo 15/10 13:29 ("arruma tudinho certinho").
CREATE TABLE IF NOT EXISTS public.bkp_fn_parceiro_chama_20261015 AS
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
       pg_get_functiondef(p.oid) AS def, now() AS copiado_em
  FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
 WHERE s.nspname = 'public'
   AND p.proname IN ('order_driver_reimbursement','post_order_to_ledger','apply_order_financial_split',
                     'compute_partner_weekly_settlement','partner_my_weekly_closeout','extrato_parceiro',
                     'partner_monthly_statement','_fecho_pedidos','admin_partner_payout_summary');
ALTER TABLE public.bkp_fn_parceiro_chama_20261015 ENABLE ROW LEVEL SECURITY;

COMMENT ON FUNCTION public.pedido_parceiro_chamou(boolean, text, uuid) IS
  'Pedido criado pelo botao "chamar estafeta" do parceiro (regras 2.4.1). Mesma regra da app: OrderModel.isPartnerSelfDispatch.';

CREATE OR REPLACE FUNCTION public._parceiro_vendas_semana(p_share numeric, p_restaurant_id text,
                                                           p_ini timestamptz, p_fim timestamptz)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $f$
  SELECT ROUND(public._parceiro_vendas_loja(COALESCE(p_share, 0) - COALESCE(x.parte, 0), p_restaurant_id)
               + COALESCE(x.vendas, 0), 2)
    FROM (SELECT SUM(COALESCE(o.subtotal, 0)) AS parte,
                 SUM(COALESCE(o.subtotal, 0) + COALESCE(o.partner_commission_visible, 0)) AS vendas
            FROM public.orders o
           WHERE o.restaurant_id = p_restaurant_id
             AND o.status = 'delivered'
             AND public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id)
             AND o.delivered_at >= p_ini AND o.delivered_at <= p_fim) x;
$f$;
REVOKE EXECUTE ON FUNCTION public._parceiro_vendas_semana(numeric, text, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.order_driver_reimbursement(p_order_id text)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $f$
  SELECT ROUND(COALESCE(
    -- [15/10/2026] Parceiro chama estafeta: o estafeta pagou o TOTAL a loja na recolha.
    (SELECT COALESCE(o.final_total, o.price, 0)::numeric
       FROM public.orders o
      WHERE o.id = p_order_id
        AND public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id)),
    (SELECT COALESCE(r.reimbursement_amount_cents, r.driver_typed_total_cents)::numeric / 100
       FROM public.order_receipts_v2 r
      WHERE r.order_id::text = p_order_id
      ORDER BY r.created_at DESC
      LIMIT 1),
    (SELECT CASE WHEN COALESCE(o.is_purchase_finalized, false)
                 THEN COALESCE(o.final_purchase_value, 0)::numeric ELSE 0 END
       FROM public.orders o WHERE o.id = p_order_id),
    0), 2);
$f$;