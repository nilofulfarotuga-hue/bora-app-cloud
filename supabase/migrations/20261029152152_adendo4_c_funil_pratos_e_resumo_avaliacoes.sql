-- ADENDO 4 — parte C: painel do parceiro.
--
--  * product_view_daily: uma linha por cliente, por prato e por dia em que
--    abriu a ficha do prato. Serve só para o funil "prato muito visto e pouco
--    pedido". Nao guarda nada alem do identificador do cliente e do dia; so se
--    le pela funcao do parceiro (abaixo), nunca pela tabela.
--  * partner_funil_pratos: aberturas contra pedidos, por prato, de uma loja.
--  * restaurant_review_summary: o resumo das avaliacoes escrito pela IA (a
--    Edge Function resumo-avaliacoes grava aqui). O parceiro so le o da sua loja.
--
-- Funcoes novas nascem fechadas a anon: so utilizadores com sessao.

create table if not exists public.product_view_daily (
  product_id    text not null,
  restaurant_id text not null,
  day           date not null default ((now() at time zone 'Europe/Lisbon')::date),
  user_id       uuid not null,
  primary key (product_id, day, user_id)
);
create index if not exists product_view_daily_loja_dia
  on public.product_view_daily (restaurant_id, day);
alter table public.product_view_daily enable row level security;
revoke all on table public.product_view_daily from anon, authenticated;

create or replace function public.registar_abertura_ficha(p_product_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_loja text;
begin
  if v_uid is null or p_product_id is null then
    return;
  end if;
  select p.restaurant_id into v_loja from public.products p where p.id = p_product_id;
  if v_loja is null then
    return;
  end if;
  insert into public.product_view_daily (product_id, restaurant_id, user_id)
  values (p_product_id, v_loja, v_uid)
  on conflict do nothing;
end;
$$;
revoke all on function public.registar_abertura_ficha(text) from public, anon;
grant execute on function public.registar_abertura_ficha(text) to authenticated;

create or replace function public.partner_funil_pratos(p_restaurant_id text, p_dias integer default 30)
returns table (product_id text, nome text, aberturas bigint, pedidos bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_dias integer := greatest(1, least(coalesce(p_dias, 30), 90));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not (
    public.is_admin()
    or exists (select 1 from public.restaurants r
                where r.id = p_restaurant_id and r.user_ = v_uid)
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  with vistas as (
    select v.product_id as pid, count(*)::bigint as n
      from public.product_view_daily v
     where v.restaurant_id = p_restaurant_id
       and v.day >= ((now() at time zone 'Europe/Lisbon')::date - v_dias)
     group by v.product_id
  ),
  pedidas as (
    select (i.item ->> 'productId') as pid,
           sum(coalesce(nullif(i.item ->> 'quantity', '')::numeric, 1))::bigint as n
      from public.orders o
     cross join lateral jsonb_array_elements(o.items) as i(item)
     where o.restaurant_id = p_restaurant_id
       and jsonb_typeof(o.items) = 'array'
       and o.created_at >= now() - make_interval(days => v_dias)
       and o.status not in ('cancelled', 'rejected')
     group by 1
  )
  select p.id::text,
         p.name::text,
         coalesce(vi.n, 0)::bigint,
         coalesce(pe.n, 0)::bigint
    from public.products p
    left join vistas  vi on vi.pid = p.id
    left join pedidas pe on pe.pid = p.id
   where p.restaurant_id = p_restaurant_id
     and (coalesce(vi.n, 0) > 0 or coalesce(pe.n, 0) > 0)
   order by coalesce(vi.n, 0) desc, p.name;
end;
$$;
revoke all on function public.partner_funil_pratos(text, integer) from public, anon;
grant execute on function public.partner_funil_pratos(text, integer) to authenticated;

create table if not exists public.restaurant_review_summary (
  restaurant_id text primary key,
  summary       text not null,
  ratings_count integer not null default 0,
  generated_at  timestamptz not null default now()
);
alter table public.restaurant_review_summary enable row level security;

drop policy if exists restaurant_review_summary_dono on public.restaurant_review_summary;
create policy restaurant_review_summary_dono
  on public.restaurant_review_summary for select to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.restaurants r
                where r.id = restaurant_review_summary.restaurant_id
                  and r.user_ = auth.uid())
  );
revoke all on table public.restaurant_review_summary from anon;
grant select on table public.restaurant_review_summary to authenticated;
