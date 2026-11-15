-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115145610); antes não estava em supabase/migrations.
-- No servidor, statements guardou um carregador (copiado abaixo, comentado) que executou a cópia de
-- docs/propostas/painel-admin-15-11/P4_central_robo_suporte.PROPOSTA.sql (commit e1224f14; net._http_response
-- 157757) depois de conferir o sha256 227aeffbd80c7fdc354a0d8935a2e5be7beb6b488aaa8df0787c6f6cf0aca6f8.
-- O texto depois do carregador é byte a byte o que correu.
--
-- >>> carregador gravado em schema_migrations.statements (versão 20261115145610):
-- do $$
-- declare
--   v_sql text;
-- begin
--   select content into v_sql from net._http_response where id = 157757;
--   if v_sql is null or encode(sha256(convert_to(v_sql,'UTF8')),'hex') <> '227aeffbd80c7fdc354a0d8935a2e5be7beb6b488aaa8df0787c6f6cf0aca6f8' then
--     raise exception 'sha256 nao confere ou resposta vazia';
--   end if;
--   execute v_sql;
-- end $$;
-- <<< fim do carregador; a seguir, o que ele executou.

-- PROPOSTA P4 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai.
-- Central do robô do suporte (painel admin): as 5 funções que faltam e 1 coluna nova.
-- Não mexe em dinheiro, pedidos, estafetas, carteiras, tokens nem em regras de acesso (RLS).
--
-- COMO APLICAR
--   O ficheiro inteiro numa só chamada (execute_sql, ou apply_migration com o nome
--   painel_admin_central_robo_suporte). O Postgres corre tudo como um bloco: se uma parte falhar,
--   nada fica feito. Pode correr-se outra vez sem estragar nada.
--   Depois, guardar uma cópia em supabase/migrations/ (regra 5 do AGENTS.md).
--
-- O QUE FALTA E PORQUE O ECRÃ FALHA (conferido só com SELECT a 15/11, entre as 13:30 e as 14:10)
--   O ecrã "Central do robô do suporte" (lib/screens/admin/admin_suporte_central_screen.dart) chamava
--   admin_suporte_conversas, admin_suporte_sem_resposta, admin_suporte_config, admin_suporte_definir e
--   admin_suporte_propor_skill. Nenhuma existe no servidor: a API responde PGRST202 e as abas mostram
--   "Esta parte da central ainda não foi instalada no servidor".
--   Às 14:10 o conserto de CÓDIGO (outro ajudante, ainda a mexer) já pôs a aba Conversas a usar
--   admin_suporte_sessoes e o detalhe a usar admin_suporte_conversa(p_session_id), que existem.
--   As funções 2 a 5 da lista abaixo continuam a ser chamadas pelo ecrã, com estes parâmetros e estas
--   chaves. A função 1 (admin_suporte_conversas) fica porque a missão a pediu: é a única que dá a lista
--   das ferramentas usadas em cada conversa (admin_suporte_sessoes não a tem). Se o ecrã não a voltar
--   a usar, o bloco "2)" do SQL pode ficar de fora sem partir nada.
--   Falta também a coluna support_settings.ferramentas_desligadas (lista de textos). O robô
--   (supabase/functions/support-chatbot/index.ts, linhas 140 e 1141) já a lê como lista e esconde do
--   modelo as ferramentas que lá estiverem. Hoje, sem a coluna, lê "nada desligado"; com a coluna
--   vazia ('{}') faz exatamente o mesmo. Nada muda no robô até alguém desligar uma ferramenta.
--
-- O QUE CADA FUNÇÃO DEVOLVE (todas: só para admin, senão erro admin_required; só a role authenticated
-- as pode chamar, anon não)
--   1. admin_suporte_conversas(p_dias 30, p_limite 100) → lista das conversas com movimento nos
--      últimos p_dias dias (máximo 500), as mais recentes primeiro:
--      {id, quando (início, data com fuso), papel (client/driver/partner), nome, primeira (1.ª pergunta,
--       até 160 letras), mensagens (n.º de falas da pessoa, do robô e da equipe, como em "Conversas ao
--       vivo"), passou_a_equipa (sim/não), ferramentas (lista das consultas que o robô fez)}.
--   2. admin_suporte_sem_resposta(p_dias 30) → lista (máximo 200) das perguntas em que o robô não
--      resolveu: {sessao, quando, papel, pergunta, resposta (a do robô), motivo}. Motivos, em PT-BR:
--      passou à equipe (o robô abriu ticket: support_tickets com esta conversa, mais o WhatsApp ao
--      dono) · disse que passava à equipe, mas não abriu ticket (só ficou o aviso normal de cada
--      mensagem) · disse que não sabia · pediu para falar com uma pessoa · robô fora do ar (falha da
--      IA) · não conseguiu resolver (muitas consultas) · não entendeu a pergunta · ferramenta não
--      autorizada · ficou sem resposta · à espera da equipe.
--      As frases fixas do robô vêm de support-chatbot/index.ts (linhas 1371-1453) e pessoa.ts.
--   3. admin_suporte_config() → {modelo, ferramentas_desligadas[], skills[{nome, modo, ativa}]}.
--   4. admin_suporte_definir(p_tipo, p_nome, p_valor) → {ok, erro}.
--      'modelo': só os 3 do ecrã (gemini-3.5-flash-lite, claude-sonnet-5-5, claude-haiku-5-5), porque
--      um nome errado estraga a reserva do robô (o Gemini, quando o Claude falha) e aí ninguém tem
--      resposta. 'ferramenta' e 'skill': p_valor 'ligar'/'desligar'.
--      Cada mudança fica em admin_audit_log pelo log_admin_action (ações suporte_modelo,
--      suporte_ferramenta, suporte_skill), com o antes e o depois.
--   5. admin_suporte_propor_skill(p_pergunta, p_nome, p_guia) → {ok, id}. Cria uma sugestão pendente em
--      skill_suggestions (origem admin_painel, modo read_only, categoria general) que aparece em
--      "Sugestões de skills" para aprovar. Não liga nada sozinha. O guia fica só com o texto do admin
--      (a pergunta do cliente pode ter dados dele e o guia vai para todas as conversas).
--
-- O QUE NÃO MUDA
--   admin_suporte_conversa(p_session_id uuid) e admin_suporte_sessoes ficam iguais: servem "Conversas ao
--   vivo". Atenção para o ecrã: a conversa devolve um objeto {ok, sessao, cliente, mensagens, pedidos},
--   sem o que cada ferramenta pediu e devolveu (só o nome), e marca a conversa como lida. Isso é
--   CÓDIGO (AUDITORIA.md, S6), não deste ficheiro.
--
-- O QUE ISTO SUBSTITUI
--   Em docs/propostas/PROPOSTA_20261105_robo_suporte_painel_e_skills.md (nunca aplicada) fica superada
--   a parte do painel: a coluna ferramentas_desligadas e estas 5 funções. NÃO se repete o bloco que
--   recriava admin_suporte_conversa com o parâmetro p_sessao: o Postgres recusa mudar o nome de um
--   parâmetro ("cannot change name of input parameter"). O resto dessa proposta NÃO está aqui e continua
--   por aplicar (conferido a 15/11: nada dela está no servidor): o arredondamento em
--   agent_get_my_tokens_history (texto dos tokens), o agent_search_products com o produto em destaque,
--   a cópia bkp_support_skills_20261105 e os textos novos das skills.
--
-- COMO PROVAR DEPOIS: no fim do ficheiro (tudo só leitura).


-- 0) PRÉ-VOO: parar se já houver outra versão destas funções com outros parâmetros (duas versões com
--    o mesmo nome confundem a API: erro PGRST203). A 15/11 não havia nenhuma.
do $prevoo$
declare
  v_conflito text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
    into v_conflito
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_suporte_conversas', 'admin_suporte_sem_resposta', 'admin_suporte_config',
                       'admin_suporte_definir', 'admin_suporte_propor_skill')
     and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' not in (
           'admin_suporte_conversas(p_dias integer, p_limite integer)',
           'admin_suporte_sem_resposta(p_dias integer)',
           'admin_suporte_config()',
           'admin_suporte_definir(p_tipo text, p_nome text, p_valor text)',
           'admin_suporte_propor_skill(p_pergunta text, p_nome text, p_guia text)');
  if v_conflito is not null then
    raise exception 'P4 parado: já existe outra versão destas funções: %', v_conflito;
  end if;
