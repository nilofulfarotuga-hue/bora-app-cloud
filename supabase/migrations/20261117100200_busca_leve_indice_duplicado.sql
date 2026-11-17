-- Missão servidor-busca-leve-2026-11-17, bloco B1 (1.5). APLICA A CLAUDE.AI.
--
-- products tinha dois índices de trigramas IGUAIS (lido em pg_indexes a 17/11):
--   idx_products_search_trgm  = CREATE INDEX ... USING gin (search_normalized gin_trgm_ops)
--   products_search_trgm_idx  = CREATE INDEX ... USING gin (search_normalized gin_trgm_ops)
-- Cada escrita num produto paga os dois. Os planos da pesquisa usam o products_search_trgm_idx
-- (visto no EXPLAIN de "frango"); sai o outro.
--
-- O ideal é DROP INDEX CONCURRENTLY (não bloqueia as leituras), mas não corre dentro de uma
-- transação e as migrações correm numa. Por isso: correr À PARTE, fora de transação, pelo
-- execute_sql:  drop index concurrently if exists public.idx_products_search_trgm;
-- Se for aplicada como migração normal, corre a versão abaixo: espera no máximo 3 s pelo cadeado
-- (com lock_timeout falha em vez de pôr a fila toda à espera) e o DROP em si é instantâneo.
set local lock_timeout = '3s';
drop index if exists public.idx_products_search_trgm;
