-- 20261016100000_chave_nova_banco_manda_apikey.sql
-- Missão chave-nova-16-10 (16/10/2026), Bloco 3. APLICAR SÓ DEPOIS do Bloco 2 (as Edge Functions
-- chamadas pelo banco publicadas a aceitar a chave nova — ver docs/CHAVES-2026-10-16.md).
--
-- O que faz, de forma determinística (sem copiar corpos de funções para aqui):
--   1) guarda em public.bkp_fn_chave_legada_20261016 (RLS ligado, sem políticas) a definição actual de
--      cada função do banco que chama Edge Functions com a chave legada, e o comando de cada cron;
--   2) reescreve cada uma: lê a chave de vault.sb_secret_backend (em vez de service_role_key, de um
--      current_setting que não existe, ou de vault.read_secret que não existe) e manda-a em 'apikey'
--      E em 'Authorization: Bearer' — as duas, porque há duas Edge Functions de zona vermelha que a
--      tranca não deixa alterar e que só olham para o Bearer, e o portão aceita a chave nova nos dois
--      cabeçalhos (medido a 16/10);
--   3) os helpers _service_role_key() e _dispatch_jwt() passam a devolver a chave nova;
--   4) os 6 crons que chamam Edge Functions passam a mandar o mesmo.
-- Só muda COMO a chave é lida e enviada; nenhuma regra de negócio é tocada.
-- Provado em rollback a 16/10/2026 (DO ... RAISE): 70 funções + 6 crons sem erro, 70 cópias guardadas.
-- Reverter: recriar cada função com a coluna definicao de bkp_fn_chave_legada_20261016 e, para os
-- crons, cron.alter_job(jobid, command := definicao) nas linhas 'cron:<jobname>'.

create table if not exists public.bkp_fn_chave_legada_20261016 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now());
alter table public.bkp_fn_chave_legada_20261016 enable row level security;
revoke all on public.bkp_fn_chave_legada_20261016 from public, anon, authenticated;

do $$
declare
  r record;
  v_def text; v_novo text; v_cmd text;
  n_ok int := 0; n_cron int := 0;
  v_regex_bearer text := '(''Authorization''\s*,\s*''Bearer ''\s*\|\|\s*)(\(\s*select[^()]*\)|[\w.]+\((?:[^()]|\([^()]*\))*\)|[\w.]+)';
begin
  for r in
    select p.oid, p.proname as nome
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.prosrc ilike '%service_role_key%' or p.prosrc ilike '%_dispatch_jwt(%' or p.prosrc ilike '%_dispatch_service_jwt(%')
      and p.proname not in ('_service_role_key', '_dispatch_jwt', '_dispatch_service_jwt', 'vault_semear_chave_servidor')
    order by p.proname
  loop
    v_def := pg_get_functiondef(r.oid);
    insert into public.bkp_fn_chave_legada_20261016 (nome, definicao) values (r.nome, v_def) on conflict (nome) do nothing;
    v_novo := v_def;
    v_novo := regexp_replace(v_novo, '''service_role_key''', '''sb_secret_backend''', 'g');
    v_novo := regexp_replace(v_novo, 'vault\.read_secret\(''supabase_service_role_key''\)', '(select decrypted_secret from vault.decrypted_secrets where name = ''sb_secret_backend'')', 'g');
    v_novo := regexp_replace(v_novo, 'vault\.read_secret\(''supabase_url''\)', '(select decrypted_secret from vault.decrypted_secrets where name = ''project_url'')', 'g');
    v_novo := regexp_replace(v_novo, 'current_setting\(''app\.settings\.service_role_key'',\s*true\)', '(select decrypted_secret from vault.decrypted_secrets where name = ''sb_secret_backend'')', 'g');
    v_novo := regexp_replace(v_novo, 'current_setting\(''app\.service_role_key'',\s*true\)', '(select decrypted_secret from vault.decrypted_secrets where name = ''sb_secret_backend'')', 'g');
    v_novo := regexp_replace(v_novo, 'current_setting\(''app\.supabase_url'',\s*true\)', '(select decrypted_secret from vault.decrypted_secrets where name = ''project_url'')', 'g');
    v_novo := regexp_replace(v_novo, v_regex_bearer, '''apikey'', \2, \1\2', 'gi');
    if v_novo !~ '''apikey''' or v_novo ~ 'current_setting\(''app\.' or v_novo ~ 'vault\.read_secret\(' then
      raise exception 'chave-nova: transformacao incompleta em %', r.nome;
    end if;
    execute v_novo;
    n_ok := n_ok + 1;
  end loop;

  for r in select jobid, jobname, command from cron.job where command ilike '%functions/v1%' and command ilike '%service_role_key%' loop
    insert into public.bkp_fn_chave_legada_20261016 (nome, definicao) values ('cron:' || r.jobname, r.command) on conflict (nome) do nothing;
    v_cmd := regexp_replace(r.command, '''service_role_key''', '''sb_secret_backend''', 'g');
    v_cmd := regexp_replace(v_cmd, v_regex_bearer, '''apikey'', \2, \1\2', 'gi');
    if v_cmd !~ '''apikey''' then raise exception 'chave-nova: cron % sem apikey', r.jobname; end if;
    perform cron.alter_job(r.jobid, command := v_cmd);
    n_cron := n_cron + 1;
  end loop;

  insert into public.bkp_fn_chave_legada_20261016 (nome, definicao)
    select p.proname, pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('_service_role_key', '_dispatch_jwt')
  on conflict (nome) do nothing;

  raise notice 'chave-nova: % funcoes e % crons reescritos', n_ok, n_cron;
end $$;

-- 3) helpers: passam a devolver a chave nova (nomes mantidos por compatibilidade com quem os chama)
create or replace function public._service_role_key() returns text
language sql stable security definer set search_path to 'public', 'vault' as $$
  select coalesce(nullif(current_setting('app.settings.service_role_key', true), ''),
    (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'sb_secret_backend' limit 1));
$$;

create or replace function public._dispatch_jwt() returns text
language plpgsql stable security definer set search_path to 'public', 'vault' as $$
declare v_jwt text;
begin
  select decrypted_secret into v_jwt from vault.decrypted_secrets where name = 'sb_secret_backend';
  if v_jwt is null then raise exception 'sb_secret_backend_not_in_vault: correr a chaves-semear'; end if;
  return v_jwt;
end $$;
