-- =============================================================================
-- AMIGO BORA v1 (missão m4-amigo-bora-v1-2026-11-08, ordem do Danilo 08/11/2026)
--
-- O assistente do cliente ganha memória por cliente, uma "deixa" no fim das
-- conversas livres e o registo das comparações com a Glovo/Uber.
--
--   1. Definições novas (painel /admin/assistente): personalidade, deixas,
--      modelo pequeno da conversa livre e texto de boas-vindas do Amigo.
--   2. assistant_client_profile — um resumo curto por cliente (JSON), gerado
--      em segundo plano pela Edge Function assistant-profile-refresh.
--      O cliente lê o seu; "Esquecer tudo" limpa e só volta a aprender com o
--      que acontecer DEPOIS (esquecido_em). Nunca guarda dados de pagamento.
--   3. assistant_deixas — cada deixa mostrada/clicada (rotação de 24 h e
--      métricas do painel).
--   4. assistant_comparacoes — o que os clientes compararam com outras apps.
--   5. RPCs: factos do perfil e contexto (só o servidor), esquecer/lembrar e
--      deixa clicada (cliente), visão geral e "ver perfil com motivo" (admin).
--   6. Cron de hora a hora que refresca os perfis (só quem teve pedido
--      entregue ou conversa nova; os outros uma vez por dia).
--   7. A faixa permanente "Novidade: Bora Assistente" sai da home (a entrada
--      passa a ser o botão "Ajuda-me a escolher"); cópia antes de mexer.
--
-- Zona verde: nenhuma escrita em pedidos nem em dinheiro; os pedidos só são
-- LIDOS para o resumo. Idempotente: pode correr duas vezes sem estragar nada.
-- =============================================================================

-- ─── 1. Definições ────────────────────────────────────────────────────────────
insert into public.platform_settings (key, value, description, category)
values
  ('assistant_personality_enabled', 'true'::jsonb,
   'Amigo Bora: tom de amigo, memória por cliente, saudação do costume e deixa. Desligado = assistente de compras simples (o assistente continua ligado).',
   'assistente'),
  ('deixa_promocoes_enabled', 'true'::jsonb,
   'Amigo Bora: no fim de uma conversa livre mostra UMA linha útil (promoção ativa, parceiro novo, tokens a expirar, check-in). Nunca em compras nem no suporte.',
   'assistente'),
  ('assistant_amigo_model', '"claude-haiku-5-5"'::jsonb,
   'Modelo da conversa livre do Amigo Bora (o cesto e as fotos continuam no modelo de sempre).',
   'assistente'),
  ('assistant_amigo_welcome_text', to_jsonb('Sou o Amigo Bora. Sei o que há na Guarda e o que costumas pedir. Pergunta-me o que quiseres.'::text),
   'Texto do cartão de boas-vindas do Amigo Bora na home (2 linhas).',
   'assistente')
on conflict (key) do nothing;

-- Robôs novos no livro de gastos do Claude (ia_gastos) e no porteiro.
update public.platform_settings
   set value = value
     || jsonb_build_object('edge-amigo', jsonb_build_object(
          'nome', 'Amigo Bora (conversa livre do cliente)', 'usar', true,
          'modelo', 'claude-haiku-5-5', 'prioridade', 1))
     || jsonb_build_object('edge-amigo-perfil', jsonb_build_object(
          'nome', 'Amigo Bora (resumo do perfil em segundo plano)', 'usar', true,
          'modelo', 'claude-haiku-5-5', 'prioridade', 3)),
       updated_at = now()
 where key = 'claude_robos'
   and not (value ? 'edge-amigo');