end
$prevoo$;


-- 1) Coluna nova: as ferramentas que o admin desligou (vazia = todas ligadas, como hoje).
alter table public.support_settings
  add column if not exists ferramentas_desligadas text[] not null default '{}'::text[];

comment on column public.support_settings.ferramentas_desligadas is
  'Ferramentas do robô do suporte desligadas no painel (Central do robô). Lida pela Edge Function support-chatbot.';


-- 2) Conversas do robô, com as ferramentas que usou. (Pedida pela missão; o ecrã de 14:10 usa
--    admin_suporte_sessoes no lugar dela. Ver cabeçalho.)
create or replace function public.admin_suporte_conversas(p_dias integer default 30, p_limite integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_dias   integer;
  v_limite integer;
  v_res    jsonb;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  v_dias   := greatest(1, least(coalesce(p_dias, 30), 366));
  v_limite := greatest(1, least(coalesce(p_limite, 100), 500));

  select coalesce(jsonb_agg(x.j order by x.inicio desc nulls last, x.id), '[]'::jsonb)
    into v_res
    from (
      select s.id,
             s.started_at as inicio,
             jsonb_build_object(
               'id', s.id,
               'quando', s.started_at,
               'papel', s.user_role,
               'nome', coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), '—'),
               'primeira', (select left(m.content, 160)
                              from public.support_chatbot_messages m
                             where m.session_id = s.id and m.role = 'user'
                             order by m.created_at, m.id
                             limit 1),
               'mensagens', (select count(*)
                               from public.support_chatbot_messages m
                              where m.session_id = s.id and m.role in ('user', 'assistant', 'admin')),
               'passou_a_equipa', (coalesce(s.escalated, false) or s.mode = 'admin'
                                   or s.admin_assumiu_em is not null),
               'ferramentas', coalesce((
                   select jsonb_agg(f.tool_name order by f.primeiro_uso, f.tool_name)
                     from (select m.tool_name, min(m.created_at) as primeiro_uso
                             from public.support_chatbot_messages m
                            where m.session_id = s.id and m.role = 'tool' and m.tool_name is not null
                            group by m.tool_name) f), '[]'::jsonb)
             ) as j
        from public.support_chatbot_sessions s
        left join public.users u on u.id = s.user_id
       where coalesce(s.ultima_msg_em, s.started_at) >= now() - make_interval(days => v_dias)
         and exists (select 1 from public.support_chatbot_messages m where m.session_id = s.id)
       order by s.started_at desc nulls last, s.id
       limit v_limite
    ) x;

  return v_res;
