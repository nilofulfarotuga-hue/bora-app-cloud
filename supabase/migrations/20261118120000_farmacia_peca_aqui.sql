-- Missão farmacia-peca-aqui-18-11 (Claude Code, 18/11/2026). Sem dinheiro: não mexe em preços,
-- taxas nem pagamentos.
--
-- 1. Adendo 1 (b), caso da Farmácia da Sé: quando a farmácia aceita e o cliente não confirma em
--    10 minutos, o cliente recebe UM lembrete (sininho + push). Até hoje a prescricao_vigiar só
--    lembrava a farmácia. Coluna nova lembrete_cliente_em = "já lembrei, não repito".
--    O aviso usa o tipo 'prescricao_resposta', que a app já sabe abrir (ecrã do estado do pedido),
--    também nas versões antigas.
-- 2. Bloco 3.1: admin_prescricoes_listar devolve também o que o cliente pediu (descricao) e a
--    resposta da farmácia (itens_disponiveis, motivo_texto, volta_a_ter), para a aba
--    "Pedidos especiais (pedido livre)" do painel. Só acrescenta chaves ao jsonb: quem já lê
--    a lista não parte.

alter table public.pedidos_prescricao
  add column if not exists lembrete_cliente_em timestamptz;

comment on column public.pedidos_prescricao.lembrete_cliente_em is
  'Quando o cliente foi lembrado de confirmar um pedido aceite (uma vez só). 18/11/2026.';

create or replace function public.prescricao_vigiar()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_min integer := public._setting_int('pharmacy_prescription_response_minutes', 15);
  r record; n integer := 0;
begin
  for r in select id from public.pedidos_prescricao
            where estado = 'enviado' and lembrete_enviado_em is null
              and created_at <= now() - make_interval(mins => v_min) and expira_em > now()
  loop
    update public.pedidos_prescricao set lembrete_enviado_em = now() where id = r.id;
    perform public._prescricao_avisar(r.id, 'loja', 'prescricao_lembrete', 'Receita à espera de resposta',
      'Um cliente está à espera. Responda se tem ou não tem.');
    n := n + 1;
  end loop;
  for r in select id from public.pedidos_prescricao where estado = 'enviado' and expira_em <= now()
  loop
    update public.pedidos_prescricao set estado = 'expirado' where id = r.id and estado = 'enviado';
    perform public._prescricao_avisar(r.id, 'cliente', 'prescricao_expirada', 'A farmácia não respondeu a tempo',
      'Não foi cobrado nada. Pode enviar outra vez.');
    n := n + 1;
  end loop;
  -- 18/11/2026: aceite há mais de 10 minutos e o cliente ainda não confirmou -> lembrar UMA vez.
  for r in select pp.id, pp.estado, rs.name as farmacia
             from public.pedidos_prescricao pp
             join public.restaurants rs on rs.id = pp.restaurant_id
            where pp.estado in ('aceite', 'aceite_parcial')
              and pp.lembrete_cliente_em is null
              and coalesce(pp.respondido_em, pp.updated_at) <= now() - interval '10 minutes'
              -- pedidos velhos (havia 2 aceites de 13/11 a 18/11) nunca recebem lembrete atrasado.
              and coalesce(pp.respondido_em, pp.updated_at) >= now() - interval '6 hours'
  loop
    update public.pedidos_prescricao set lembrete_cliente_em = now()
     where id = r.id and lembrete_cliente_em is null and estado in ('aceite', 'aceite_parcial');
    if found then
      perform public._prescricao_avisar(r.id, 'cliente', 'prescricao_resposta',
        case when r.estado = 'aceite_parcial'
             then 'A ' || coalesce(r.farmacia, 'farmácia') || ' tem parte do que pediu'
             else 'A ' || coalesce(r.farmacia, 'farmácia') || ' tem o que pediu' end,
        'Falta só confirmar na app para o estafeta ir buscar. Só paga depois de confirmar.');
      n := n + 1;
    end if;
  end loop;
  return n;
end $function$;

create or replace function public.admin_prescricoes_listar(p_estado text default null, p_restaurant_id text default null, p_limite integer default 200)
returns setof jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', pp.id, 'created_at', pp.created_at, 'restaurant_id', pp.restaurant_id, 'loja', r.name,
    'cliente_email', u.email, 'cliente_nome', coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name'),
    'tipo', pp.tipo, 'estado', pp.estado,
    'respondido_por_email', ru.email, 'respondido_em', pp.respondido_em,
    'valor_medicamentos_cents', pp.valor_medicamentos_cents, 'taxa_servico_cents', pp.taxa_servico_cents,
    'total_cents', pp.total_cents, 'metodo_pagamento', pp.metodo_pagamento, 'is_demo', pp.is_demo,
    'motivo_recusa', pp.motivo_recusa, 'expira_em', pp.expira_em, 'confirmado_em', pp.confirmado_em,
    'tem_foto', (pp.receita_foto_path is not null or pp.pedido_foto_path is not null),
    'tem_codigos', (pp.receita_numero is not null),
    'dados_apagados_em', pp.dados_apagados_em,
    -- 18/11/2026: pedidos especiais — o que pediu e o que a farmácia respondeu (nunca a receita).
    'descricao', case when pp.tipo = 'pedido_livre' then pp.descricao end,
    'itens_disponiveis', pp.itens_disponiveis,
    'motivo_texto', pp.motivo_texto,
    'volta_a_ter', pp.volta_a_ter,
    'lembrete_cliente_em', pp.lembrete_cliente_em)
  from public.pedidos_prescricao pp
  join public.restaurants r on r.id = pp.restaurant_id
  left join auth.users u on u.id = pp.user_id
  left join auth.users ru on ru.id = pp.respondido_por
  where (p_estado is null or pp.estado = p_estado)
    and (p_restaurant_id is null or pp.restaurant_id = p_restaurant_id)
  order by pp.created_at desc
  limit greatest(1, least(coalesce(p_limite, 200), 1000));
end $function$;

revoke all on function public.admin_prescricoes_listar(text, text, integer) from public, anon;
grant execute on function public.admin_prescricoes_listar(text, text, integer) to authenticated;
revoke all on function public.prescricao_vigiar() from public, anon, authenticated;
