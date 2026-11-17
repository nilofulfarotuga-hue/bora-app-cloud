-- 17/11/2026 — Painel admin: bloco fixo "Encomendas por telefone a aguardar"
-- no topo do dashboard. O Danilo não encontrava o botão "Chamar estafeta já"
-- (estava só no ecrã "Encomendas por telefone"). Esta função dá ao bloco só os
-- pedidos que ainda estão à espera: loja não-parceira, pedido em 'preparing',
-- estafeta ainda não chamado (libertado_em nulo) e não cancelado.
-- Só leitura, só admin. Não mexe em preços, dispatch nem pedidos.

create or replace function public.admin_telefone_a_aguardar()
returns table(order_id text, loja text, telefone text, cliente text,
              criado_em timestamptz, encomendado_em timestamptz,
              encomendado_por_nome text, chama_estafeta_as timestamptz)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  return query
  select e.order_id, r.name, coalesce(r.phone_order_number, r.phone),
         coalesce(nullif(o.customer_name, ''), u.name, 'Cliente'),
         o.created_at, e.encomendado_em, e.encomendado_por_nome,
         coalesce(e.encomendado_em, o.created_at) + make_interval(mins => r.dispatch_delay_minutes)
    from public.encomendas_telefone e
    join public.orders o on o.id = e.order_id
    join public.restaurants r on r.id = e.restaurant_id
    left join public.users u on u.id::text = o.user_id::text
   where o.status::text = 'preparing'
     and e.libertado_em is null
     and e.cancelado_em is null
     and coalesce(r.is_partner, false) = false
   order by o.created_at;
end $function$;

revoke all on function public.admin_telefone_a_aguardar() from public, anon;
grant execute on function public.admin_telefone_a_aguardar() to authenticated;

-- Tempo real: o bloco ouve as entradas/mudanças desta tabela (a RLS
-- encomendas_telefone_admin_le só deixa o admin ler, por isso só o admin recebe).
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public'
                    and tablename = 'encomendas_telefone') then
    alter publication supabase_realtime add table public.encomendas_telefone;
  end if;
end $$;
