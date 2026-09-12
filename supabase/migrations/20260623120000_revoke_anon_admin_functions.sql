-- ============================================================================
-- REVOKE anon em funções SECURITY DEFINER (HIGH + MEDIUM)
-- Aprovado por Danilo em 2026-06-23
-- ============================================================================
-- 8 funções tinham grant PUBLIC (=X/postgres) que incluía anon por herança.
-- driver_convert_tokens tinha grant explícito para anon.
-- authenticated e service_role mantêm acesso (grants explícitos preservados).
-- LOW risk functions (search_businesses, errand_*, haversine) NÃO tocadas.
-- ============================================================================

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ HIGH — admin/financeiras                                                │
-- └─────────────────────────────────────────────────────────────────────────┘

REVOKE EXECUTE ON FUNCTION public.admin_delete_business(p_id uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_delete_business(p_id uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_upsert_business(
  p_id uuid, p_name text, p_category text, p_address text,
  p_lat double precision, p_lng double precision, p_is_visible boolean
) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_business(
  p_id uuid, p_name text, p_category text, p_address text,
  p_lat double precision, p_lng double precision, p_is_visible boolean
) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.driver_convert_tokens(p_amount integer) FROM anon;

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ MEDIUM — admin sem autenticação                                        │
-- └─────────────────────────────────────────────────────────────────────────┘

REVOKE EXECUTE ON FUNCTION public.admin_set_business_visibility(p_id uuid, p_visible boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_business_visibility(p_id uuid, p_visible boolean) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_list_businesses(p_search text, p_limit integer, p_offset integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_businesses(p_search text, p_limit integer, p_offset integer) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_continente_apply_prices() FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_continente_apply_prices() FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_continente_price_list(p_filter text, p_limit integer, p_offset integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_list(p_filter text, p_limit integer, p_offset integer) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_continente_price_review(p_ids uuid[], p_action text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_review(p_ids uuid[], p_action text) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.admin_continente_price_summary() FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_continente_price_summary() FROM PUBLIC;
