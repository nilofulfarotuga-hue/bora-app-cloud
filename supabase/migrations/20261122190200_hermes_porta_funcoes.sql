-- Missão hermes-diretor-2026-11-20 — B4: a porta do Hermes ("abre tudo", com travão só nos valores e no apagar).
-- Só MECANISMO. A lista do que conta como valor NÃO vem neste ficheiro: é um dado (platform_settings,
-- chave hermes_porta_dinheiro), posto e revisto pela Claude.ai e visível no painel. Sem essa semente,
-- a porta fica trancada (tudo o que é escrita pede o autorizo). Depende de 20261122190000 (tabelas).
-- Não mexe em nenhuma zona protegida: só lê o catálogo do Postgres e cria funções novas.

-- ───────────────────────── 1. semente e normalização ─────────────────────────
create or replace function public._hp_semente() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select value from public.platform_settings where key = 'hermes_porta_dinheiro'), '{}'::jsonb)
$$;

create or replace function public._hp_lista(p jsonb, p_chave text, p_defeito text[]) returns text[]
language sql immutable as $$
  select case when jsonb_typeof(p -> p_chave) = 'array'
              then coalesce((select array_agg(x) from jsonb_array_elements_text(p -> p_chave) x), '{}')
              else p_defeito end
$$;

-- Forma única de uma operação (é sobre ela que se calcula a impressão digital da autorização).
create or replace function public._hp_normalizar(p_op jsonb) returns jsonb
language plpgsql immutable as $$
declare t text := lower(coalesce(p_op->>'tipo', ''));
begin
  if t = 'rest' then
    if upper(coalesce(p_op->>'metodo','')) not in ('GET','POST','PATCH','DELETE') then raise exception 'metodo so GET, POST, PATCH ou DELETE'; end if;
    if coalesce(p_op->>'tabela','') !~ '^[a-z_][a-z0-9_]*$' then raise exception 'tabela invalida'; end if;
    return jsonb_build_object('tipo','rest','metodo',upper(p_op->>'metodo'),'tabela',p_op->>'tabela',
                              'query',ltrim(coalesce(p_op->>'query',''),'?'),'corpo',coalesce(p_op->'corpo','null'::jsonb));
  elsif t = 'rpc' then
    if coalesce(p_op->>'funcao','') !~ '^[a-z_][a-z0-9_]*$' then raise exception 'funcao invalida'; end if;
    return jsonb_build_object('tipo','rpc','funcao',p_op->>'funcao','args',coalesce(p_op->'args','{}'::jsonb));
  end if;
  raise exception 'operacao tem de ser do tipo rest ou rpc';
end $$;

create or replace function public._hp_hash(p_op jsonb) returns text
language sql immutable as $$ select encode(sha256(convert_to(public._hp_normalizar(p_op)::text, 'UTF8')), 'hex') $$;

-- ───────────────────────── 2. classificar o esquema ─────────────────────────
create or replace function public.hermes_porta_reclassificar() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s   jsonb := public._hp_semente();
  pt  text := nullif(s->>'padrao_tabelas','');            -- nomes de tabelas de valor
  pf  text := nullif(s->>'padrao_funcoes','');            -- nomes de funções de valor
  pst text := coalesce(nullif(s->>'padrao_segredo_tabelas',''), '^$');
  ctl text[] := public._hp_lista(s, 'tabelas_controlo', '{}');
  opt text[] := public._hp_lista(s, 'tabelas_operacao', array['orders','drivers','tvde_rides','appointments']);
  opf text[] := public._hp_lista(s, 'funcoes_operacao', array['ops_reassign_order','ops_release_order_driver']);
  lvt text[] := public._hp_lista(s, 'tabelas_livres', '{}');
  lvf text[] := public._hp_lista(s, 'funcoes_livres', '{}');
  n int; volta int := 0;
