-- 2026-09-07 — cicatriz do PADRAO_BORA 6, ao contrario.
-- A regra escrita diz que REVOKE tem de ser FROM PUBLIC porque a permissao vem
-- herdada dai. Mas o Supabase tambem tem privilegios por omissao que dao
-- EXECUTE DIRECTO a `anon` em cada funcao nova do schema public — e esses o
-- REVOKE FROM PUBLIC nao apanha. Medido: as funcoes criadas hoje ficaram
-- chamaveis por quem nem sessao tem.
--
-- Nao havia escalada de privilegio (todas comecam por verificar is_admin() e
-- um anonimo nao passa), mas superficie a mais e superficie a menos.
REVOKE EXECUTE ON FUNCTION public.admin_set_settlement_state(text,text,date,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_unmark_settlement(text,text,date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_mark_settlement_paid(text,text,date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_weekly_closeout_settings(text,boolean,boolean,jsonb,integer,integer,boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_weekly_closeout_csv(date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.bora_mbway_para_cobranca() FROM anon;
REVOKE EXECUTE ON FUNCTION public.settlement_subject_user_id(text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.settlement_debtors(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public._settlement_debt_reminders() FROM anon;
REVOKE EXECUTE ON FUNCTION public._settlement_receipts_retry() FROM anon;
REVOKE EXECUTE ON FUNCTION public._refresh_driver_debt_marks() FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_resend_key(text) FROM anon;;
