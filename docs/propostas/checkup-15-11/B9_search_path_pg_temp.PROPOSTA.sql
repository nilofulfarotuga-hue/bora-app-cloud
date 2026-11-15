-- PROPOSTA (checkup-geral-15-11, nota fora do ambito do Juiz 2 da Claude.ai 19:05). Quem aplica: Claude.ai.
-- Juiz da B9 (15/11): APROVADO COM CONSERTOS (feitos aqui: prova sem ambiguidade, lock_timeout, migracao no repo).
-- 3 funcoes SECURITY DEFINER com search_path = public sem pg_temp (SELECT pg_proc.proconfig 15/11):
-- is_admin(), admin_loja_online_produto_estado(...), admin_loja_online_nicho_da_semana(...).
-- Sem pg_temp explicito no fim, o schema temporario da sessao e procurado PRIMEIRO; com pg_temp no
-- fim, deixa de ser possivel sombrear tabelas/funcoes com objetos temporarios. So muda a configuracao.
-- is_admin de PRODUCAO conferido a 15/11 (pg_get_functiondef): so usa auth.uid() e auth.users com nome
-- qualificado, por isso public, pg_temp chega.
-- Depois de aplicar: gravar este texto em supabase/migrations/<timestamp>_search_path_pg_temp.sql.
set local lock_timeout = '5s';
alter function public.is_admin() set search_path = public, pg_temp;
alter function public.admin_loja_online_produto_estado(uuid, boolean, boolean, text) set search_path = public, pg_temp;
alter function public.admin_loja_online_nicho_da_semana(uuid, text) set search_path = public, pg_temp;
-- Prova (sem ambiguidade de overloads):
-- select oid::regprocedure, prosecdef, proconfig from pg_proc where oid in (
--   'public.is_admin()'::regprocedure,
--   'public.admin_loja_online_produto_estado(uuid,boolean,boolean,text)'::regprocedure,
--   'public.admin_loja_online_nicho_da_semana(uuid,text)'::regprocedure);
-- Esperado: 3 linhas, prosecdef = true, proconfig = {"search_path=public, pg_temp"}.
