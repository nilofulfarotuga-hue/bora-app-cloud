-- Esquema de ensaio (PGlite) para provar 20261117120000_receita_cartao_mbway.sql.
-- Tabelas com as colunas que as funções usam; funções auxiliares de produção copiadas
-- (_prescricao_codigo, _setting_*, _prescricao_morada_coords, _prescricao_distancia_km,
-- farmacia_botoes_visiveis) e duplos simples para create_order, is_partner_open, avisos.
-- gen_random_uuid já vem no Postgres
create schema if not exists auth;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
do $$ begin create role authenticated; exception when others then null; end $$;
do $$ begin create role anon; exception when others then null; end $$;

create table public.platform_settings (key text primary key, value jsonb);
insert into public.platform_settings values
  ('pharmacy_prescription_real_orders_enabled', '"true"'), ('mbway_enabled', 'true'), ('errand_fee_normal_cents', '600');

create table public.restaurants (id text primary key, name text, address text, lat double precision, lng double precision,
  coming_soon boolean, so_lista_permissao boolean, user_id uuid, user_ uuid, category text, pharmacy_prescription_mode text);
create table public.users (id uuid primary key, name text, phone text);
create table public.client_addresses (user_id uuid, address text, lat double precision, lng double precision, is_default boolean, updated_at timestamptz);
create table public.loja_lista_permissao (restaurant_id text, user_id uuid);
create table public.drivers (id uuid default gen_random_uuid(), user_id uuid, name text);
create table public.orders (id text primary key default gen_random_uuid()::text, user_id uuid, status text, payment_status text,
  payment_method text, service_type text, price numeric, delivery_fee numeric, distance_km numeric,
  errand_description text, errand_location_lat double precision, errand_location_lng double precision,
  errand_estimated_purchase_cents integer, dropoff_address text, dropoff_lat double precision, dropoff_lng double precision,
  driver_id uuid, payment_buffer_total numeric, errand_has_purchase boolean, errand_home_stop boolean, errand_speed text,
  created_at timestamptz default now());
create table public.payment_drafts (id uuid primary key default gen_random_uuid(), user_id uuid, payload jsonb,
  used_at timestamptz, order_id text, created_at timestamptz default now());
create table public.avisos (quem text, titulo text, id uuid);
create table public.admin_push (tipo text, resumo text);

create table public.pedidos_prescricao (
  id uuid primary key default gen_random_uuid(), created_at timestamptz default now(), updated_at timestamptz,
  restaurant_id text, user_id uuid, tipo text, estado text check (estado in ('enviado','aceite','aceite_parcial','recusado','expirado','cancelado','confirmado','entregue')),
  receita_foto_path text, receita_numero text, receita_codigo_acesso text, receita_codigo_opcao text, descricao text,
  pedido_foto_path text, morada text, lat double precision, lng double precision, nota text, assinatura_path text,
  consentimento_versao text, consentimento_texto text, consentimento_em timestamptz, valor_medicamentos_cents integer,
  itens_disponiveis text, tempo_preparacao_min integer, motivo_recusa text, motivo_texto text, volta_a_ter text,
  respondido_por uuid, respondido_em timestamptz, lembrete_enviado_em timestamptz, expira_em timestamptz,
  taxa_servico_cents integer, total_cents integer, metodo_pagamento text check (metodo_pagamento is null or metodo_pagamento in ('card','mbway','cash')),
  so_disponiveis boolean, confirmado_em timestamptz, codigo_levantamento text, codigo_entrega text, order_id text,
  is_demo boolean, cancelado_por uuid, cancelado_em timestamptz, entregue_em timestamptz, dados_apagados_em timestamptz);

