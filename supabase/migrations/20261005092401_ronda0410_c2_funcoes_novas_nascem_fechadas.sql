-- Ronda 04/10 C.2 (05/10/2026): o "revoke ... in schema public from public" não chega — o Postgres dá
-- EXECUTE a PUBLIC a qualquer função nova por um privilégio global, que só se tira sem "in schema".
-- Efeito: funções novas criadas por postgres deixam de ser chamáveis por anon; authenticated e
-- service_role continuam a receber pelo privilégio por defeito do schema public. Abrir a anon = GRANT explícito.
-- Prova (transacção desfeita): função nova -> anon=f authenticated=t service_role=t.
alter default privileges for role postgres revoke execute on functions from public;
