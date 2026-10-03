-- Correccao da correccao (2026-09-10).
--
-- Ao acrescentar o degrau 'callingDriver -> driverAccepted', os pedidos demo
-- passaram a chegar ao passo seguinte e bateram num gatilho de integridade:
-- `enforce_storeshopping_finalize_before_pickup` recusa marcar como levantado
-- um pedido de compra em loja sem contrato antes de a compra estar finalizada.
-- O gatilho esta certo e nao se contorna: a funcao passa a respeita-lo, e
-- esses pedidos ficam em 'driverAccepted' -- que e' onde o cliente ja ve o
-- estafeta e a conversa.
create or replace function public.mover_pedidos_demo()
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_aceites int; v_avancados int; v_cancelados int;
begin
  update public.orders
     set status = 'driverAccepted'
   where is_test_order
     and status in ('preparing', 'callingDriver')
     and assigned_driver_id is not null
     and created_at > now() - interval '2 hours';
  get diagnostics v_aceites = row_count;

  update public.orders
     set status = case status
                    when 'driverAccepted' then 'pickedUp'
                    when 'pickedUp'       then 'onTheWay'
                    else status end
   where is_test_order
     and status in ('driverAccepted','pickedUp')
     and created_at > now() - interval '2 hours'
     and not (service_type = 'storeShopping'
              and coalesce(is_partner_store, false) = false
              and coalesce(is_purchase_finalized, false) = false);
  get diagnostics v_avancados = row_count;

  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Pedido de demonstracao encerrado automaticamente',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and created_at <= now() - interval '2 hours';
  get diagnostics v_cancelados = row_count;

  return 'aceites=' || v_aceites || ' avancados=' || v_avancados
         || ' cancelados=' || v_cancelados;
end;
$function$;