end;
$function$;

comment on function public.admin_suporte_conversas(integer, integer) is
  'Painel, Central do robô do suporte: conversas recentes com as ferramentas usadas. Só admin.';
revoke all on function public.admin_suporte_conversas(integer, integer) from public, anon;
grant execute on function public.admin_suporte_conversas(integer, integer) to authenticated;


-- 3) Perguntas em que o robô não resolveu (passou à equipe, falhou ou disse que não sabia).
--    Para cada pergunta (fala 'user') olha a 1.ª resposta do robô antes da pergunta seguinte, se
--    respondeu a equipe (fala 'admin') e se o robô abriu aviso (support_tickets desta conversa).
create or replace function public.admin_suporte_sem_resposta(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_dias integer;
  v_res  jsonb;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  v_dias := greatest(1, least(coalesce(p_dias, 30), 366));

  select coalesce(jsonb_agg(jsonb_build_object(
           'sessao', k.session_id,
           'quando', k.created_at,
           'papel', k.user_role,
           'pergunta', left(k.content, 300),
           'resposta', left(k.resposta, 300),
           'motivo', k.motivo) order by k.created_at desc, k.id), '[]'::jsonb)
    into v_res
    from (
      with perguntas as (
        select m.id, m.session_id, m.created_at, m.content, s.user_role, s.mode,
               lead(m.created_at) over (partition by m.session_id order by m.created_at, m.id) as proxima
          from public.support_chatbot_messages m
          join public.support_chatbot_sessions s on s.id = m.session_id
         where m.role = 'user'
           and m.created_at >= now() - make_interval(days => v_dias)
      ), com_resposta as (
        select p.*,
               r.content as resposta,
               exists (select 1 from public.support_chatbot_messages a
                        where a.session_id = p.session_id and a.role = 'admin'
                          and a.created_at >= p.created_at) as equipa_respondeu,
               exists (select 1 from public.support_tickets t
                        where t.session_id = p.session_id
                          and t.created_at >= p.created_at
                          and (p.proxima is null or t.created_at < p.proxima)) as equipa_avisada
          from perguntas p
          left join lateral (
            select m.content
              from public.support_chatbot_messages m
             where m.session_id = p.session_id and m.role = 'assistant'
               and m.created_at >= p.created_at
               and (p.proxima is null or m.created_at < p.proxima)
             order by m.created_at, m.id
             limit 1) r on true
      ), classificadas as (
        select c.*,
          case
            when c.resposta is null and c.equipa_respondeu then null
            when c.resposta is null and c.mode = 'admin' then 'à espera da equipe'
            when c.resposta is null and c.created_at > now() - interval '2 minutes' then null
            when c.resposta is null then 'ficou sem resposta'
            when c.resposta like 'Estou temporariamente indisponivel%' then 'robô fora do ar (falha da IA)'
            when c.resposta like 'Nao consegui resolver%' then 'não conseguiu resolver (muitas consultas)'
            when c.resposta like 'Erro interno: ferramenta nao autorizada%' then 'ferramenta não autorizada'
            when c.resposta like 'Desculpa, nao percebi bem%' then 'não entendeu a pergunta'
            when c.resposta like 'Claro! Para falares com uma pessoa%' then 'pediu para falar com uma pessoa'
            when c.equipa_avisada then 'passou à equipe'
            when c.resposta ~* '(confirm(ar|o|amos)|verific(ar|o|amos)) com a equipa|pass(ar|o|ei|amos)[^.!?]{0,30}equipa|equipa (vai|já|ja) (tratar|responder|ver|confirmar)'
              then 'disse que passava à equipe, mas não abriu ticket'
            when c.resposta ~* 'n(ã|Ã|a)o (sei|consigo (ver|saber|aceder|confirmar|verificar|encontrar)|tenho (acesso|essa informa|informa|resposta|como saber)|posso ajudar)'
              then 'disse que não sabia'
          end as motivo
        from com_resposta c
      )
      select *
        from classificadas
       where motivo is not null
       order by created_at desc, id
       limit 200
    ) k;

  return v_res;
end;
$function$;

comment on function public.admin_suporte_sem_resposta(integer) is
  'Painel, Central do robô do suporte: perguntas que o robô passou à equipe ou não soube responder. Só admin.';
revoke all on function public.admin_suporte_sem_resposta(integer) from public, anon;
grant execute on function public.admin_suporte_sem_resposta(integer) to authenticated;


-- 4) Ajustes do robô: modelo, ferramentas desligadas e skills.
create or replace function public.admin_suporte_config()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_modelo     text;
  v_desligadas text[];
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  select s.gemini_model, s.ferramentas_desligadas
    into v_modelo, v_desligadas
    from public.support_settings s
   where s.id = 1;

  return jsonb_build_object(
    'modelo', v_modelo,
    'ferramentas_desligadas', to_jsonb(coalesce(v_desligadas, '{}'::text[])),
    'skills', coalesce((
        select jsonb_agg(jsonb_build_object('nome', k.skill_name, 'modo', k.mode, 'ativa', k.active)
                         order by k.skill_name)
          from (select skill_name, mode, active
                  from public.support_skills
                 order by skill_name
                 limit 500) k), '[]'::jsonb));