-- ─── 2. Perfil por cliente ────────────────────────────────────────────────────
create table if not exists public.assistant_client_profile (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  perfil        jsonb not null default '{}'::jsonb,
  lembrar       boolean not null default true,
  esquecido_em  timestamptz,
  msgs_lidas_ate timestamptz,
  fonte         text,
  modelo        text,
  custo_usd     numeric not null default 0,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table public.assistant_client_profile is
  'Amigo Bora: resumo curto do cliente (lojas favoritas, hábitos, ticket médio, categorias, restrições ditas em conversa, nome e registo). Gerado pela Edge assistant-profile-refresh. Nunca dados de pagamento.';

alter table public.assistant_client_profile enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_client_profile' and policyname = 'amigo_perfil_proprio') then
    create policy amigo_perfil_proprio on public.assistant_client_profile
      for select to authenticated using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_client_profile' and policyname = 'convidado_so_ve') then
    create policy convidado_so_ve on public.assistant_client_profile
      as restrictive for all to authenticated
      using (not (select public.is_conta_convidado()))
      with check (not (select public.is_conta_convidado()));
  end if;
end $$;

revoke all on public.assistant_client_profile from anon;
grant select on public.assistant_client_profile to authenticated;
grant all on public.assistant_client_profile to service_role;

-- ─── 3. Deixas mostradas / clicadas ───────────────────────────────────────────
create table if not exists public.assistant_deixas (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users(id) on delete set null,
  conversation_id uuid,
  chave           text not null,
  tipo            text not null,
  texto           text not null,
  acao            jsonb,
  mostrada_em     timestamptz not null default now(),
  clicada_em      timestamptz
);
create index if not exists assistant_deixas_user_idx on public.assistant_deixas (user_id, mostrada_em desc);
create index if not exists assistant_deixas_quando_idx on public.assistant_deixas (mostrada_em desc);

alter table public.assistant_deixas enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_deixas' and policyname = 'amigo_deixas_proprias') then
    create policy amigo_deixas_proprias on public.assistant_deixas
      for select to authenticated using (auth.uid() = user_id or public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_deixas' and policyname = 'convidado_so_ve') then
    create policy convidado_so_ve on public.assistant_deixas
      as restrictive for all to authenticated
      using (not (select public.is_conta_convidado()))
      with check (not (select public.is_conta_convidado()));
  end if;
end $$;

revoke all on public.assistant_deixas from anon;
grant select on public.assistant_deixas to authenticated;
grant all on public.assistant_deixas to service_role;

-- ─── 4. Comparações com outras apps ───────────────────────────────────────────
create table if not exists public.assistant_comparacoes (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users(id) on delete set null,
  conversation_id  uuid,
  app              text not null,
  origem           text not null check (origem in ('print', 'escrito')),
  itens            jsonb not null default '[]'::jsonb,
  total_outra_cents integer,
  total_bora_cents  integer,
  diferenca_cents   integer,
  vencedor          text check (vencedor in ('bora', 'outra', 'empate', 'sem_total')),
  loja_bora         text,
  restaurant_id     text,
  cobertura_pct     numeric,
  criado_em         timestamptz not null default now()
);
create index if not exists assistant_comparacoes_quando_idx on public.assistant_comparacoes (criado_em desc);

alter table public.assistant_comparacoes enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_comparacoes' and policyname = 'amigo_comparacoes_ver') then
    create policy amigo_comparacoes_ver on public.assistant_comparacoes
      for select to authenticated using (auth.uid() = user_id or public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'assistant_comparacoes' and policyname = 'convidado_so_ve') then
    create policy convidado_so_ve on public.assistant_comparacoes
      as restrictive for all to authenticated
      using (not (select public.is_conta_convidado()))
      with check (not (select public.is_conta_convidado()));
  end if;
end $$;

revoke all on public.assistant_comparacoes from anon;
grant select on public.assistant_comparacoes to authenticated;
grant all on public.assistant_comparacoes to service_role;

-- ─── 5a. Factos do perfil (só o servidor) ─────────────────────────────────────
-- Tudo calculado aqui a partir dos pedidos ENTREGUES dos últimos 180 dias (e só
-- depois de um "Esquecer tudo"). Horas em Lisboa. Períodos: manhã 5-10h,
-- almoço 11-14h, tarde 15-18h, noite 19-4h. Hábito = mesma loja, mesmo dia da
-- semana e mesmo período pelo menos 2 vezes.
create or replace function public.assistant_amigo_factos(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with corte as (
    select greatest(
             now() - interval '180 days',
             coalesce((select esquecido_em from public.assistant_client_profile where user_id = p_user_id), '-infinity'::timestamptz)
           ) as desde
  ),
  o as (
    select o.id, o.restaurant_id, o.service_type, o.customer_total, o.items, o.created_at,
           coalesce(nullif(o.vendor_name, ''), r.name, o.restaurant_id) as loja,
           (o.created_at at time zone 'Europe/Lisbon') as lx
      from public.orders o
      left join public.restaurants r on r.id = o.restaurant_id
     where o.user_id = p_user_id
       and o.status = 'delivered'
       and o.created_at > (select desde from corte)
  ),
  op as (
    select o.*,
           extract(isodow from lx)::int as dia,
           case
             when extract(hour from lx) between 5 and 10 then 'manha'
             when extract(hour from lx) between 11 and 14 then 'almoco'
             when extract(hour from lx) between 15 and 18 then 'tarde'
             else 'noite'
           end as periodo
      from o
  ),
  habitos as (
    select dia, periodo, restaurant_id, min(loja) as loja, count(*)::int as vezes,
           (array_agg(id order by created_at desc))[1] as ultimo_pedido_id,
           max(created_at) as ultimo
      from op
     where restaurant_id is not null
       and service_type in ('restaurant', 'storeShopping', 'takeaway')
     group by dia, periodo, restaurant_id
    having count(*) >= 2
     order by count(*) desc, max(created_at) desc
     limit 3
  ),
  lojas as (
    select restaurant_id, min(loja) as loja, count(*)::int as pedidos, max(created_at) as ultimo
      from op
     where restaurant_id is not null
     group by restaurant_id
     order by count(*) desc, max(created_at) desc
     limit 3
  ),
  artigos as (
    select trim(i->>'name') as nome, min(op.loja) as loja,
           count(distinct op.id)::int as vezes
      from op, jsonb_array_elements(case when jsonb_typeof(op.items) = 'array' then op.items else '[]'::jsonb end) i
     where coalesce(trim(i->>'name'), '') <> ''
     group by trim(i->>'name')
    having count(distinct op.id) >= 2
     order by count(distinct op.id) desc
     limit 5
  )
  select jsonb_build_object(
    'pedidos_entregues', (select count(*) from op),
    'ultimo_pedido_em', (select to_char(max(lx), 'YYYY-MM-DD') from op),
    'ticket_medio_eur', (select round(avg(customer_total), 2) from op where service_type <> 'errand' and customer_total > 0),
    'categorias', jsonb_build_object(
       'restaurante', (select count(*) from op where service_type in ('restaurant', 'takeaway')),
       'mercado',     (select count(*) from op where service_type = 'storeShopping'),
       'favores',     (select count(*) from op where service_type = 'errand'),
       'limpeza',     (select count(*) from public.cleaning_bookings cb
                         where cb.client_user_id = p_user_id
                           and cb.status not in ('cancelled', 'canceled')
                           and cb.created_at > (select desde from corte))),
    'lojas_favoritas', coalesce((select jsonb_agg(jsonb_build_object('id', restaurant_id, 'nome', loja, 'pedidos', pedidos)) from lojas), '[]'::jsonb),
    'recorrentes', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'loja', loja, 'vezes', vezes)) from artigos), '[]'::jsonb),
    'habitos', coalesce((select jsonb_agg(jsonb_build_object(
        'dia', dia,
        'dia_nome', (array['segunda','terça','quarta','quinta','sexta','sábado','domingo'])[dia],
        'periodo', periodo, 'loja_id', restaurant_id, 'loja', loja, 'vezes', vezes,
        'ultimo_pedido_id', ultimo_pedido_id)) from habitos), '[]'::jsonb)
  );
