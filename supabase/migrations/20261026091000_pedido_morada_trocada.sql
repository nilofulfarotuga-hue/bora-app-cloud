-- 20261026091000_pedido_morada_trocada.sql
-- Missão melhorias-paridade-2026-10-26, item 5 — o painel vê se o cliente trocou a morada
-- no último ecrã antes de pagar ("Entregar em: … · Trocar").
--
-- Não toca no create_order nem na tabela orders (zona protegida): mesmo desenho da foto do
-- favor e da data das Festas — uma RPC dedicada, chamada pela app DEPOIS de o pedido nascer.
-- Só aditivo. Reverter: drop function + drop table (fim do ficheiro).

create table if not exists public.pedido_morada_trocada (
  order_id      text primary key,
  morada_antes  text,
  morada_depois text,
  criado_em     timestamptz not null default now()
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

-- REVERTER:
--   drop function if exists public.pedido_marcar_morada_trocada(text, text);
--   drop table if exists public.pedido_morada_trocada;
