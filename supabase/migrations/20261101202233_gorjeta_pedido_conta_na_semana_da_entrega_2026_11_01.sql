-- Gorjeta de PEDIDO conta na semana em que fica ganha — proposta
-- docs/propostas/gorjetas-taxa-2026-10-30/pagamentos_acerto_por_entrega.md, aplicada 01/11/2026
-- (missão zona-vermelha-2026-11-01, autorização do Danilo 01/11 19:56: "38, gorjeta do carrinho junto
-- ao pagamento... na 38 você faz" — inclui "acerto pela data de entrega").
--
-- O problema: gorjetas_online_do_prestador (usada por compute_driver_settlement e
-- admin_tvde_acertos_por_tipo) somava por paid_at. A gorjeta do carrinho é paga ANTES da entrega e o
-- prestador só fica escrito na entrega: paga domingo 23:50, entregue segunda 00:20 → o fecho de segunda
-- 00:05 não a dava a ninguém e o fecho seguinte já não a via. Nunca chegava ao estafeta.
--
-- Regra: gorjeta de pedido conta na semana da mais tarde entre o pagamento e a entrega, e só com o
-- pedido entregue; gorjeta de corrida TVDE conta no pagamento, como antes. Semanas já fechadas não se
-- recalculam. Mesma assinatura e mesmas permissões (EXECUTE só postgres e service_role).
-- Prova (01/11): a única gorjeta online paga (TVDE 29/10, 2,00 € → 1,72 €) dá o mesmo valor.

-- 0. Cópia da definição anterior (nunca se apaga)
CREATE TABLE IF NOT EXISTS public.bkp_fn_gorjeta_liquida_20261030 (
  assinatura text, definicao text, copiado_em timestamptz
);
INSERT INTO public.bkp_fn_gorjeta_liquida_20261030 (assinatura, definicao, copiado_em)
SELECT 'public.gorjetas_online_do_prestador(uuid,timestamptz,timestamptz) [antes de 20261101202233]',
       pg_get_functiondef('public.gorjetas_online_do_prestador(uuid,timestamptz,timestamptz)'::regprocedure),
       now();

CREATE OR REPLACE FUNCTION public.gorjetas_online_do_prestador(p_user_id uuid, p_ini timestamp with time zone, p_fim timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 30/10/2026: soma o que o prestador recebe (gorjeta paga depois já sem a taxa da Stripe).
  -- 01/11/2026: gorjeta de pedido conta na semana em que fica ganha (a mais tarde entre o pagamento e a
  -- entrega) e só com o pedido entregue; gorjeta TVDE conta no pagamento, como antes.
  SELECT COALESCE(SUM(t.liquido_prestador_cents), 0) / 100.0
    FROM public.tips t
    LEFT JOIN public.orders o ON o.id = t.order_id
   WHERE t.provider_user_id = p_user_id
     AND t.status = 'succeeded'
     AND t.method IN ('card', 'mbway')
     AND (t.target <> 'order' OR o.status = 'delivered')
     AND CASE WHEN t.target = 'order' THEN GREATEST(t.paid_at, o.delivered_at) ELSE t.paid_at END >= p_ini
     AND CASE WHEN t.target = 'order' THEN GREATEST(t.paid_at, o.delivered_at) ELSE t.paid_at END <= p_fim;
$function$;
REVOKE ALL ON FUNCTION public.gorjetas_online_do_prestador(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gorjetas_online_do_prestador(uuid, timestamptz, timestamptz) TO service_role;
