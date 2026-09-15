-- ============================================================================
-- PROPOSTA — role Postgres READ-ONLY para o Graphify mapear o SCHEMA do Supabase
-- ⚠️ NÃO APLICAR sem o "vai" do Danilo. Isto cria uma role na BD de produção.
-- Projeto Supabase: ojykpzwqrtusfeakzrna
-- ----------------------------------------------------------------------------
-- Porquê uma role dedicada (regra C1 do prompt): NUNCA usar service_role nem
-- qualquer credencial de escrita para isto. Esta role só CONECTA e lê o catálogo.
--
-- Segurança (regra C3 — só metadados, nunca dados de linhas):
--   O graphify --postgres (pg_introspect.py) só consulta information_schema
--   (tables/views/routines/table_constraints/referential_constraints).
--   pg_catalog/information_schema são legíveis por PUBLIC por defeito, por isso
--   basta poder CONECTAR. NÃO se concede SELECT em nenhuma tabela → a role NÃO
--   consegue ler linhas de orders/wallets/ledger_entries/etc.
-- ============================================================================

-- 1) Role de login read-only (troca a password por uma forte, guardada em segredo)
CREATE ROLE graphify_ro LOGIN PASSWORD '<POR_UMA_PASSWORD_FORTE_AQUI>';

-- 2) Só conectar. Sem privilégios de dados. Sem herança de roles.
ALTER ROLE graphify_ro NOINHERIT;
GRANT CONNECT ON DATABASE postgres TO graphify_ro;

-- 3) (Defensivo) Garantir que não recebe SELECT em dados de negócio.
--    NÃO fazer GRANT SELECT em tabelas. Sem grants + RLS, a leitura de linhas é negada.
--    O acesso ao catálogo (nomes de tabela/coluna/FK) mantém-se — é o que o mapa precisa.

-- ----------------------------------------------------------------------------
-- DEPOIS de criada (guardar o DSN FORA do repo, ex.: variável de ambiente):
--   DSN (session mode, 5432):
--     postgresql://graphify_ro:<PASSWORD>@db.ojykpzwqrtusfeakzrna.supabase.co:5432/postgres
--
--   Extração (metadados apenas, junta ao grafo existente):
--     graphify extract . --postgres "postgresql://graphify_ro:<PASSWORD>@db.ojykpzwqrtusfeakzrna.supabase.co:5432/postgres"
--
--   Reverter a role:  DROP ROLE graphify_ro;
-- ----------------------------------------------------------------------------
