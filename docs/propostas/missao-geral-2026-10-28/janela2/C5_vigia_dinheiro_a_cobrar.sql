-- C5 (missao-geral-2026-10-28): vigia do dinheiro a cobrar.
-- De 10 em 10 minutos procura pedidos a dinheiro em curso (ultimos 2 dias) em que o valor que o
-- estafeta vai cobrar (cash_total_due) e maior do que o total menos o que o cliente ja pagou com
-- saldo, tokens e credito de menu (mais 1 centimo de folga). Avisa o painel por notify_admin_event,
-- uma vez por pedido por dia. So le os pedidos: nao muda nada neles.
-- A divida antiga (debt_collected_cents) fica de fora de proposito: o create_order tambem a deixa
-- fora do cash_total_due e a app do estafeta soma-a por cima.
-- Aplicar na JANELA 2. Se a guarda recusar este texto num ficheiro de supabase/migrations, vai
-- para a lista "migracoes por pôr no repo".

create or replace function public.vigia_dinheiro_a_cobrar()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select o.id,
           o.cash_total_due,
           round(greatest(0, coalesce(o.final_total, o.price)
                 - coalesce(o.wallet_applied_cents, 0) / 100.0
                 - coalesce(o.tokens_applied_value_cents, 0) / 100.0
                 - coalesce(o.menu_credit_applied_cents, 0) / 100.0), 2) as devia
      from public.orders o
     where o.payment_method = 'cash'
       and o.status::text not in ('delivered', 'cancelled', 'canceled')
       and o.created_at > now() - interval '2 days'
       and o.cash_total_due is not null
  loop
    if r.cash_total_due > r.devia + 0.01
       and not exists (select 1 from public.admin_notifications a
                        where a.event_type = 'dinheiro_a_cobrar_a_mais'
                          and a.entity_id = r.id
                          and a.created_at > now() - interval '1 day') then
      perform public.notify_admin_event(
        'dinheiro_a_cobrar_a_mais',
        'high',
        format('Pedido %s: o estafeta vai cobrar %s € em dinheiro, mas o cliente só deve %s € (o resto já foi pago com saldo/tokens).',
               left(r.id, 8),
               replace(round(r.cash_total_due, 2)::text, '.', ','),
               replace(r.devia::text, '.', ',')),
        'order',
        r.id,
        jsonb_build_object('cash_total_due', r.cash_total_due, 'devia', r.devia),
        null);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

revoke all on function public.vigia_dinheiro_a_cobrar() from public, anon, authenticated;

select cron.schedule('vigia-dinheiro-a-cobrar', '*/10 * * * *', $c$select public.vigia_dinheiro_a_cobrar()$c$);
