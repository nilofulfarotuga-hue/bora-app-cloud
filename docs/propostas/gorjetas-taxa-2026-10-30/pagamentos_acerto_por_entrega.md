# Proposta — gorjeta de pedido conta na semana da ENTREGA (acerto semanal) · gorjetas-taxa-2026-10-30

⚠️ ISTO MEXE EM DINHEIRO (acerto semanal do prestador). NÃO aplicado e NÃO mudado no repo: a decisão é da
Claude.ai / do Danilo. Só a proposta.

## O problema (caso concreto)
`gorjetas_online_do_prestador(p_user_id, p_ini, p_fim)` (usada por `compute_driver_settlement` e
`admin_tvde_acertos_por_tipo`) soma as gorjetas `succeeded` do prestador com `paid_at` dentro da semana.
Mas numa gorjeta de pedido o prestador só fica escrito na ENTREGA (`fn_orders_gorjeta_acompanha`: até lá é
`00000000-…`), e a gorjeta do carrinho é paga ANTES da entrega.

- Domingo 23:50 — o cliente paga um pedido com 2,00 € de gorjeta no carrinho → `tips.paid_at` = domingo 23:50,
  `provider_user_id` = 00000000-… (ainda não há estafeta).
- Segunda 00:05 UTC — o fecho semanal (job 26, `run_weekly_closeout`) fecha a semana que acabou no domingo:
  a gorjeta está na janela, mas não é de ninguém → o estafeta não a recebe.
- Segunda 00:20 — o estafeta entrega → a gorjeta passa a ser dele.
- Segunda seguinte — o fecho olha para `paid_at` dentro da nova semana: domingo 23:50 já não entra.
  **A gorjeta nunca chega ao estafeta.** O mesmo acontece com qualquer gorjeta paga numa semana e entregue
  depois do fecho (pedidos agendados para segunda, por exemplo).

## A regra proposta
Gorjeta de PEDIDO conta na semana em que fica ganha = a mais tarde entre o pagamento e a entrega
(do carrinho: paga antes → conta na entrega; dada depois: paga depois da entrega → conta no pagamento), e só
se o pedido foi entregue. Gorjeta de corrida TVDE: como hoje (`paid_at`; é sempre dada depois de a corrida acabar).

## SQL (mesma assinatura, mesmas permissões: EXECUTE só postgres e service_role)
```sql
-- guardar antes: INSERT INTO public.bkp_fn_gorjeta_liquida_20261030 ... (ou nova tabela bkp_*) com
-- pg_get_functiondef('public.gorjetas_online_do_prestador(uuid,timestamptz,timestamptz)'::regprocedure)
CREATE OR REPLACE FUNCTION public.gorjetas_online_do_prestador(p_user_id uuid, p_ini timestamp with time zone, p_fim timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 30/10/2026: soma o que o prestador recebe (gorjeta paga depois já sem a taxa da Stripe).
  -- Proposta: gorjeta de pedido conta na semana em que fica ganha (a mais tarde entre o pagamento e a
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
```

## Antes de aplicar
- Comparar, prestador a prestador, as últimas 8 semanas com a função de hoje e com esta (`SELECT` lado a lado):
  a diferença só pode estar em gorjetas de pedidos entregues noutra semana que não a do pagamento.
- Hoje há 1 gorjeta online paga (TVDE, 29/10, 2,00 € → 1,72 €): a regra nova dá o mesmo valor para ela.
- Semanas já fechadas não se recalculam (o fecho grava o acerto); a mudança vale do próximo fecho em diante.
