-- Missão fechar-tudo-2026-11-10 (Claude Code, 10/11/2026), adendo 1: varredura das funções SECURITY DEFINER.
--
-- Mesma guarda morta do achado de 10/11 (current_user dentro de SECURITY DEFINER é sempre o dono, postgres),
-- mas aqui NÃO é explorável: estas três funções não têm EXECUTE para authenticated nem anon (só service_role
-- e postgres). Corrige-se na mesma (defesa para o dia em que alguém der permissão por engano):
--     current_user not in ('postgres', 'service_role')   →   session_user <> 'postgres'
-- Quem chama hoje continua a passar: o robô dos embeddings entra com o papel service_role no JWT (a primeira
-- metade da guarda) e o cron/CLI entra ligado como postgres (session_user = 'postgres').
-- Remendo por âncora: se o texto não aparecer exatamente uma vez, pára sem mudar nada. Backup antes.
-- Não mexe em dinheiro nem em dados.

create table if not exists public.bkp_funcoes_guarda_20261110 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_funcoes_guarda_20261110 enable row level security;
revoke all on public.bkp_funcoes_guarda_20261110 from public, anon, authenticated;

do $$
declare
  r record;
  v_def text;
  v_ancora constant text := 'current_user not in (''postgres'', ''service_role'')';
  v_n int;
  v_total int := 0;
begin
  for r in
    select p.oid, p.oid::regprocedure::text as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('assistant_set_embeddings', 'assistant_set_embeddings_gte', 'knowledge_set_embeddings_gte')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
    if v_n <> 1 then
      raise exception 'âncora encontrada % vezes em % (esperado 1): nada mudado', v_n, r.nome;
    end if;
    insert into public.bkp_funcoes_guarda_20261110 (nome, definicao) values (r.nome, v_def)
      on conflict (nome) do nothing;
    execute replace(v_def, v_ancora, 'session_user <> ''postgres''');
    v_total := v_total + 1;
  end loop;
  if v_total <> 3 then
    raise exception 'esperava 3 funções, encontrei %', v_total;
  end if;
end $$;

-- Prova depois de aplicar:
--   select p.proname, pg_get_functiondef(p.oid) ~ 'current_user' as ainda_tem_current_user,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_pode
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('assistant_set_embeddings','assistant_set_embeddings_gte','knowledge_set_embeddings_gte');
--   → ainda_tem_current_user = false e authenticated_pode = false nas três.
