-- APLICADA EM PRODUÇÃO a 21/09/2026 08:45 UTC (Claude Code, missão contas-claras-20260921) — version 20260921084507.
-- Duas funções de LEITURA, temporárias, para o repo se pôr igual ao servidor sem recopiar SQL à mão
-- (só service_role as podia chamar). REMOVIDAS no fim da missão pela migration
-- 20260921094845_contas_claras_c6_remove_helper_leitura_repo_2026_09_21. Fica aqui só para o histórico bater.
-- 2026-09-21 — CONTAS CLARAS · C1 — duas funções de LEITURA para o repo se pôr igual ao servidor
-- sem recopiar SQL à mão (só service_role as pode chamar; removidas no fim da missão).
CREATE OR REPLACE FUNCTION public._repo_migration_sql(p_version text)
RETURNS TABLE (version text, name text, sql text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT m.version, m.name, array_to_string(m.statements, E'\n')
    FROM supabase_migrations.schema_migrations m WHERE m.version = p_version;
$$;
REVOKE ALL ON FUNCTION public._repo_migration_sql(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._repo_function_def(p_name text)
RETURNS TABLE (proname text, args text, def text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.proname::text, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)
    FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = p_name;
$$;
REVOKE ALL ON FUNCTION public._repo_function_def(text) FROM PUBLIC, anon, authenticated;
