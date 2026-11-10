-- PROPOSTA URGENTE DE SEGURANÇA (missão fecho-contabilista-2026-11-10, Claude Code, 10/11/2026) — APLICA A CLAUDE.AI.
--
-- O DEFEITO: stripe_extrato_resumo(text,text,text) e stripe_extrato_cruzar_base() são SECURITY DEFINER
-- (dono postgres), têm EXECUTE para "authenticated" e a guarda delas inclui
--     current_user in ('postgres','service_role')
-- Dentro de uma função SECURITY DEFINER o current_user é SEMPRE o dono (postgres), por isso esta condição
-- é sempre verdadeira e qualquer pessoa com sessão na app passa a guarda.
-- PROVA (10/11/2026, produção, só leitura): com "set local role authenticated" e um uid inventado
-- (is_admin()=false), stripe_extrato_resumo('2026-10','2026-10','empresa') devolveu o resumo, e
-- fecho_mensal_prestadores(2026,10) devolveu 2 estafetas com NIF, email e ganhos (essa é corrigida na
-- proposta 01, que a substitui inteira). e2e_log fluxo 'fecho-contabilista-2026-11-10', passo
-- 'achado-seguranca-current-user'.
--
-- A CORREÇÃO: trocar só essa condição por "session_user = 'postgres'" (ligação direta à base: cron, CLI,
-- MCP). O resto de cada guarda (is_admin(), papel service_role) fica igual. Remendo por âncora: se o texto
-- não aparecer exatamente uma vez, pára sem mudar nada. Backup antes em bkp_funcoes_guarda_20261110.
-- Não mexe em dinheiro nem em dados: só quem pode chamar.

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
  v_novo text;
  v_ancora constant text := 'current_user in (''postgres'',''service_role'')';
  v_n int;
begin
  for r in
    select p.oid, p.oid::regprocedure::text as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('stripe_extrato_resumo', 'stripe_extrato_cruzar_base')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
    if v_n <> 1 then
      raise exception 'âncora encontrada % vezes em % (esperado 1): nada mudado', v_n, r.nome;
    end if;
    insert into public.bkp_funcoes_guarda_20261110 (nome, definicao) values (r.nome, v_def)
      on conflict (nome) do nothing;
    v_novo := replace(v_def, v_ancora, 'session_user = ''postgres''');
    execute v_novo;
  end loop;
end $$;

-- Prova depois de aplicar (deve dar erro de permissão nas duas chamadas):
--   set local role authenticated;
--   select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
--   select public.stripe_extrato_resumo('2026-10','2026-10','empresa');   -- esperado: exceção da guarda
--   select public.fecho_mensal_prestadores(2026,10);                     -- esperado: admin_required (proposta 01)
