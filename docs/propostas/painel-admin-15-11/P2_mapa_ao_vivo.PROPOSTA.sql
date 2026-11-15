-- PROPOSTA P2 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- Só funções de LEITURA do painel (mapa ao vivo). Não mexe em pedidos, despacho, dinheiro nem RLS.
--
-- Porque é que o mapa ao vivo mostra "3" (relatório S1, conferido por SELECT a 15/11):
--   * Havia 2 estafetas ligados (drivers.is_online), os dois reais e com sinal recente.
--   * Um deles tem DUAS linhas em driver_locations, uma com drivers.id e outra com o user_id, as duas
--     recentes e a 1 m uma da outra. A admin_live_drivers junta driver_locations com drivers por
--     "d.user_id = dl.driver_id OR d.id = dl.driver_id" e devolve uma linha por posição, sem tirar os
--     repetidos: 3 linhas, dois pinos azuis um em cima do outro. O cartão AGORA do início conta
--     drivers.is_online e diz 2; por isso os números não batiam.
--   * A causa de fundo é o gatilho trg_sync_drivers_to_driver_locations, que grava com drivers.id,
--     enquanto a app grava pela driver_update_location com auth.uid() (o user_id). 17 de 22 estafetas
--     têm id diferente do user_id; já há 11 linhas repetidas e 2 órfãs. Esse gatilho alimenta o
--     despacho (proximidade), por isso NÃO se mexe aqui: fica descrito no fim, só com ordem do Danilo.
--
-- O que muda:
--   1. admin_live_drivers: uma linha por estafeta (drivers.id, o id que abre a ficha), a posição mais
--      recente, e só quem está mesmo ligado: drivers.is_online, não banido, não apagado, GPS nos
--      últimos 5 minutos. As linhas de posição sem estafeta (órfãs) deixam de aparecer. Mesmas colunas
--      e o mesmo guarda.
--   2. admin_live_orders: passa a incluir 'readyForPickup' (pronto na loja), estado válido em
--      orders_status_canonical_check que hoje desaparece do mapa.

create or replace function public.admin_live_drivers()
 returns table(driver_id uuid, driver_name text, driver_phone text, latitude numeric, longitude numeric,
               heading numeric, speed_kmh numeric, last_updated timestamp with time zone,
               active_order_id text, vehicle_type text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public._admin_op_guard();
  return query
  select x.driver_id, x.driver_name, x.driver_phone, x.latitude, x.longitude, x.heading,
         x.speed_kmh, x.last_updated, x.active_order_id, x.vehicle_type
    from (
      -- driver_id = drivers.id: é o id que a ficha do estafeta abre (AdminDriverDetailScreen
      -- procura drivers por id). Hoje a função devolvia o id da linha de posição, que para 17 de 22
      -- estafetas é o user_id e não abre a ficha.
      select distinct on (d.id)
             d.id as driver_id,
             d.name as driver_name,
             d.phone as driver_phone,
             dl.latitude, dl.longitude, dl.heading, dl.speed_kmh, dl.last_updated,
             (select o.id from public.orders o
               where (o.assigned_driver_id::text = d.user_id::text or o.assigned_driver_id::text = d.id::text)
                 and o.status in ('driverAccepted', 'pickedUp', 'onTheWay')
               order by o.created_at desc
               limit 1) as active_order_id,
             d.vehicle_type
        from public.driver_locations dl
        join public.drivers d on (d.user_id = dl.driver_id or d.id = dl.driver_id)
       where dl.is_online = true
         and d.is_online = true
         and coalesce(d.is_banned, false) = false
         and d.deleted_at is null
         and dl.last_updated > now() - interval '5 minutes'
       order by d.id, dl.last_updated desc
    ) x;
end;
$function$;

create or replace function public.admin_live_orders(p_include_test_orders boolean default false)
 returns table(id text, status text, service_type text, vendor_name text, customer_name text, total numeric,
               created_at timestamp with time zone, pickup_lat numeric, pickup_lng numeric, dropoff_lat numeric,
               dropoff_lng numeric, pickup_address text, dropoff_address text, assigned_driver_id text,
               is_partner_store boolean, is_test_order boolean)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public._admin_op_guard();
  return query
  select
    o.id,
    o.status,
    o.service_type,
    o.vendor_name,
    o.customer_name,
    coalesce(o.price, 0)::numeric,
    o.created_at,
    o.pickup_lat::numeric,
    o.pickup_lng::numeric,
    o.dropoff_lat::numeric,
    o.dropoff_lng::numeric,
    o.pickup_address,
    o.dropoff_address,
    o.assigned_driver_id,
    coalesce(o.is_partner_store, false),
    coalesce(o.is_test_order, false)
  from public.orders o
  where o.status in ('created', 'preparing', 'readyForPickup', 'callingDriver',
                     'driverAccepted', 'pickedUp', 'onTheWay')
    and (
      p_include_test_orders = true
      or coalesce(o.is_test_order, false) = false
    )
  order by o.created_at desc
  limit 100;
end;
$function$;

-- PROVA depois de aplicar (como admin no painel): o contador "Entregadores ligados" do mapa passa a
-- bater com o cartão AGORA do início. Por SQL, a contagem que a função vai devolver:
--   select count(distinct d.id)
--     from public.driver_locations dl
--     join public.drivers d on (d.user_id = dl.driver_id or d.id = dl.driver_id)
--    where dl.is_online and d.is_online and not coalesce(d.is_banned, false) and d.deleted_at is null
--      and dl.last_updated > now() - interval '5 minutes';
--
-- SÓ COM ORDEM DO DANILO (entrada do despacho, não incluído acima): o gatilho
-- fn_sync_drivers_to_driver_locations passar a gravar coalesce(NEW.user_id, NEW.id), e juntar as 11
-- linhas repetidas de driver_locations (com cópia antes em bkp_driver_locations_20261115). Mexe na
-- tabela que o despacho usa para escolher o estafeta mais perto: precisa de teste real.