$$;

revoke all on function public.assistant_amigo_factos(uuid) from public, anon, authenticated;
grant execute on function public.assistant_amigo_factos(uuid) to service_role;

-- ─── 5b. Contexto do Amigo para uma conversa (só o servidor) ──────────────────
-- Perfil (se o cliente deixa lembrar) + últimos 5 pedidos (resumo) + promoções
-- ativas da home + parceiros novos dos últimos 14 dias. Tudo curto: a Edge
-- corta o perfil a ~600 tokens.
create or replace function public.assistant_amigo_contexto(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with p as (
    select coalesce((select lembrar from public.assistant_client_profile where user_id = p_user_id), true) as lembrar,
           coalesce((select perfil from public.assistant_client_profile where user_id = p_user_id), '{}'::jsonb) as perfil,
           (select atualizado_em from public.assistant_client_profile where user_id = p_user_id) as atualizado_em
  )
  select jsonb_build_object(
    'lembrar', (select lembrar from p),
    'perfil', case when (select lembrar from p) then (select perfil from p) else '{}'::jsonb end,
    'perfil_atualizado_em', (select atualizado_em from p),
    'ultimos_pedidos', case when (select lembrar from p) then coalesce((
        select jsonb_agg(x order by x.quando desc) from (
          select o.id as pedido_id,
                 to_char(o.created_at at time zone 'Europe/Lisbon', 'YYYY-MM-DD') as dia,
                 o.created_at as quando,
                 coalesce(nullif(o.vendor_name, ''), o.restaurant_id) as loja,
                 o.restaurant_id as loja_id,
                 o.service_type as tipo,
                 o.status as estado,
                 (select string_agg(trim(i->>'name'), ', ')
                    from (select e as i from jsonb_array_elements(case when jsonb_typeof(o.items) = 'array' then o.items else '[]'::jsonb end) e limit 3) z) as artigos
            from public.orders o
           where o.user_id = p_user_id
             and o.created_at > coalesce((select esquecido_em from public.assistant_client_profile where user_id = p_user_id), '-infinity'::timestamptz)
           order by o.created_at desc
           limit 5) x), '[]'::jsonb)
      else '[]'::jsonb end,
    'promocoes', coalesce((
        select jsonb_agg(jsonb_build_object('id', b.id, 'titulo', b.titulo, 'subtitulo', b.subtitulo,
                                            'tipo_destino', b.tipo_destino, 'destino', b.destino) order by b.ordem)
          from public.home_banners b
         where b.ativo
           and (b.inicio is null or b.inicio <= now())
           and (b.fim is null or b.fim > now())
           and coalesce(b.destino, '') <> 'assistente'), '[]'::jsonb),
    'parceiros_novos', coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.name, 'categoria', r.category))
          from (select * from public.restaurants r
                 where coalesce(r.approved_at, r.created_at) > now() - interval '14 days'
                   and coalesce(r.coming_soon, false) = false
                   and coalesce(r.is_active_admin, true)
                   and coalesce(r.approval_status, 'approved') = 'approved'
                 order by coalesce(r.approved_at, r.created_at) desc
                 limit 5) r), '[]'::jsonb)
  );
