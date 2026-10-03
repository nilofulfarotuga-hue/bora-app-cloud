-- 2026-09-21 — CONTAS CLARAS · Bloco C6 · limpeza.
-- Remove as duas funções auxiliares de LEITURA criadas às 08h30 (migration contas_claras_c1_helper_leitura_repo)
-- para o Claude Code puxar por REST o statement exacto das migrations e a definição viva das funções
-- (pg_get_functiondef) e provar que o repo é igual ao servidor. Eram SECURITY DEFINER sem grant a anon/authenticated;
-- cumpriram a missão e saem — nada as chama.
DROP FUNCTION IF EXISTS public._repo_migration_sql(text);
DROP FUNCTION IF EXISTS public._repo_function_def(text);