begin
  perform set_config('statement_timeout', '180s', true);
  create temp table if not exists _hp_t (objeto text primary key, classe text, motivo text) on commit drop;
  create temp table if not exists _hp_f (objeto text primary key, classe text, motivo text, src text, vol text) on commit drop;
  truncate _hp_t; truncate _hp_f;

  insert into _hp_t
  select c.relname,
         case when c.relname = 'hermes_porta_tokens' or c.relname ~* pst then 'segredo'
              when c.relname ~ '^(hermes_porta_|hermes_autorizacoes$|hermes_apagados$|admin_audit_log$|schema_migrations$)' or c.relname = any (ctl) then 'controlo'
              when c.relname ~ '^(bkp_|_backup_|backup_|_snapshot_)' then 'controlo'
              when c.relname = any (opt) then 'operacao'
              when c.relname = any (lvt) then 'livre'
              when pt is null then 'dinheiro'
              when c.relname ~* pt then 'dinheiro'
              else 'livre' end,
         case when c.relname = 'hermes_porta_tokens' or c.relname ~* pst then 'guarda senhas ou chaves'
              when c.relname ~ '^(bkp_|_backup_|backup_|_snapshot_)' then 'copia de seguranca: nao se escreve'
              when c.relname = any (opt) then 'pedidos e prestadores: so pelas funcoes de operacao'
              when pt is null then 'sem semente: a porta fica trancada'
              when c.relname ~* pt then 'nome de tabela de valor'
              else null end
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p','v','m');

  insert into _hp_f (objeto, src, vol)
  select p.proname, string_agg(coalesce(p.prosrc,''), E'\n'), max(p.provolatile::text)
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' group by p.proname;

  update _hp_f set classe = 'controlo', motivo = 'gere a porta, as autorizacoes, papeis, agendamentos ou estrutura'
   where objeto ~ '^(hermes_porta_|hermes_autorizac|hermes_apagados|admin_hermes_|_hp_)'
      or src ~* '(cron\.(schedule|unschedule|alter_job)|\mgrant\M|\mrevoke\M|\malter\s+(role|table|policy|function)|\mcreate\s+(role|policy|table)|\mdrop\s+(table|function|policy|role))';
  update _hp_f set classe = 'segredo', motivo = 'le o cofre de segredos' where classe is null and src ~* 'vault\.';
  update _hp_f set classe = 'operacao', motivo = 'funcao de operacao autorizada' where classe is null and objeto = any (opf);
  update _hp_f set classe = 'livre', motivo = 'posta na lista livre' where classe is null and objeto = any (lvf);
  -- valor: pelo nome, por escrever numa tabela de valor ou de operação, por SQL dinâmico/chamada para fora, por contágio
  update _hp_f set classe = 'dinheiro', motivo = case when pf is null then 'sem semente: a porta fica trancada' else 'nome de funcao de valor' end
   where classe is null and vol = 'v' and (pf is null or objeto ~* pf);
  update _hp_f f set classe = 'dinheiro', motivo = 'mexe na tabela ' || t.objeto
    from _hp_t t where f.classe is null and f.vol = 'v' and t.classe in ('dinheiro','operacao') and f.src ~ ('\m' || t.objeto || '\M');
  update _hp_f set classe = 'dinheiro', motivo = 'SQL dinamico ou chamada para fora: na duvida, valor'
   where classe is null and vol = 'v' and src ~* '(\mexecute\s+format|net\.http_|\mhttp_(post|get)\M)';
  loop
    update _hp_f f set classe = 'dinheiro', motivo = 'chama ' || g.objeto
      from _hp_f g where f.classe is null and f.vol = 'v' and g.classe = 'dinheiro' and length(g.objeto) > 5
       and f.src ~ ('\m' || g.objeto || '\s*\(');
    get diagnostics n = row_count; volta := volta + 1;
    exit when n = 0 or volta >= 6;
  end loop;
  update _hp_f set classe = 'livre' where classe is null;
  -- tabela "livre" cujo gatilho mexe em valores passa a valor
  update _hp_t t set classe = 'dinheiro', motivo = 'o gatilho ' || p.proname || ' mexe em valores'
    from pg_trigger tg join pg_class c on c.oid = tg.tgrelid join pg_proc p on p.oid = tg.tgfoid join _hp_f f on f.objeto = p.proname
   where not tg.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = t.objeto
     and t.classe = 'livre' and f.classe = 'dinheiro' and not (t.objeto = any (lvt));

  delete from public.hermes_porta_classes where not manual;
  insert into public.hermes_porta_classes (tipo, objeto, classe, motivo)
  select 'tabela', objeto, classe, motivo from _hp_t
   where not exists (select 1 from public.hermes_porta_classes k where k.tipo = 'tabela' and k.objeto = _hp_t.objeto)
  union all
  select 'funcao', objeto, classe, motivo from _hp_f
   where not exists (select 1 from public.hermes_porta_classes k where k.tipo = 'funcao' and k.objeto = _hp_f.objeto);

  return (select jsonb_object_agg(x.tipo || ':' || x.classe, x.qt) from (select k.tipo, k.classe, count(*) as qt from public.hermes_porta_classes k group by 1, 2) x)
         || jsonb_build_object('com_semente', pt is not null, 'voltas_de_contagio', volta);
