-- ============================================================================
-- bora_admin — REFERÊNCIA / DECISÃO (2026-06-23)
-- ============================================================================
-- ⛔ NÃO EXECUTAR um REVOKE de `authenticated` nas funções public.admin_*.
--    O admin panel (Flutter) chama estas RPCs como role `authenticated`.
--    Revogar parte TODOS os ecrãs admin. No Supabase não há role Postgres
--    por-utilizador, logo `GRANT bora_admin TO "uuid"` NÃO tem alvo válido.
--    Detalhe completo: sessions/2026-06-23-bora-admin-role.md
-- ============================================================================

-- ----------------------------------------------------------------------------
-- COMO A SEGURANÇA ADMIN FUNCIONA HOJE (já implementado, sólido)
-- ----------------------------------------------------------------------------
-- As funções admin_* validam o caller internamente via:
--   _admin_op_guard()  -> exige auth.jwt()->'app_metadata'->>'role' = 'admin'
--   is_admin()         -> raw_app_meta_data->>'role'='admin' OU email do Danilo
-- O EXECUTE para `authenticated` é só a porta; o guard interno é a fechadura.

-- ----------------------------------------------------------------------------
-- VERIFICAÇÃO: funções admin_* sem guard interno (candidatas a hardening futuro)
-- ----------------------------------------------------------------------------
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname LIKE 'admin\_%'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%_admin_op_guard%'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%is_admin%'
ORDER BY p.proname;
-- Para cada função listada acima: adicionar no topo do corpo
--   PERFORM public._admin_op_guard();   -- (ou)  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN'; END IF;
-- Isto é defense-in-depth SEM mexer em grants e SEM partir o painel.

-- ----------------------------------------------------------------------------
-- CONCEDER / REMOVER ADMIN (mecanismo correto — claim no JWT, não role Postgres)
-- ----------------------------------------------------------------------------
-- Conceder:
-- UPDATE auth.users
--    SET raw_app_meta_data = COALESCE(raw_app_meta_data,'{}'::jsonb) || '{"role":"admin"}'::jsonb
--  WHERE email = 'EMAIL_DO_ADMIN';
-- Remover:
-- UPDATE auth.users
--    SET raw_app_meta_data = raw_app_meta_data - 'role'
--  WHERE email = 'EMAIL_DO_ADMIN';
-- (efetivo no próximo login/refresh do token)