$$;

revoke all on function public.assistant_amigo_contexto(uuid) from public, anon, authenticated;
grant execute on function public.assistant_amigo_contexto(uuid) to service_role;

-- ─── 5c. Cliente: esquecer tudo / deixar lembrar / deixa clicada ──────────────
create or replace function public.assistant_amigo_esquecer()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_mem int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  delete from public.assistant_client_memory where user_id = v_uid;
  get diagnostics v_mem = row_count;
  insert into public.assistant_client_profile (user_id, perfil, esquecido_em, msgs_lidas_ate, fonte, atualizado_em)
  values (v_uid, '{}'::jsonb, now(), now(), 'esquecido pelo cliente', now())
  on conflict (user_id) do update
     set perfil = '{}'::jsonb, esquecido_em = now(), msgs_lidas_ate = now(),
         fonte = 'esquecido pelo cliente', atualizado_em = now();
  -- As métricas ficam, mas deixam de apontar para o cliente.
  update public.assistant_deixas set user_id = null where user_id = v_uid;
  update public.assistant_comparacoes set user_id = null where user_id = v_uid;
  return jsonb_build_object('ok', true, 'memorias_apagadas', v_mem);
end;
$$;

create or replace function public.assistant_amigo_lembrar(p_lembrar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  insert into public.assistant_client_profile (user_id, lembrar, atualizado_em)
  values (v_uid, coalesce(p_lembrar, true), now())
  on conflict (user_id) do update set lembrar = coalesce(p_lembrar, true), atualizado_em = now();
  return jsonb_build_object('ok', true, 'lembrar', coalesce(p_lembrar, true));
end;
$$;

create or replace function public.assistant_amigo_deixa_clicada(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  update public.assistant_deixas
     set clicada_em = coalesce(clicada_em, now())
   where id = p_id and user_id = auth.uid();
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n > 0);
end;
$$;

revoke all on function public.assistant_amigo_esquecer() from public, anon;
revoke all on function public.assistant_amigo_lembrar(boolean) from public, anon;
revoke all on function public.assistant_amigo_deixa_clicada(uuid) from public, anon;
grant execute on function public.assistant_amigo_esquecer() to authenticated;
grant execute on function public.assistant_amigo_lembrar(boolean) to authenticated;
grant execute on function public.assistant_amigo_deixa_clicada(uuid) to authenticated;

-- ─── 5d. Painel admin ─────────────────────────────────────────────────────────
create or replace function public.admin_amigo_overview(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)));
  v jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;

  with c as (
    select c.id, c.started_at, c.cost_usd, c.messages_count,
           exists (select 1 from public.assistant_cart_proposals p where p.conversation_id = c.id) as com_carrinho,
           exists (select 1 from public.assistant_cart_proposals p where p.conversation_id = c.id and p.opened_at is not null) as carrinho_aberto,
           exists (select 1 from public.assistant_cart_proposals p where p.conversation_id = c.id and p.order_id is not null) as virou_pedido
      from public.assistant_conversations c
     where c.started_at >= v_desde
       and coalesce(c.messages_count, 0) > 0
  ),
  d as (select * from public.assistant_deixas where mostrada_em >= v_desde),
  k as (select * from public.assistant_comparacoes where criado_em >= v_desde),
  g as (select robo, count(*) as n, sum(custo_usd) as usd
          from public.ia_gastos
         where quando >= v_desde and robo in ('edge-assistente', 'edge-amigo', 'edge-amigo-perfil')
         group by robo)
  select jsonb_build_object(
    'dias', greatest(1, least(coalesce(p_dias, 30), 365)),
    'conversas', (select count(*) from c),
    'conversas_por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', dia, 'n', n) order by dia)
                                     from (select to_char(started_at at time zone 'Europe/Lisbon', 'YYYY-MM-DD') as dia, count(*) as n
                                             from c group by 1) x), '[]'::jsonb),
    'com_carrinho', (select count(*) from c where com_carrinho),
    'carrinho_aberto', (select count(*) from c where carrinho_aberto),
    'virou_pedido', (select count(*) from c where virou_pedido),
    'pct_carrinho', (select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where com_carrinho) / count(*), 1) end from c),
    'custo_total_usd', (select round(coalesce(sum(cost_usd), 0), 4) from c),
    'custo_medio_conversa_usd', (select case when count(*) = 0 then 0 else round(coalesce(sum(cost_usd), 0) / count(*), 5) end from c),
    'gastos_por_robo', coalesce((select jsonb_agg(jsonb_build_object('robo', robo, 'chamadas', n, 'usd', round(usd, 4))) from g), '[]'::jsonb),
    'comparacoes', jsonb_build_object(
       'total', (select count(*) from k),
       'bora_ganhou', (select count(*) from k where vencedor = 'bora'),
       'outra_ganhou', (select count(*) from k where vencedor = 'outra'),
       'empate', (select count(*) from k where vencedor = 'empate'),
       'sem_total', (select count(*) from k where vencedor = 'sem_total'),
       'por_app', coalesce((select jsonb_agg(jsonb_build_object('app', app, 'n', n)) from (select app, count(*) as n from k group by app order by 2 desc) a), '[]'::jsonb),
       'ultimas', coalesce((select jsonb_agg(jsonb_build_object('quando', criado_em, 'app', app, 'origem', origem, 'vencedor', vencedor,
                                                                'diferenca_cents', diferenca_cents, 'loja_bora', loja_bora,
                                                                'artigos', jsonb_array_length(itens)) order by criado_em desc)
                             from (select * from k order by criado_em desc limit 15) u), '[]'::jsonb)),
    'deixas', jsonb_build_object(
       'mostradas', (select count(*) from d),
       'clicadas', (select count(*) from d where clicada_em is not null),
       'por_tipo', coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'mostradas', m, 'clicadas', cl))
                               from (select tipo, count(*) as m, count(*) filter (where clicada_em is not null) as cl from d group by tipo) t), '[]'::jsonb)),
    'perfis', jsonb_build_object(
       'total', (select count(*) from public.assistant_client_profile),
       'com_habitos', (select count(*) from public.assistant_client_profile where jsonb_array_length(coalesce(perfil->'habitos', '[]'::jsonb)) > 0),
       'nao_lembrar', (select count(*) from public.assistant_client_profile where not lembrar),
       'esquecidos', (select count(*) from public.assistant_client_profile where esquecido_em is not null),
       'atualizados_24h', (select count(*) from public.assistant_client_profile where atualizado_em > now() - interval '24 hours')),
    'interruptores', jsonb_build_object(
       'assistant_enabled', (select value from public.platform_settings where key = 'assistant_enabled'),
       'assistant_personality_enabled', (select value from public.platform_settings where key = 'assistant_personality_enabled'),
       'deixa_promocoes_enabled', (select value from public.platform_settings where key = 'deixa_promocoes_enabled'),
       'assistant_amigo_model', (select value from public.platform_settings where key = 'assistant_amigo_model'),
       'assistant_amigo_welcome_text', (select value from public.platform_settings where key = 'assistant_amigo_welcome_text'))
  ) into v;
  return v;
