-- 2026-09-07 — a versao de dois argumentos ficou a conviver com a nova de
-- sete. Chamada pelo nome do argumento, as duas davam igual e o servidor
-- respondia com erro de ambiguidade — o painel deixaria de guardar o MB Way.
-- Fica so a nova, que aceita os mesmos dois primeiros argumentos.
DROP FUNCTION IF EXISTS public.admin_update_weekly_closeout_settings(text, boolean);;
