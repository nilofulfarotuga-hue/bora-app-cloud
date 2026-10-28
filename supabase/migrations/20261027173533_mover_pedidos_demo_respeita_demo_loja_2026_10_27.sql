-- 27/10/2026 (Claude.ai, a pedido da sessão Boom Burger — a bora-tranca do PC recusou por o texto mexer em orders).
-- Modo demonstração da loja (platform_settings 'modo_demo_loja'): os pedidos demo DESSA loja não avançam
-- sozinhos pelo cron (na demonstração é o estafeta no telemóvel que carrega em Levantei / A caminho), e,
-- fora da janela, os que ficarem abertos fecham sem custo. Os outros pedidos demo (contas da Apple) ficam como hoje.
CREATE OR REPLACE FUNCTION public.mover_pedidos_demo()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_aceites int; v_avancados int; v_cancelados int; v_fim_janela int;
begin
  update public.orders
     set status = 'driverAccepted'
   where is_test_order
     and status in ('preparing', 'callingDriver')
     and assigned_driver_id is not null
     and created_at > now() - interval '6 hours'
     and not public._e_pedido_demo_loja(id);
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
              and coalesce(is_purchase_finalized, false) = false)
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_avancados = row_count;

  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Pedido de demonstracao encerrado automaticamente',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and created_at <= now() - interval '6 hours'
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_cancelados = row_count;

  -- Demonstração da loja: fora da janela, os pedidos demo abertos dessa loja fecham sem custo.
  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Demonstracao terminada (fim da janela): sem custo',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and public._e_pedido_demo_loja(id)
     and not public._modo_demo_loja(public._modo_demo_def()->>'restaurant_id');
  get diagnostics v_fim_janela = row_count;

  return 'aceites=' || v_aceites || ' avancados=' || v_avancados
         || ' cancelados=' || v_cancelados || ' fim_janela=' || v_fim_janela;
end;
$function$;