end $$;

-- ───────────────────────── 3. autorizações ─────────────────────────
create or replace function public._hp_expirar() returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.hermes_autorizacoes set estado = 'expirada' where estado in ('pendente','autorizada') and expira_em <= now()
$$;

create or replace function public._hp_avisar(p_texto text, p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin   -- sininho + push + Telegram, pelo canal de alertas que já existe; nunca parte quem chama
  if to_regprocedure('public.notify_admin_urgent_push(text,text,text,text,jsonb,text)') is not null then
    execute 'select public.notify_admin_urgent_push($1,$2,$3,$4,$5,$6)'
      using 'hermes_autorizacao', p_texto, 'hermes_autorizacao', p_id::text, jsonb_build_object('autorizacao_id', p_id), '/admin/autorizacoes/' || p_id;
  end if;
exception when others then null;
end $$;

create or replace function public._hp_auditar(p_acao text, p_ref text, p_detalhe jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.admin_audit_log (admin_email, action, entity_type, entity_id_text, details)
  values ('hermes@porta', p_acao, 'hermes_porta', p_ref, coalesce(p_detalhe, '{}'::jsonb));
exception when others then null;
end $$;

create or replace function public.hermes_autorizacao_pedir(p_acao text, p_porque text, p_valor_eur numeric, p_operacao jsonb, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_op jsonb; v_hash text; v_id bigint; v_txt text;
begin
  if coalesce(btrim(p_acao), '') = '' then return jsonb_build_object('ok', false, 'erro', 'falta dizer a acao em portugues simples'); end if;
  begin v_op := public._hp_normalizar(p_operacao); exception when others then return jsonb_build_object('ok', false, 'erro', sqlerrm); end;
  v_hash := public._hp_hash(v_op);
  perform public._hp_expirar();
  select id into v_id from public.hermes_autorizacoes where operacao_hash = v_hash and estado = 'pendente' limit 1;
  if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'estado', 'pendente', 'repetido', true); end if;
  if (select count(*) from public.hermes_autorizacoes where estado = 'pendente') >= 10 then
    return jsonb_build_object('ok', false, 'erro', 'ja ha 10 pedidos a espera do Danilo: nao peco mais ate ele decidir');
  end if;
  insert into public.hermes_autorizacoes (acao, porque, valor_eur, operacao, operacao_hash, teste)
  values (left(btrim(p_acao), 300), left(p_porque, 600), p_valor_eur, v_op, v_hash, coalesce(p_teste, false)) returning id into v_id;
  v_txt := case when coalesce(p_teste, false) then E'TESTE da missão — não precisas de fazer nada\n' else E'O Hermes pede autorização\n' end
        || left(btrim(p_acao), 200) || coalesce(' (' || to_char(p_valor_eur, 'FM999990D00') || ' €)', '')
        || '. Pedido n.º ' || v_id || '. Toca aqui para autorizar, ou diz "autorizo ' || v_id || '" ao Hermes.';
  perform public._hp_avisar(v_txt, v_id);
  perform public._hp_auditar('hermes_autorizacao_pedida', v_id::text, jsonb_build_object('acao', p_acao, 'valor_eur', p_valor_eur, 'operacao', v_op));
  return jsonb_build_object('ok', true, 'id', v_id, 'estado', 'pendente', 'expira_em', now() + interval '30 minutes');
end $$;

-- Decidir (painel, verificador do Telegram, Claude.ai, Claude Code). Nunca chamada pelo Hermes.
create or replace function public.hermes_autorizacao_decidir(p_id bigint, p_decisao text, p_via text, p_quem text, p_texto text default null, p_telegram_message_id bigint default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.hermes_autorizacoes;
begin
  if p_decisao not in ('autorizada','recusada') then return jsonb_build_object('ok', false, 'erro', 'decisao tem de ser autorizada ou recusada'); end if;
  if p_via not in ('painel','telegram','claude-ai','claude-code') then return jsonb_build_object('ok', false, 'erro', 'via desconhecida'); end if;
  if p_decisao = 'autorizada' and p_via <> 'painel' and coalesce(p_texto, '') !~* '\mautorizo\M' then
    return jsonb_build_object('ok', false, 'erro', 'so vale com a palavra "autorizo" do Danilo, tal como ele a disse');
  end if;
  perform public._hp_expirar();
  select * into a from public.hermes_autorizacoes where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'erro', 'pedido nao existe'); end if;
  if a.estado <> 'pendente' then return jsonb_build_object('ok', false, 'estado', a.estado, 'erro', 'este pedido ja esta ' || a.estado); end if;
  update public.hermes_autorizacoes
     set estado = p_decisao, decidida_em = now(), decidida_por = left(p_quem, 120), via = p_via,
         texto_literal = left(p_texto, 500), telegram_message_id = p_telegram_message_id,
         expira_em = case when p_decisao = 'autorizada' then now() + interval '30 minutes' else expira_em end
   where id = p_id;
  perform public._hp_auditar('hermes_autorizacao_' || p_decisao, p_id::text, jsonb_build_object('via', p_via, 'quem', p_quem, 'texto', left(p_texto, 200)));
  if p_decisao = 'autorizada' and p_via <> 'painel' then   -- rasto e segurança: o Danilo fica a saber na hora
    perform public._hp_avisar('Registei o teu autorizo' || E'\n' || 'Para: ' || left(a.acao, 200) || ', às ' || to_char(now() at time zone 'Europe/Lisbon', 'HH24:MI')
            || '. Se não foste tu, responde NÃO ao Hermes ou recusa no painel.', p_id);
  end if;
  return jsonb_build_object('ok', true, 'estado', p_decisao, 'id', p_id);
end $$;

-- "Se não foste tu, responde NÃO": anula um autorizo já dado, enquanto não tiver sido usado.
create or replace function public.hermes_autorizacao_anular(p_id bigint, p_quem text, p_texto text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.hermes_autorizacoes;
begin
  update public.hermes_autorizacoes set estado = 'recusada', decidida_em = now(), decidida_por = left(p_quem, 120),
         resultado = 'anulada depois de autorizada: ' || coalesce(left(p_texto, 200), 'sem texto')
   where id = p_id and estado = 'autorizada' returning * into a;
  if not found then
    select * into a from public.hermes_autorizacoes where id = p_id;
    return jsonb_build_object('ok', false, 'estado', a.estado, 'erro', case when a.estado = 'usada' then 'ja foi usada: nao da para anular' else 'nao estava autorizada' end);
  end if;
  perform public._hp_auditar('hermes_autorizacao_anulada', p_id::text, jsonb_build_object('quem', p_quem, 'texto', left(p_texto, 200)));
  return jsonb_build_object('ok', true, 'estado', 'recusada', 'id', p_id);
end $$;

create or replace function public.admin_hermes_autorizacao_decidir(p_id bigint, p_decisao text, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then return jsonb_build_object('ok', false, 'erro', 'so o administrador'); end if;
  return public.hermes_autorizacao_decidir(p_id, p_decisao, 'painel', coalesce(auth.uid()::text, 'admin'), p_motivo, null);
end $$;

-- Uma autorização = ESTA operação, uma vez, dentro da validade. Atómico.
create or replace function public.hermes_autorizacao_consumir(p_id bigint, p_operacao jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.hermes_autorizacoes; v_hash text := public._hp_hash(p_operacao);
begin
  perform public._hp_expirar();
  update public.hermes_autorizacoes set estado = 'usada', usada_em = now()
   where id = p_id and estado = 'autorizada' and expira_em > now() and operacao_hash = v_hash returning * into a;
  if found then return jsonb_build_object('ok', true, 'id', p_id); end if;
  select * into a from public.hermes_autorizacoes where id = p_id;
  return jsonb_build_object('ok', false, 'erro', case
    when a.id is null then 'autorizacao nao existe'
    when a.estado = 'usada' then 'esta autorizacao ja foi usada (vale uma vez so)'
    when a.estado = 'expirada' then 'esta autorizacao expirou (30 minutos)'
    when a.estado = 'pendente' then 'o Danilo ainda nao autorizou este pedido'
    when a.estado = 'recusada' then 'o Danilo recusou este pedido'
    when a.operacao_hash <> v_hash then 'a operacao nao e a mesma que foi autorizada'
    else 'autorizacao invalida' end);
end $$;

create or replace function public.hermes_autorizacao_resultado(p_id bigint, p_resultado text) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.hermes_autorizacoes set resultado = left(p_resultado, 2000) where id = p_id and estado = 'usada'
$$;

-- ───────────────────────── 4. decidir uma operação ─────────────────────────
create or replace function public.hermes_porta_decidir(p_op jsonb, p_autorizacao_id bigint default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  o jsonb; s jsonb := public._hp_semente();
  pc text := nullif(s->>'padrao_colunas','');     -- colunas de valor em tabelas livres (preço, taxa, ganho…)
  pk text := nullif(s->>'padrao_chaves','');      -- chaves de definições que são valor
  alvo text; metodo text; q text; cls text; mot text; precisa boolean := false; r jsonb; cols text[]; chaves text[];
begin
  begin o := public._hp_normalizar(p_op); exception when others then return jsonb_build_object('permitido', false, 'motivo', sqlerrm); end;
  if o->>'tipo' = 'rest' then
    alvo := o->>'tabela'; metodo := o->>'metodo'; q := coalesce(o->>'query', '');
    select classe, motivo into cls, mot from public.hermes_porta_classes where tipo = 'tabela' and objeto = alvo;
    if cls is null then cls := 'dinheiro'; mot := 'tabela ainda nao classificada: na duvida, trata-se como valor'; end if;
    if cls = 'segredo' then return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'esta tabela guarda senhas ou chaves: a porta nao a abre'); end if;
    if to_regclass(format('public.%I', alvo)) is null then return jsonb_build_object('permitido', false, 'motivo', 'essa tabela nao existe'); end if;
    if metodo = 'GET' then
      -- ler pela porta REST só o que o papel de leitura pode ler INTEIRO; o resto lê-se por sql_ler, coluna a coluna
      if has_table_privilege('hermes_leitor', format('public.%I', alvo), 'SELECT') then return jsonb_build_object('permitido', true, 'classe', cls); end if;
      return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'esta tabela tem colunas reservadas: le com sql_ler, so as colunas que a operacao colunas mostrar');
    end if;
    if cls = 'controlo' then return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'tabela de controlo ou copia de seguranca: so o Danilo ou a Claude.ai'); end if;
    if cls = 'operacao' then return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'pedidos e prestadores so pelas funcoes ops_reassign_order e ops_release_order_driver (regras-operacao-agentes)'); end if;
    if metodo in ('PATCH','DELETE') and q !~ '(^|&)(?!(select|order|limit|offset|on_conflict|columns)=)[a-z_][a-z0-9_.]*=' then
      return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'PATCH e DELETE precisam de filtro (ex.: id=eq.5)');
    end if;
    if metodo = 'DELETE' then precisa := true; mot := 'apagar';
    elsif cls = 'dinheiro' then precisa := true;
    elsif alvo = 'platform_settings' then
      select array_agg(distinct k) into chaves from (
        select (regexp_matches(q, '(?:^|&)key=eq\.([^&]+)', 'g'))[1] as k
        union all select e->>'key' from jsonb_array_elements(case when jsonb_typeof(o->'corpo') = 'array' then o->'corpo' when jsonb_typeof(o->'corpo') = 'object' then jsonb_build_array(o->'corpo') else '[]'::jsonb end) e
      ) x where k is not null;
      if chaves is null then precisa := true; mot := 'definicoes sem chave clara: na duvida, valor';
      elsif exists (select 1 from unnest(chaves) k where k ~ '^hermes_porta_') or exists (select 1 from public.platform_settings ps where ps.key = any (chaves) and coalesce(ps.is_secret, false)) then
        return jsonb_build_object('permitido', false, 'classe', 'controlo', 'motivo', 'definicao de controlo da porta ou segredo: so o Danilo ou a Claude.ai');
      elsif pk is null or exists (select 1 from unnest(chaves) k where k ~* pk) then precisa := true; mot := 'definicao de preco, comissao ou taxa';
      end if;
    elsif pc is not null then
      select array_agg(distinct k) into cols from (
        select jsonb_object_keys(e) k from jsonb_array_elements(case when jsonb_typeof(o->'corpo') = 'array' then o->'corpo' when jsonb_typeof(o->'corpo') = 'object' then jsonb_build_array(o->'corpo') else '[]'::jsonb end) e where jsonb_typeof(e) = 'object') x;
      if exists (select 1 from unnest(coalesce(cols, '{}')) k where k ~* pc) then precisa := true; mot := 'coluna de valor (' || (select string_agg(k, ', ') from unnest(cols) k where k ~* pc) || ')'; end if;
    end if;
  else
    alvo := o->>'funcao';
    select classe, motivo into cls, mot from public.hermes_porta_classes where tipo = 'funcao' and objeto = alvo;
    if cls is null then cls := 'dinheiro'; mot := 'funcao ainda nao classificada: na duvida, trata-se como valor'; end if;
    if cls in ('segredo','controlo') then return jsonb_build_object('permitido', false, 'classe', cls, 'motivo', 'funcao de controlo ou que le segredos: so o Danilo ou a Claude.ai'); end if;
    if cls = 'dinheiro' then precisa := true; end if;
  end if;

  if not precisa then return jsonb_build_object('permitido', true, 'classe', cls); end if;
  if p_autorizacao_id is null then
    return jsonb_build_object('permitido', false, 'precisa_autorizo', true, 'classe', cls,
      'motivo', 'precisa do autorizo do Danilo (' || coalesce(mot, 'valor') || '). Usa pedir_autorizacao com esta mesma operacao e espera.');
  end if;
  r := public.hermes_autorizacao_consumir(p_autorizacao_id, o);
  if (r->>'ok')::boolean then return jsonb_build_object('permitido', true, 'classe', cls, 'autorizacao_id', p_autorizacao_id); end if;
  return jsonb_build_object('permitido', false, 'precisa_autorizo', true, 'classe', cls, 'motivo', r->>'erro');
end $$;

create or replace function public.hermes_apagados_guardar(p_autorizacao_id bigint, p_tabela text, p_linhas jsonb) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  insert into public.hermes_apagados (autorizacao_id, tabela, linha)
  select p_autorizacao_id, p_tabela, e from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) e;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.hermes_porta_auditar(p_acao text, p_ref text, p_detalhe jsonb) returns void
