-- Resumo diário de uma campanha paga — missão guarda-primeiro-2026-10-26.
-- Quem chama: resumo_do_dia.py na VPS (Hermes), às 21:30, com a chave HERMES_DECISOR_KEY
-- (segredo hermes_decisor_key do vault). Só devolve CONTAGENS, nada pessoal.
--
-- Atenção ao que isto mede: a app não lê a origem da instalação (Install Referrer), por isso
-- um 1.º pedido NÃO se consegue ligar conta a conta à origem do anúncio. Devolve-se:
--   visitas  = pessoas que abriram www.boraguarda.com/baixar?de=<origem> (link_clicks, sem robôs);
--   contas   = contas novas criadas (auth.users) — todas as origens;
--   primeiros = clientes cujo 1.º pedido pago e entregue de sempre caiu no período — todas as origens.
-- O texto do resumo diz isto às claras.

create or replace function public.campanha_pago_resumo(
  p_chave text,
  p_origem text,
  p_inicio date,
  p_dia date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok text;
  v_ini timestamptz := (p_inicio::timestamp at time zone 'Europe/Lisbon');
  v_dia_ini timestamptz := (p_dia::timestamp at time zone 'Europe/Lisbon');
  v_dia_fim timestamptz := ((p_dia + 1)::timestamp at time zone 'Europe/Lisbon');
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'hermes_decisor_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then
    raise exception 'chave_invalida';
  end if;

  return (
    with primeiros as (
      select o.user_id, min(coalesce(o.delivered_at, o.created_at)) as em
      from public.orders o
      where o.status = 'delivered'
        and o.payment_status = 'paid'
        and coalesce(o.is_test_order, false) = false
        and o.user_id is not null
      group by o.user_id
    )
    select jsonb_build_object(
      'visitas_dia', (select count(*) from public.link_clicks c
                      where c.origin = p_origem and not public.e_robo(c.user_agent)
                        and c.created_at >= v_dia_ini and c.created_at < v_dia_fim),
      'visitas_total', (select count(*) from public.link_clicks c
                        where c.origin = p_origem and not public.e_robo(c.user_agent)
                          and c.created_at >= v_ini and c.created_at < v_dia_fim),
      'contas_dia', (select count(*) from auth.users u
                     where u.created_at >= v_dia_ini and u.created_at < v_dia_fim),
      'contas_total', (select count(*) from auth.users u
                       where u.created_at >= v_ini and u.created_at < v_dia_fim),
      'primeiros_dia', (select count(*) from primeiros p
                        where p.em >= v_dia_ini and p.em < v_dia_fim),
      'primeiros_total', (select count(*) from primeiros p
                          where p.em >= v_ini and p.em < v_dia_fim)
    )
  );
end;
$$;

-- Robô com p_chave: aberto a anon de propósito (a VPS só tem a chave pública + a chave do robô).
revoke all on function public.campanha_pago_resumo(text, text, date, date) from public;
grant execute on function public.campanha_pago_resumo(text, text, date, date) to anon, authenticated;
