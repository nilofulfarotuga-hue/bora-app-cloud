-- farmacias-2026-11-11 · 07 (Claude.ai, 11/11 20:00)
-- PORQUÊ: o pedido de demonstração do Danilo na Farmácia da Sé (c6908bfe, 19:56) foi cancelado
-- 46 s depois com "Demonstracao terminada (fim da janela)". A limpeza `mover_pedidos_demo` fecha
-- os pedidos demo quando a JANELA da demonstração da Boom (platform_settings.modo_demo_loja,
-- terminou a 30/10) já passou — e apanhava também os pedidos das lojas escondidas (farmácias),
-- que não têm janela nenhuma.
-- O QUE MUDA: o fecho "fim da janela" passa a valer só para a loja da janela; os pedidos de
-- teste das lojas escondidas só fecham sozinhos ao fim de 6 horas (como os outros pedidos demo).
-- Nada mexe em valores cobrados ou pagos.
CREATE OR REPLACE FUNCTION public.mover_pedidos_demo()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_aceites int; v_avancados int; v_cancelados int; v_fim_janela int; v_escondidas int;
begin
  update public.orders
     set status = 'driverAccepted'
   where is_test_order
     and status in ('preparing', 'callingDriver')
     and assigned_driver_id is not null
     and created_at > now() - interval '6 hours'
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_aceites = row_count;

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

  -- Demonstração com janela (Boom): fora da janela, os pedidos demo abertos DESSA loja fecham sem custo.
  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Demonstracao terminada (fim da janela): sem custo',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and restaurant_id = public._modo_demo_def()->>'restaurant_id'
     and public._e_pedido_demo_loja(id)
     and not public._modo_demo_loja(public._modo_demo_def()->>'restaurant_id');
  get diagnostics v_fim_janela = row_count;

  -- Lojas escondidas (farmácias, 11/11): sem janela; o pedido de teste só fecha ao fim de 6 horas.
  update public.orders o
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Demonstracao terminada: sem custo',
         cancel_fee = 0
    from public.restaurants r
   where r.id = o.restaurant_id and r.so_lista_permissao
     and o.is_test_order
     and o.status not in ('delivered','cancelled','rejected')
     and o.created_at <= now() - interval '6 hours';
  get diagnostics v_escondidas = row_count;

  return 'aceites=' || v_aceites || ' avancados=' || v_avancados
         || ' cancelados=' || v_cancelados || ' fim_janela=' || v_fim_janela
         || ' escondidas=' || v_escondidas;
end;
$function$;
