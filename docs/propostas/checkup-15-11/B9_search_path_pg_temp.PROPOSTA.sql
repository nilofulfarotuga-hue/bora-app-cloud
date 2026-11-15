-- PROPOSTA (checkup-geral-15-11, nota fora do ambito do Juiz 2 da Claude.ai 19:05). Quem aplica: Claude.ai.
-- 3 funcoes SECURITY DEFINER com search_path = public sem pg_temp (SELECT pg_proc.proconfig 15/11):
-- is_admin(), admin_loja_online_produto_estado(...), admin_loja_online_nicho_da_semana(...).
-- Sem pg_temp explicito no fim, o schema temporario da sessao e procurado PRIMEIRO; com pg_temp no
-- fim, deixa de ser possivel sombrear tabelas/funcoes com objetos temporarios. So muda a configuracao.
alter function public.is_admin() set search_path = public, pg_temp;
alter function public.admin_loja_online_produto_estado(uuid, boolean, boolean, text) set search_path = public, pg_temp;
alter function public.admin_loja_online_nicho_da_semana(uuid, text) set search_path = public, pg_temp;
-- Prova: select proname, proconfig from pg_proc where proname in ('is_admin','admin_loja_online_produto_estado','admin_loja_online_nicho_da_semana');
