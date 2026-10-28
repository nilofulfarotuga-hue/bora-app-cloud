-- 20261026091000_pedido_morada_trocada.sql
-- Missão melhorias-paridade-2026-10-26, item 5 — o painel vê se o cliente trocou a morada
-- no último ecrã antes de pagar ("Entregar em: … · Trocar").
--
-- Não toca no create_order nem na tabela orders (zona protegida): mesmo desenho da foto do
-- favor e da data das Festas — uma RPC dedicada, chamada pela app DEPOIS de o pedido nascer.
-- Adendo C (26/10): no cartão, quando o pedido demora a nascer (webhook), a app só tem o
-- RASCUNHO do pagamento (payment_drafts.id); a marca fica presa ao rascunho e o painel
-- encontra-a pelo payment_intent_id do pedido (o rascunho é limpo por cron depois de usado).
-- Só aditivo. Reverter: fim do ficheiro.

create table if not exists public.pedido_morada_trocada (
  id            uuid primary key default gen_random_uuid(),
  order_id      text unique,
  draft_id      uuid unique,
  payment_intent_id text unique,
  morada_antes  text,
  morada_depois text,
  criado_em     timestamptz not null default now(),
  constraint pedido_morada_trocada_alvo check (order_id is not null or draft_id is not null)
);
alter table public.pedido_morada_trocada enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'pedido_morada_trocada'
                   and policyname = 'pedido_morada_trocada_admin_le') then
    create policy pedido_morada_trocada_admin_le on public.pedido_morada_trocada
      for select to authenticated using (public.is_admin());
  end if;
end $$;

-- O dono do pedido marca que trocou a morada no fim. Só lê orders (não escreve lá).
create or replace function public.pedido_marcar_morada_trocada(p_order_id text, p_morada_antes text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_depois text;
begin
  select o.dropoff_address into v_depois
  from public.orders o
  where o.id = p_order_id and o.user_id::text = auth.uid()::text;
  if not found then
    return false;
  end if;
  insert into public.pedido_morada_trocada (order_id, morada_antes, morada_depois)
  values (p_order_id, left(coalesce(p_morada_antes, ''), 300), v_depois)
  on conflict (order_id) do nothing;
  return true;
end $$;
revoke all on function public.pedido_marcar_morada_trocada(text, text) from public, anon;
grant execute on function public.pedido_marcar_morada_trocada(text, text) to authenticated;

-- Adendo C: o mesmo, pelo rascunho do pagamento por cartão (pedido ainda a nascer).
create or replace function public.pedido_marcar_morada_trocada_rascunho(p_draft_id uuid, p_morada_antes text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_depois text;
  v_order  text;
  v_pi     text;
begin
  select d.payload->>'dropoff_address', d.order_id, d.payment_intent_id into v_depois, v_order, v_pi
  from public.payment_drafts d
  where d.id = p_draft_id and d.user_id = auth.uid();
  if not found then
    return false;
  end if;
  insert into public.pedido_morada_trocada (draft_id, order_id, payment_intent_id, morada_antes, morada_depois)
  values (p_draft_id, v_order, v_pi, left(coalesce(p_morada_antes, ''), 300), v_depois)
  on conflict do nothing;
  return true;
end $$;
revoke all on function public.pedido_marcar_morada_trocada_rascunho(uuid, text) from public, anon;
grant execute on function public.pedido_marcar_morada_trocada_rascunho(uuid, text) to authenticated;

-- Painel: a marca de um pedido, pelo id do pedido OU pelo rascunho que o criou.
create or replace function public.admin_morada_trocada(p_order_id text)
returns table (morada_antes text, morada_depois text, criado_em timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select m.morada_antes, m.morada_depois, m.criado_em
  from public.pedido_morada_trocada m
  where public.is_admin()
    and (m.order_id = p_order_id
         or m.payment_intent_id = (select o.payment_intent_id from public.orders o where o.id = p_order_id)
         or m.draft_id in (select d.id from public.payment_drafts d where d.order_id = p_order_id))
  order by m.criado_em
  limit 1;
$$;
revoke all on function public.admin_morada_trocada(text) from public, anon;
grant execute on function public.admin_morada_trocada(text) to authenticated;

-- REVERTER:
--   drop function if exists public.admin_morada_trocada(text);
--   drop function if exists public.pedido_marcar_morada_trocada_rascunho(uuid, text);
--   drop function if exists public.pedido_marcar_morada_trocada(text, text);
--   drop table if exists public.pedido_morada_trocada;