end;
$function$;

comment on function public.admin_suporte_config() is
  'Painel, Central do robô do suporte: modelo, ferramentas desligadas e skills. Só admin.';
revoke all on function public.admin_suporte_config() from public, anon;
grant execute on function public.admin_suporte_config() to authenticated;


-- 5) Mudar um ajuste (com auditoria).
create or replace function public.admin_suporte_definir(p_tipo text, p_nome text, p_valor text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tipo  text;
  v_nome  text;
  v_valor text;
  v_antes text;
  v_lista text[];
  v_skill record;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  v_tipo  := lower(btrim(coalesce(p_tipo, '')));
  v_nome  := btrim(coalesce(p_nome, ''));
  v_valor := btrim(coalesce(p_valor, ''));

  if v_tipo = 'modelo' then
    -- Só os modelos que o robô conhece (support-chatbot: GEMINI_PADRAO; _shared/claude.ts: MODELOS_CLAUDE).
    if v_valor not in ('gemini-3.5-flash-lite', 'claude-sonnet-5-5', 'claude-haiku-5-5') then
      return jsonb_build_object('ok', false, 'erro', 'modelo_invalido');
    end if;
    select s.gemini_model into v_antes from public.support_settings s where s.id = 1 for update;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'configuracao_em_falta');
    end if;
    update public.support_settings set gemini_model = v_valor, updated_at = now() where id = 1;
    perform public.log_admin_action(
      p_action_type => 'suporte_modelo',
      p_entity_type => 'support_settings',
      p_entity_id   => 'gemini_model',
      p_details     => jsonb_build_object('antes', v_antes, 'depois', v_valor));
    return jsonb_build_object('ok', true, 'erro', null);
  end if;

  if v_tipo not in ('ferramenta', 'skill') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;
  if v_valor not in ('ligar', 'desligar') then
    return jsonb_build_object('ok', false, 'erro', 'valor_invalido');
  end if;

  if v_tipo = 'ferramenta' then
    if v_nome !~ '^[a-z][a-z0-9_]{2,79}$' then
      return jsonb_build_object('ok', false, 'erro', 'ferramenta_invalida');
    end if;
    select s.ferramentas_desligadas into v_lista from public.support_settings s where s.id = 1 for update;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'configuracao_em_falta');
    end if;
    update public.support_settings
       set ferramentas_desligadas = case
             when v_valor = 'ligar' then array_remove(coalesce(ferramentas_desligadas, '{}'::text[]), v_nome)
             else array_append(array_remove(coalesce(ferramentas_desligadas, '{}'::text[]), v_nome), v_nome)
           end,
           updated_at = now()
     where id = 1;
    perform public.log_admin_action(
      p_action_type => 'suporte_ferramenta',
      p_entity_type => 'support_settings',
      p_entity_id   => v_nome,
      p_details     => jsonb_build_object('acao', v_valor,
                                          'estava_desligada', v_nome = any(coalesce(v_lista, '{}'::text[]))));
    return jsonb_build_object('ok', true, 'erro', null);
  end if;

  -- v_tipo = 'skill'
  select k.id, k.active, k.mode
    into v_skill
    from public.support_skills k
   where k.skill_name = v_nome
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'skill_nao_encontrada');
  end if;
  update public.support_skills set active = (v_valor = 'ligar'), updated_at = now() where id = v_skill.id;
  perform public.log_admin_action(
    p_action_type => 'suporte_skill',
    p_entity_type => 'support_skills',
    p_entity_id   => v_skill.id::text,
    p_details     => jsonb_build_object('skill', v_nome, 'modo', v_skill.mode,
                                        'antes', v_skill.active, 'depois', (v_valor = 'ligar')));
  return jsonb_build_object('ok', true, 'erro', null);
