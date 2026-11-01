-- PROPOSTA (não aplicar às cegas) — 01/11/2026, missão seguranca-05, achado pelo caminho.
--
-- e2e_log tem a política e2e_log_select_any (SELECT, {anon, authenticated}, qual = true):
-- 5.943 linhas do registo de operação (ids de pedidos, erros do servidor, nomes de funções,
-- tentativas bloqueadas) legíveis por QUALQUER anónimo em /rest/v1/e2e_log. A escrita (insert)
-- por anon/authenticated tem de ficar (a app, o porteiro do Telegram e os gatilhos escrevem lá).
--
-- Quem LÊ (levantamento 01/11): Claude.ai pelo MCP (postgres), scripts/e2e (chave de servidor),
-- o painel por RPCs definer. Nem lib/ nem web/ nem ferramentas/ fazem SELECT direto com a chave
-- pública. O que NÃO consigo ver daqui: o Hermes na VPS (repo próprio) — se ler e2e_log com a chave
-- pública, parte. Por isso é PROPOSTA: confirmar no Hermes (grep "e2e_log" nos scripts da VPS) e só
-- depois aplicar. Voltar atrás: create policy e2e_log_select_any on public.e2e_log for select
-- to anon, authenticated using (true);
--
-- Idempotente.

do $mig$
begin
  if exists (select 1 from pg_policies where schemaname='public' and tablename='e2e_log' and policyname='e2e_log_select_any') then
    alter policy e2e_log_select_any on public.e2e_log using (public.is_admin());
  end if;
end
$mig$;

-- PROVA:
--   select policyname, roles::text, qual from pg_policies where schemaname='public' and tablename='e2e_log';
--   -- esperado: e2e_log_select_any → qual = is_admin() ; e2e_log_insert_any continua with_check = true
--   begin; set local role anon; select count(*) from public.e2e_log; rollback;   -- esperado: 0
