-- APLICADA EM PRODUÇÃO a 21/09/2026 11:21 UTC (Claude Code, missão contas-claras-20260921, bloco C7) — version 20260921112122.
-- Função temporária de LEITURA (pg_get_functiondef) para puxar por REST o corpo vivo da função que cria o pedido e
-- escrever a PROPOSTA sem recopiar SQL à mão. REMOVIDA às 11:28 pela migration 20260921112821. Fica só para o histórico bater.
-- 2026-09-21 — CONTAS CLARAS · C7 — volta a existir, temporariamente, a função de LEITURA que devolve a definição
-- viva de uma função (pg_get_functiondef), para o Claude Code puxar por REST o corpo exacto da função que cria o
-- pedido e escrever a proposta de correcção sem recopiar SQL à mão. Só service_role a pode chamar. Sai no fim do bloco.
CREATE OR REPLACE FUNCTION public._repo_function_def(p_name text)
RETURNS TABLE (proname text, args text, def text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.proname::text, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)
    FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = p_name;
$$;
REVOKE ALL ON FUNCTION public._repo_function_def(text) FROM PUBLIC, anon, authenticated;