create function public._setting_txt(p_key text, p_defeito text) returns text language sql stable as
  $$ select coalesce((select value #>> '{}' from public.platform_settings where key = p_key), p_defeito) $$;
create function public._setting_int(p_key text, p_defeito integer) returns integer language sql stable as
  $$ select coalesce((select (value #>> '{}')::integer from public.platform_settings where key = p_key), p_defeito) $$;
create function public.get_setting(p_key text) returns jsonb language sql stable as
  $$ select value from public.platform_settings where key = p_key $$;
create function public._prescricao_codigo(p_tam integer) returns text language sql as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, p_tam) $$;
create function public.is_admin() returns boolean language sql stable as $$ select coalesce(current_setting('test.admin', true), '') = 'sim' $$;
create function public.loja_visivel_para_mim(p text) returns boolean language sql as $$ select true $$;
create function public._haversine_km(a double precision, b double precision, c double precision, d double precision) returns double precision
  language sql immutable as $$ select 6371 * 2 * asin(sqrt(power(sin(radians(c - a) / 2), 2) + cos(radians(a)) * cos(radians(c)) * power(sin(radians(d - b) / 2), 2))) $$;
create function public.is_partner_open(p_restaurant_id text, p_at timestamptz default now()) returns jsonb language sql stable as $$
  select case when coalesce(current_setting('test.aberta', true), 'sim') = 'sim'
              then '{"is_open": true}'::jsonb else '{"is_open": false, "opens_at": "09:00", "opens_dia": "hoje"}'::jsonb end $$;
create function public._prescricao_avisar(p_id uuid, p_para text, p_tipo text, p_titulo text, p_corpo text) returns void language sql as
  $$ insert into public.avisos values (p_para, p_titulo, p_id) $$;
create function public.notify_admin_urgent_push(p_event_type text, p_summary text, p_entity_type text, p_entity_id text, p_payload jsonb, p_deep_link text)
  returns void language sql as $$ insert into public.admin_push values (p_event_type, p_summary) $$;

-- Duplo do create_order: grava o Favor como o servidor (taxa fixa 6,00 + 0,50/km acima de 2 km),
-- MB Way desligado, duplicado em 60 s, pago na criação quando payment_already_confirmed.
create function public.create_order(p_input jsonb) returns jsonb language plpgsql as $$
declare v_id text := gen_random_uuid()::text; v_fee numeric; v_user uuid := coalesce(auth.uid(), (p_input->>'user_id')::uuid);
begin
  if p_input->>'payment_method' = 'mbway' and not coalesce((public.get_setting('mbway_enabled') #>> '{}')::boolean, true) then
    raise exception 'MBWAY_DISABLED';
  end if;
  if exists (select 1 from public.orders o where o.user_id = v_user and o.service_type = 'errand'
             and o.dropoff_address = p_input->>'dropoff_address' and o.created_at > now() - interval '60 seconds'
             and o.price is not distinct from (6.00 + greatest(0, (p_input->>'distance_km')::numeric - 2) * 0.5 + (p_input->>'errand_estimated_purchase_cents')::numeric / 100)
             and o.status not in ('cancelled','rejected') and auth.uid() is not null) then
    raise exception 'duplicate_errand: já há um pedido igual';
  end if;
  v_fee := 6.00 + greatest(0, (p_input->>'distance_km')::numeric - 2) * 0.5;
  -- Um só INSERT com tudo (como o _create_order_core): os gatilhos AFTER INSERT veem as colunas.
  -- Sem compra, o preço é só a taxa (o valor estimado fica gravado na mesma), como em produção.
  insert into public.orders (id, user_id, status, payment_status, payment_method, service_type, price, delivery_fee, distance_km,
    errand_description, errand_location_lat, errand_location_lng, errand_estimated_purchase_cents, dropoff_address, dropoff_lat, dropoff_lng,
    payment_buffer_total, errand_has_purchase, errand_home_stop, errand_speed)
  values (v_id, v_user, 'created', case when coalesce((p_input->>'payment_already_confirmed')::boolean, false) then 'paid' else 'pending' end,
    p_input->>'payment_method', p_input->>'service_type',
    v_fee + case when coalesce((p_input->>'errand_has_purchase')::boolean, false)
                 then (p_input->>'errand_estimated_purchase_cents')::numeric / 100 else 0 end,
    v_fee, (p_input->>'distance_km')::numeric,
    p_input->>'errand_description', (p_input->>'errand_location_lat')::float8, (p_input->>'errand_location_lng')::float8,
    (p_input->>'errand_estimated_purchase_cents')::int, p_input->>'dropoff_address', (p_input->>'dropoff_lat')::float8, (p_input->>'dropoff_lng')::float8,
    v_fee + (p_input->>'errand_estimated_purchase_cents')::numeric / 100 * 1.2,
    (p_input->>'errand_has_purchase')::boolean, (p_input->>'errand_home_stop')::boolean, p_input->>'errand_speed');
  return jsonb_build_object('order_id', v_id, 'price', v_fee + (p_input->>'errand_estimated_purchase_cents')::numeric / 100,
                            'fees_total', v_fee, 'payment_status', (select payment_status from public.orders where id = v_id));
end $$;

-- Cópias de produção (17/11 08:10, sem mudança)
CREATE OR REPLACE FUNCTION public._prescricao_morada_coords(p_user uuid, p_morada text, p_lat double precision, p_lng double precision, OUT lat double precision, OUT lng double precision)
 RETURNS record LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m text := lower(regexp_replace(btrim(coalesce(p_morada, '')), '\s+', ' ', 'g'));
begin
  if p_lat is not null and p_lng is not null then
    lat := p_lat; lng := p_lng; return;
  end if;
  if v_m = '' then return; end if;
  select a.lat, a.lng into lat, lng from public.client_addresses a
   where a.user_id = p_user and a.lat is not null and a.lng is not null
     and lower(regexp_replace(btrim(coalesce(a.address, '')), '\s+', ' ', 'g')) = v_m
   order by a.is_default desc nulls last, a.updated_at desc nulls last limit 1;
  if lat is not null then return; end if;
  select o.dropoff_lat, o.dropoff_lng into lat, lng from public.orders o
   where o.user_id = p_user and o.dropoff_lat is not null and o.dropoff_lng is not null
     and lower(regexp_replace(btrim(coalesce(o.dropoff_address, '')), '\s+', ' ', 'g')) = v_m
   order by o.created_at desc limit 1;
end $function$;

CREATE OR REPLACE FUNCTION public._prescricao_distancia_km(p_restaurant_id text, p_lat double precision, p_lng double precision)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when p_lat is null or p_lng is null or r.lat is null or r.lng is null then null
              else round((public._haversine_km(r.lat, r.lng, p_lat, p_lng) * 1.3)::numeric, 2) end
    from public.restaurants r where r.id = p_restaurant_id
$function$;

CREATE OR REPLACE FUNCTION public.farmacia_botoes_visiveis(p_restaurant_id text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((
    select r.category = 'pharmacy'
       and public.loja_visivel_para_mim(r.id)
       and (coalesce(r.so_lista_permissao, false)
            or (public._setting_txt('pharmacy_prescription_real_orders_enabled', 'false') = 'true'
                and not coalesce(r.coming_soon, false)))
       and (
         r.pharmacy_prescription_mode = 'publico'
         or (r.pharmacy_prescription_mode = 'so_lista' and auth.uid() is not null and (
               public.is_admin() or r.user_id = auth.uid() or r.user_ = auth.uid()
               or exists (select 1 from public.loja_lista_permissao l where l.restaurant_id = r.id and l.user_id = auth.uid())))
       )
      from public.restaurants r where r.id = p_restaurant_id
  ), false);
$function$;