language sql security definer set search_path = public, pg_temp as $$ select public._hp_auditar(p_acao, p_ref, p_detalhe) $$;

-- ───────────────────────── 5. ler tudo (só leitura, com um papel sem acesso a segredos) ─────────────────────────
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'hermes_leitor') then
    begin execute 'create role hermes_leitor nologin bypassrls';
    exception when others then execute 'create role hermes_leitor nologin'; end;   -- sem bypassrls só vê o que a RLS deixar
  end if;
end $$;
grant usage on schema public to hermes_leitor;

-- Vistas seguras para o que não se abre inteiro.
create or replace view public.hermes_platform_settings as
  select key, category, description, updated_at, case when coalesce(is_secret, false) then null else value end as value, coalesce(is_secret, false) as is_secret
    from public.platform_settings;
do $$ begin
  if to_regclass('cron.job') is not null then
    execute $v$create or replace view public.hermes_cron_jobs as
      select jobid, jobname, schedule, active, left(regexp_replace(command, '[A-Za-z0-9_\-]{32,}', '<...>', 'g'), 160) as comando from cron.job$v$;
    execute $v$create or replace view public.hermes_cron_falhas as
      select jobid, status, left(return_message, 300) as mensagem, start_time from cron.job_run_details where status <> 'succeeded'$v$;
  end if;