end;
$$;

-- Ver o perfil de UM cliente: só admin, com motivo, e fica na auditoria.
create or replace function public.admin_amigo_ver_perfil(p_email text, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_row public.assistant_client_profile%rowtype;
  v_mem int;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'motivo_obrigatorio: escreve o motivo (mínimo 10 letras)';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'cliente não encontrado');
  end if;
  perform public.log_admin_action('amigo_ver_perfil', 'assistant_client_profile', v_uid::text,
                                  jsonb_build_object('motivo', trim(p_motivo)));
  select * into v_row from public.assistant_client_profile where user_id = v_uid;
  select count(*) into v_mem from public.assistant_client_memory where user_id = v_uid;
  return jsonb_build_object(
    'ok', true,
    'tem_perfil', v_row.user_id is not null,
    'perfil', coalesce(v_row.perfil, '{}'::jsonb),
    'lembrar', coalesce(v_row.lembrar, true),
    'esquecido_em', v_row.esquecido_em,
    'atualizado_em', v_row.atualizado_em,
    'memorias', v_mem);
end;
$$;

revoke all on function public.admin_amigo_overview(integer) from public, anon;
revoke all on function public.admin_amigo_ver_perfil(text, text) from public, anon;
grant execute on function public.admin_amigo_overview(integer) to authenticated;
grant execute on function public.admin_amigo_ver_perfil(text, text) to authenticated;

-- ─── 6. Cron: refrescar perfis de hora a hora ─────────────────────────────────
-- A Edge escolhe sozinha quem precisa (pedido entregue ou conversa nova desde o
-- último resumo; os outros clientes ativos uma vez por dia), no máximo 25 por volta.
select cron.schedule(
  'amigo-bora-perfis',
  '23 * * * *',
  $cron$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
               || '/functions/v1/assistant-profile-refresh',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                 'Content-Type', 'application/json'),
    body    := jsonb_build_object('scheduled', true),
    timeout_milliseconds := 60000
  );
  $cron$
);

-- ─── 7. A faixa permanente do assistente sai da home ──────────────────────────
create table if not exists public.bkp_home_banners_assistente_20261108 as
  select * from public.home_banners where destino = 'assistente';
alter table public.bkp_home_banners_assistente_20261108 enable row level security;

update public.home_banners
   set ativo = false, atualizado_em = now()
 where destino = 'assistente'
   and tipo_destino = 'categoria'
   and ativo;
