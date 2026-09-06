-- ============================================================================
-- GERADO EM 2026-06-23 — AGUARDA APROVAÇÃO DANILO
-- ============================================================================
-- Aplica APENAS após revisão de cada função.
-- NUNCA aplicar driver_convert_tokens sem testar fluxo TVDE completo.
-- Zonas protegidas (orders/wallets/ledger/bora_tokens) NÃO são tocadas aqui.
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ HIGH RISK — funções admin/financeiras executáveis por anon             │
-- └─────────────────────────────────────────────────────────────────────────┘

-- [HIGH] anon pode APAGAR negócios inteiros (restaurantes, lojas, etc.)
REVOKE EXECUTE ON FUNCTION public.admin_delete_business(p_id uuid) FROM anon;

-- [HIGH] anon pode CRIAR/EDITAR negócios (injetar lojas falsas)
REVOKE EXECUTE ON FUNCTION public.admin_upsert_business(p_id uuid, p_name text, p_category text, p_address text, p_lat double precision, p_lng double precision, p_is_visible boolean) FROM anon;

-- [HIGH] anon pode converter tokens de estafeta em dinheiro (ZONA FINANCEIRA)
-- ⚠️ TESTAR fluxo TVDE completo antes de revogar — confirmar que o app
--    nunca chama esta RPC sem autenticação.
REVOKE EXECUTE ON FUNCTION public.driver_convert_tokens(p_amount integer) FROM anon;

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ MEDIUM RISK — funções admin sem autenticação                          │
-- └─────────────────────────────────────────────────────────────────────────┘

-- [MEDIUM] anon pode alterar visibilidade de negócios
REVOKE EXECUTE ON FUNCTION public.admin_set_business_visibility(p_id uuid, p_visible boolean) FROM anon;

-- [MEDIUM] anon pode listar todos os negócios (dados internos)
REVOKE EXECUTE ON FUNCTION public.admin_list_businesses(p_search text, p_limit integer, p_offset integer) FROM anon;

-- [MEDIUM] anon pode aplicar preços Continente em massa
REVOKE EXECUTE ON FUNCTION public.admin_continente_apply_prices() FROM anon;

-- [MEDIUM] anon pode listar preços Continente pendentes
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_list(p_filter text, p_limit integer, p_offset integer) FROM anon;

-- [MEDIUM] anon pode aprovar/rejeitar preços Continente
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_review(p_ids uuid[], p_action text) FROM anon;

-- [MEDIUM] anon pode ver resumo de preços Continente
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_summary() FROM anon;

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ LOW RISK — funções de cliente/errand sem autenticação                  │
-- └─────────────────────────────────────────────────────────────────────────┘

-- [LOW] anon pode responder a aumento de orçamento de errand
REVOKE EXECUTE ON FUNCTION public.client_respond_budget_increase(p_order_id text, p_approve boolean) FROM anon;

-- [LOW] anon pode definir foto de pedido errand
REVOKE EXECUTE ON FUNCTION public.client_set_errand_request_photo(p_order_id text, p_url text) FROM anon;

-- [LOW] anon pode pedir aumento de orçamento de errand
REVOKE EXECUTE ON FUNCTION public.errand_request_budget_increase(p_order_id text, p_new_total_cents integer) FROM anon;

-- [LOW] anon pode enfileirar catálogo errand
REVOKE EXECUTE ON FUNCTION public.fn_enqueue_errand_catalog() FROM anon;

-- [LOW] anon pode pesquisar negócios (pode ser intencional para landing page)
-- ⚠️ Verificar se search_businesses é usado no site público antes de revogar.
REVOKE EXECUTE ON FUNCTION public.search_businesses(p_query text, p_lat double precision, p_lng double precision, p_limit integer) FROM anon;

-- ============================================================================
-- VERIFICAÇÃO PÓS-APLICAÇÃO (correr depois de cada REVOKE):
-- SELECT proname, has_function_privilege('anon', p.oid, 'EXECUTE')
-- FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
-- WHERE n.nspname = 'public' AND p.proname = '<nome_funcao>';
-- ============================================================================