end $$;

-- Dá ao papel de leitura SELECT em tudo o que não é segredo (tabela inteira, ou só as colunas sem segredo).
create or replace function public.hermes_porta_leitor_sincronizar() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s jsonb := public._hp_semente(); psc text := coalesce(nullif(s->>'padrao_segredo_colunas',''), '^$');
        r record; cols text; n_t int := 0; n_p int := 0; n_s int := 0;
begin
  for r in select c.relname, k.classe from pg_class c left join public.hermes_porta_classes k on k.tipo = 'tabela' and k.objeto = c.relname
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p','v','m') loop
    execute format('revoke all on public.%I from hermes_leitor', r.relname);
    if r.classe is null or r.classe = 'segredo' or r.relname = 'platform_settings' then n_s := n_s + 1; continue; end if;
    select string_agg(quote_ident(a.attname), ', ') into cols from pg_attribute a
     where a.attrelid = ('public.' || quote_ident(r.relname))::regclass and a.attnum > 0 and not a.attisdropped and a.attname !~* psc;
    if cols is null then n_s := n_s + 1; continue; end if;
    if exists (select 1 from pg_attribute a where a.attrelid = ('public.' || quote_ident(r.relname))::regclass and a.attnum > 0 and not a.attisdropped and a.attname ~* psc) then
      execute format('grant select (%s) on public.%I to hermes_leitor', cols, r.relname); n_p := n_p + 1;
    else
      execute format('grant select on public.%I to hermes_leitor', r.relname); n_t := n_t + 1;
    end if;
  end loop;
  return jsonb_build_object('inteiras', n_t, 'so_colunas_sem_segredo', n_p, 'fechadas', n_s);