end;
$function$;

comment on function public.admin_suporte_definir(text, text, text) is
  'Painel, Central do robô do suporte: troca o modelo e liga/desliga ferramentas e skills, com auditoria. Só admin.';
revoke all on function public.admin_suporte_definir(text, text, text) from public, anon;
grant execute on function public.admin_suporte_definir(text, text, text) to authenticated;


-- 6) Propor uma skill (guia de atendimento) a partir de uma pergunta sem resposta.
create or replace function public.admin_suporte_propor_skill(p_pergunta text, p_nome text, p_guia text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_pergunta text;
  v_guia     text;
  v_nome     text;
  v_id       uuid;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  v_pergunta := left(btrim(coalesce(p_pergunta, '')), 1000);
  v_guia     := left(btrim(coalesce(p_guia, '')), 4000);
  -- Nome no formato das skills que já existem (ex.: ORDER_STATUS): maiúsculas, sem acentos,
  -- só letras, números e "_".
  v_nome := upper(btrim(regexp_replace(
              translate(btrim(coalesce(p_nome, '')),
                        'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
                        'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
              '[^A-Za-z0-9]+', '_', 'g'), '_'));

  if length(v_nome) < 3 or length(v_nome) > 80 then
    return jsonb_build_object('ok', false, 'erro', 'nome_invalido');
  end if;
  if length(v_guia) < 10 then
    return jsonb_build_object('ok', false, 'erro', 'guia_obrigatorio');
  end if;
  if exists (select 1 from public.support_skills k where k.skill_name = v_nome) then
    return jsonb_build_object('ok', false, 'erro', 'ja_existe_skill_com_este_nome');
  end if;

  -- Mesmo nome já proposto no painel e ainda pendente: fica o guia novo (não se duplica a proposta).
  update public.skill_suggestions s
     set suggested_playbook_md = v_guia,
         pattern_summary       = left(coalesce(nullif(v_pergunta, ''), v_nome), 200),
         sample_messages       = case when v_pergunta = '' then s.sample_messages
                                      else jsonb_build_array(left(v_pergunta, 500)) end,
         message_count         = case when v_pergunta = '' then s.message_count else 1 end,
         suggested_at          = now()
   where s.id = (select x.id
                   from public.skill_suggestions x
                  where x.status = 'pending'
                    and x.source = 'admin_painel'
                    and x.suggested_skill_name = v_nome
                  order by x.suggested_at desc
                  limit 1)
  returning s.id into v_id;

  if v_id is null then
    insert into public.skill_suggestions (
      status, proposal_type, zone_type, source,
      pattern_summary, sample_messages, message_count,
      suggested_skill_name, suggested_category, suggested_mode,
      suggested_playbook_md, suggested_allowed_tools, gemini_model, admin_notes)
    values (
      'pending', 'new_skill', 'safe', 'admin_painel',
      left(coalesce(nullif(v_pergunta, ''), v_nome), 200),
      case when v_pergunta = '' then '[]'::jsonb else jsonb_build_array(left(v_pergunta, 500)) end,
      case when v_pergunta = '' then 0 else 1 end,
      v_nome, 'general', 'read_only',
      v_guia, '[]'::jsonb, null,
      'Proposta no painel (Central do robô do suporte), a partir de uma pergunta sem resposta.')
    returning id into v_id;
  end if;

  perform public.log_admin_action(
    p_action_type => 'suporte_propor_skill',
    p_entity_type => 'skill_suggestions',
    p_entity_id   => v_id::text,
    p_details     => jsonb_build_object('skill', v_nome));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

comment on function public.admin_suporte_propor_skill(text, text, text) is
  'Painel, Central do robô do suporte: cria uma sugestão de skill pendente (aprova-se em Sugestões de skills). Só admin.';
revoke all on function public.admin_suporte_propor_skill(text, text, text) from public, anon;
grant execute on function public.admin_suporte_propor_skill(text, text, text) to authenticated;


-- 7) A API passa a ver as funções novas já (o Supabase também o faz sozinho).
notify pgrst, 'reload schema';


-- =====================================================================================================
-- PROVA (depois de aplicar; tudo só leitura)
--
-- 1) As 5 funções existem, com porteiro e sem anon; a conversa antiga continua igual:
--    select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef, p.provolatile,
--           has_function_privilege('anon', p.oid, 'execute') as anon_pode,
--           has_function_privilege('authenticated', p.oid, 'execute') as authenticated_pode,
--           position('admin_required' in p.prosrc) > 0 as tem_porteiro
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname like 'admin_suporte_%'
--     order by 1, 2;
--    Esperado: 9 linhas (8 se o bloco 2 ficar de fora). As novas com prosecdef true, anon_pode false,
--    authenticated_pode true e tem_porteiro true. admin_suporte_conversa numa linha só, com
--    "p_session_id uuid".
--
-- 2) A coluna nova, vazia (= tudo ligado, como hoje):
--    select data_type, is_nullable, column_default from information_schema.columns
--     where table_schema = 'public' and table_name = 'support_settings'
--       and column_name = 'ferramentas_desligadas';               -- ARRAY | NO | '{}'::text[]
--    select ferramentas_desligadas from public.support_settings where id = 1;   -- {}
--
-- 3) O porteiro: no SQL do MCP ninguém é admin, por isso isto TEM de falhar com admin_required (42501):
--    select public.admin_suporte_config();
--
-- 4) As 3 leituras como admin, só com contagens (a mesma chamada, as duas linhas juntas; o
--    set_config só vale dentro dela e não grava nada; sem o bloco 2, tirar a coluna "conversas"):
--    select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub',
--             (select id from auth.users where raw_app_meta_data->>'role' = 'admin' limit 1))::text, true);
--    select jsonb_array_length(public.admin_suporte_conversas(30))   as conversas,
--           jsonb_array_length(public.admin_suporte_sem_resposta(30)) as sem_resposta,
--           jsonb_array_length(public.admin_suporte_config()->'skills') as skills,
--           public.admin_suporte_config()->>'modelo'                    as modelo;
--    O miolo destas funções, corrido só com SELECT a 15/11 às 14:08 (Lisboa), dava: conversas 55
--    (8 passaram à equipe, 28 com ferramentas); sem resposta 24 (passou à equipe 9, disse que passava
--    à equipe mas não abriu ticket 9, disse que não sabia 4, pediu para falar com uma pessoa 2);
--    skills 35; modelo gemini-3.5-flash-lite. Os números sobem com cada conversa nova (às 13:50 eram
--    30 conversas e 16 sem resposta).
--
-- 5) No painel, com a conta admin: Central do robô do suporte → as 3 abas carregam. Em Ajustes,
--    desligar e voltar a ligar uma ferramenta; depois:
--    select action, entity_type, entity_id_text, details, created_at from public.admin_audit_log
--     where action like 'suporte_%' order by created_at desc limit 5;
--    select ferramentas_desligadas from public.support_settings where id = 1;   -- volta a {}
--
-- DESFAZER (só se for preciso e com ordem; NÃO correr junto com o resto):
--    drop function if exists public.admin_suporte_conversas(integer, integer);
--    drop function if exists public.admin_suporte_sem_resposta(integer);
--    drop function if exists public.admin_suporte_config();
--    drop function if exists public.admin_suporte_definir(text, text, text);
--    drop function if exists public.admin_suporte_propor_skill(text, text, text);
--    A coluna pode ficar (o robô aceita-a vazia). Tirá-la apaga o que o admin desligou:
--    alter table public.support_settings drop column if exists ferramentas_desligadas;
-- =====================================================================================================
