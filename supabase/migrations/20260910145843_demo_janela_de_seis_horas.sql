-- A janela de 2 horas dos pedidos de demonstracao e' curta demais.
--
-- CICATRIZ (2026-09-10): a gravacao para a Apple precisa de um pedido vivo
-- com estafeta atribuido. Uma corrida de CI leva ~45 min, e entre preparar,
-- correr e repetir passavam-se mais de duas horas -- o cron encerrava o
-- pedido a meio e a gravacao ficava sem a conversa para filmar. Aconteceu
-- duas vezes no mesmo dia.
--
-- Seis horas continuam a ser higiene (nenhum pedido de demonstracao fica
-- aberto de um dia para o outro) e cobrem tanto a gravacao como um revisor
-- da Apple que faca uma encomenda e volte a ela mais tarde.
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
     and created_at > now() - interval '6 hours';
  get diagnostics v_aceites = row_count;

  -- Respeita `enforce_storeshopping_finalize_before_pickup`: compra em loja
  -- sem contrato nao pode ser dada como levantada antes de finalizada. Fica
  -- em 'driverAccepted', que ja e' onde o cliente ve o estafeta e a conversa.
  update public.orders
     set status = case status
                    when 'driverAccepted' then 'pickedUp'
                    when 'pickedUp'       then 'onTheWay'
                    else status end
   where is_test_order
     and status in ('driverAccepted','pickedUp')
     and created_at > now() - interval '6 hours'
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
     and created_at <= now() - interval '6 hours';
  get diagnostics v_cancelados = row_count;

  return 'aceites=' || v_aceites || ' avancados=' || v_avancados
         || ' cancelados=' || v_cancelados;
end;
$function$;