end $$;

-- SELECT livre, mas: uma instrução só, sem funções de SQL dinâmico, corrida com o papel de leitura.
-- STABLE de propósito: o PostgREST corre funções STABLE em transação só de leitura. O tempo-limite de 8 s
-- é a definição da função (o PostgREST aplica-a à transação).
create or replace function public.hermes_porta_sql_ler(p_sql text, p_limite integer default 200) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp set statement_timeout = '8s' as $$
declare v jsonb; lim integer := least(greatest(coalesce(p_limite, 200), 1), 1000); q text := btrim(rtrim(btrim(coalesce(p_sql, '')), ';'));
begin
  if q !~* '^(select|with)\M' then raise exception 'so leitura: comeca por SELECT ou WITH'; end if;
  if position(';' in q) > 0 then raise exception 'uma instrucao so (sem ponto e virgula)'; end if;
  if q ~* '(\m(query|table|cursor|schema|database)_to_xml|\mdblink|\mpg_read_|\mpg_ls_|\mlo_(import|export|get)|\mcopy\s|\mset_config\M|\mnextval\M|\msetval\M|vault\.|\mpg_sleep)' then
    raise exception 'esta consulta usa uma funcao que a porta nao deixa';
  end if;
  execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from (%s) hp_q limit %s) t', q, lim) into v;
  return jsonb_build_object('ok', true, 'n', jsonb_array_length(v), 'linhas', v);
