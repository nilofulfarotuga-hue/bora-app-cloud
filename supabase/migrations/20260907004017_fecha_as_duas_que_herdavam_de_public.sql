-- 2026-09-07 — sequela da anterior, e prova de que as DUAS regras sao precisas.
-- Depois de revogar de `anon`, duas funcoes continuavam chamaveis por anonimos:
-- nessas a permissao vinha herdada de PUBLIC, e revogar do papel nao apanha o
-- que vem de PUBLIC (PADRAO_BORA 6). Ha portanto dois caminhos de permissao e
-- e preciso fechar os dois — nao basta um.
REVOKE ALL ON FUNCTION public.admin_mark_settlement_paid(text,text,date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_mark_settlement_paid(text,text,date) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_settlement_paid(text,text,date) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_update_weekly_closeout_settings(text,boolean,boolean,jsonb,integer,integer,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_weekly_closeout_settings(text,boolean,boolean,jsonb,integer,integer,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_weekly_closeout_settings(text,boolean,boolean,jsonb,integer,integer,boolean) TO authenticated;

-- A lista de quem deve leva nome, email e telefone la dentro. So o servidor
-- precisa dela (e quem a chama e a Edge dos lembretes); o painel ve a mesma
-- informacao pela admin_weekly_closeout_list, que exige ser administrador.
REVOKE ALL ON FUNCTION public.settlement_debtors(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.settlement_debtors(int) FROM anon;
REVOKE ALL ON FUNCTION public.settlement_debtors(int) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.settlement_debtors(int) TO service_role;;
