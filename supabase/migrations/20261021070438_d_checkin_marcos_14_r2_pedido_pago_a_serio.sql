-- Bloco D · ronda 2 do revisor (21/10/2026) — F7: o "1 pedido pago nos ultimos 30 dias" do vale dos
-- 30 dias deixa de se poder fingir escrevendo na propria linha.
-- Pedidos: so conta um pedido entregue e pago cuja entrega ficou registada por outra pessoa que nao o
--   cliente (estafeta, loja ou servidor) no historico order_status_events, que o cliente nao escreve;
--   os 30 dias contam pela hora desse registo, nao por delivered_at (que o cliente pode escrever).
--   (O historico existe desde 12/09/2026; todas as entregas desde 13/09 la estao.)
-- Limpezas: concluidas, com profissional atribuida e pagamento confirmado pelo servidor: 'released'
--   no cartao/MB Way, 'cash_pending'/'cash_settled' no dinheiro. O cliente nao tem regra de escrita em
--   cleaning_bookings: estes campos so os escrevem as funcoes do servidor.
-- Lavagens: deixam de contar ate a regra de escrita das lavagens (P4) estar no ar. Hoje o cliente e o
--   lavador escrevem qualquer coluna da sua lavagem (carwash_bookings_update_own), por isso nada nela
--   prova um pagamento.
-- TVDE: igual (o cliente nao escreve em tvde_rides).
CREATE OR REPLACE FUNCTION public._checkin_teve_pedido_pago(p_uid uuid, p_dias integer)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH j AS (SELECT now() - make_interval(days => GREATEST(COALESCE(p_dias, 30), 1)) AS desde,
                    public.is_demo_user(p_uid) AS demo)
  SELECT EXISTS (
           SELECT 1 FROM public.orders o, j
            WHERE o.user_id = p_uid AND o.status = 'delivered' AND o.payment_status = 'paid'
              AND COALESCE(o.price, 0) > 0
              AND (NOT COALESCE(o.is_test_order, false) OR j.demo)
              AND EXISTS (SELECT 1 FROM public.order_status_events e
                           WHERE e.order_id = o.id
                             AND e.to_status = 'delivered'
                             AND e.actor_uid IS DISTINCT FROM p_uid
                             AND e.occurred_at >= j.desde))
      OR EXISTS (
           SELECT 1 FROM public.tvde_rides r, j
            WHERE r.client_id = p_uid AND r.status = 'finalizada' AND r.created_at >= j.desde)
      OR EXISTS (
           SELECT 1 FROM public.cleaning_bookings b, j
            WHERE b.client_user_id = p_uid AND b.status = 'completed' AND b.cleaner_id IS NOT NULL
              AND ((b.payment_method IN ('card', 'mbway') AND b.payment_status = 'released')
                OR (b.payment_method = 'cash' AND b.payment_status IN ('cash_pending', 'cash_settled')))
              AND COALESCE(b.completed_at, b.scheduled_at) >= j.desde
              AND (NOT COALESCE(b.is_test_order, false) OR j.demo))
$function$;

REVOKE ALL ON FUNCTION public._checkin_teve_pedido_pago(uuid, integer) FROM PUBLIC, anon, authenticated;