end $$;

create or replace function public.hermes_porta_colunas(p_tabela text) returns text[]
language sql stable security definer set search_path = public, pg_temp as $$
  select array_agg(a.attname::text order by a.attnum) from pg_attribute a
   where a.attrelid = to_regclass('public.' || quote_ident(p_tabela)) and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('hermes_leitor', a.attrelid, a.attnum, 'SELECT')
$$;

-- A leitura corre com os privilégios do papel de leitura (não com os do dono): é ele o dono da função.
do $$ begin
  begin
    grant hermes_leitor to current_user;
    grant create on schema public to hermes_leitor;
    alter function public.hermes_porta_sql_ler(text, integer) owner to hermes_leitor;
    revoke create on schema public from hermes_leitor;
  exception when others then
    raise warning 'hermes_porta_sql_ler ficou com o dono atual (%); rever com a Claude.ai antes de ligar a leitura livre', sqlerrm;
  end;
end $$;

-- ───────────────────────── 6. quem pode chamar ─────────────────────────
do $$ declare f text; begin
  for f in select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace
            and (p.proname ~ '^(_hp_|hermes_porta_|hermes_autorizacao_|hermes_apagados_)' or p.proname = 'admin_hermes_autorizacao_decidir') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
grant execute on function public.admin_hermes_autorizacao_decidir(bigint, text, text) to authenticated;   -- guarda is_admin() lá dentro
revoke all on public.hermes_platform_settings from anon, authenticated;
grant select on public.hermes_platform_settings to hermes_leitor, service_role;

-- ───────────────────────── 7. manter a classificação fresca ─────────────────────────
do $$ begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'hermes-porta-reclassificar';
    perform cron.schedule('hermes-porta-reclassificar', '10 4 * * *', $c$select public.hermes_porta_reclassificar(); select public.hermes_porta_leitor_sincronizar();$c$);
  end if;
end $$;

-- B7: a marca de arquivado que hoje vive na nota passa para a coluna nova.
update public.agentes_estado set arquivado = true,
       substituto = coalesce(substituto, (regexp_match(nota, 'substituto\s*=\s*([a-z0-9-]+)', 'i'))[1])
 where nota ilike 'ARQUIVADO%' and not arquivado;
