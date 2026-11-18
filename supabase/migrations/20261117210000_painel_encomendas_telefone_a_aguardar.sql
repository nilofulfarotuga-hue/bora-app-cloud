-- 17/11/2026 — Painel admin: bloco "Encomendas por telefone a aguardar" no topo do dashboard.
-- O botão "Chamar estafeta já" (admin_chamar_estafeta_ja, 25/10) estava escondido na lista
-- "Encomendas por telefone". Esta função dá só os pedidos que ainda esperam: loja não-parceira,
-- pedido em 'preparing', estafeta por chamar e encomenda não cancelada — com o nome do cliente
-- e a hora do servidor (para a contagem decrescente não depender do relógio do telemóvel).
-- Só leitura. Não mexe em preços, dispatch nem dinheiro.

create or replace function public.admin_encomendas_telefone_a_aguardar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'so_admin' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'agora', now(),
    'pedidos', coalesce((
      select jsonb_agg(x order by x.criado_em)
        from (
          select e.order_id,
                 r.name as loja,
                 coalesce(r.phone_order_number, r.phone) as telefone,
                 coalesce(nullif(trim(o.customer_name), ''), nullif(trim(u.name), ''), 'Cliente') as cliente,
                 o.created_at as criado_em,
                 e.encomendado_em,
                 e.encomendado_por_nome,
                 coalesce(e.encomendado_em, o.created_at)
                   + make_interval(mins => coalesce(r.dispatch_delay_minutes, 15)) as chama_estafeta_as
            from public.encomendas_telefone e
            join public.orders o on o.id = e.order_id
            join public.restaurants r on r.id = e.restaurant_id
            left join public.users u on u.id::text = o.user_id::text
           where o.status::text = 'preparing'
             and e.libertado_em is null
             and e.cancelado_em is null
             and coalesce(r.is_partner, false) = false
        ) x
    ), '[]'::jsonb)
  );
end
$function$;

revoke all on function public.admin_encomendas_telefone_a_aguardar() from public, anon;
grant execute on function public.admin_encomendas_telefone_a_aguardar() to authenticated, service_role;

-- Tempo real: o bloco do painel ouve as mudanças da tabela (RLS já só deixa o admin ler).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'encomendas_telefone'
  ) then
    alter publication supabase_realtime add table public.encomendas_telefone;
  end if;
end $$;
