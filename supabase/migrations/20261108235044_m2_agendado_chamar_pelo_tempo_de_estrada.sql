-- PROPOSTA · missão m2-estafeta-conta-fila-2026-11-08 · bloco 5 (pedido do Danilo 08/11 17:27)
-- ZONA DE DESPACHO: o Claude Code só leu e propõe. Aplicar: Claude.ai (com o vai do Danilo se achar
-- que é motor de despacho). Não mexe em dinheiro.
--
-- Caso real: loja não-parceira (Jyosmi) abre às 19h, pedido agendado pronto às 19:15; o estafeta foi
-- chamado às 18:45 porque a chamada era SEMPRE "hora marcada − dispatch_antecedencia_agendado_minutos"
-- (30 min fixos, em agendados_nao_parceiros_despachar e no gatilho _orders_agendado_retem).
--
-- Regra nova: chamar a (hora pronto − tempo de estrada do estafeta online mais perto até à loja − 5 min),
-- nunca menos de 10 min antes. Tempo de estrada = distância em linha reta × 1,3 a 25 km/h (a mesma
-- ordem de grandeza do dispatch); sem ninguém online, 10 min de estrada (→ chama 15 min antes).
-- O setting dispatch_antecedencia_agendado_minutos passa a ser o TECTO (nunca mais cedo do que isto).
-- "Hora pronto" = ready_at_promised (a loja prometeu) ou, sem ele, scheduled_for.

create or replace function public._agendado_minutos_antes(p_order_id text)
returns integer
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  o record;
  v_teto integer;
  v_km numeric;
  v_estrada integer;
begin
  select pickup_lat, pickup_lng into o from public.orders where id = p_order_id;
  select (value #>> '{}')::integer into v_teto
    from public.platform_settings where key = 'dispatch_antecedencia_agendado_minutos';
  v_teto := greatest(coalesce(v_teto, 30), 10);
  if o.pickup_lat is not null and o.pickup_lng is not null then
    select min(2 * 6371 * asin(sqrt(
             power(sin(radians(d.lat - o.pickup_lat) / 2), 2) +
             cos(radians(o.pickup_lat)) * cos(radians(d.lat)) *
             power(sin(radians(d.lng - o.pickup_lng) / 2), 2))))
      into v_km
      from public.drivers d
     where d.is_online and d.approval_status = 'approved' and d.deleted_at is null
       and d.lat is not null and d.lng is not null
       and coalesce(d.vehicle_type, '') <> 'carro_passageiros';
  end if;
  v_estrada := case when v_km is null then 10 else ceil(v_km * 1.3 / 25.0 * 60)::integer end;
  return least(greatest(v_estrada + 5, 10), v_teto);
end
$$;

-- Gatilho: segura em 'preparing' até à hora certa (só muda a conta dos minutos).
create or replace function public._orders_agendado_retem()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ant integer;
  v_pronto timestamptz;
begin
  if new.status = 'callingDriver'
     and old.status in ('created', 'preparing')
     and new.scheduled_for is not null
     and not (coalesce(new.service_type, '') = 'restaurant' and coalesce(new.is_partner_store, false))
  then
    v_ant := public._agendado_minutos_antes(new.id);
    v_pronto := coalesce(new.ready_at_promised, new.scheduled_for);
    if now() < v_pronto - make_interval(mins => v_ant) then
      new.status := 'preparing';
    end if;
  end if;
  return new;
end;
$function$;

-- Varredura: chama quando chega a hora certa de cada pedido (só muda a conta dos minutos).
create or replace function public.agendados_nao_parceiros_despachar()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_o   record;
  v_n   integer := 0;
begin
  for v_o in
    select id, status
      from public.orders
     where status in ('created', 'preparing')
       and scheduled_for is not null
       and service_type in ('restaurant', 'storeShopping')
       and not (service_type = 'restaurant' and coalesce(is_partner_store, false))
       and assigned_driver_id is null
       and driver_id is null
       and (coalesce(payment_method, 'cash') = 'cash' or payment_status = 'paid')
       and now() >= coalesce(ready_at_promised, scheduled_for)
                    - make_interval(mins => public._agendado_minutos_antes(id))
     order by scheduled_for
     limit 50
     for update skip locked
  loop
    begin
      perform set_config('app.order_transition_source', 'agendados_nao_parceiros_despachar', true);
      if v_o.status = 'created' then
        update public.orders set status = 'preparing' where id = v_o.id and status = 'created';
      end if;
      update public.orders set status = 'callingDriver' where id = v_o.id and status = 'preparing';
      v_n := v_n + 1;
    exception when others then
      insert into public.order_lifecycle_errors(order_id, component, error_message)
      values (v_o.id, 'agendados_nao_parceiros_despachar', sqlerrm);
    end;
  end loop;
  return v_n;
end;
$function$;

revoke all on function public._agendado_minutos_antes(text) from public, anon, authenticated;
