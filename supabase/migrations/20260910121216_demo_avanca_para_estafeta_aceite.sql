-- A maquina de demonstracao tinha um degrau em falta (2026-09-10).
--
-- `mover_pedidos_demo()` so avancava pedidos que JA estivessem em
-- 'driverAccepted' ou 'pickedUp'. Mas a app, depois de criar o pedido, poe-no
-- em 'preparing' e depois 'callingDriver' -- atras do que a funcao apanhava.
-- Nenhum pedido de demonstracao chegava a 'driverAccepted', e por isso o
-- cartao do estafeta (e a conversa com ele) nunca aparecia ao cliente.
--
-- Acrescenta-se o degrau em falta, com duas guardas: so pedidos marcados como
-- teste, e so os que ja tem estafeta atribuido pelo gatilho da caixa fechada.
-- Pedidos reais nao sao tocados.
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
     and created_at > now() - interval '2 hours';
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