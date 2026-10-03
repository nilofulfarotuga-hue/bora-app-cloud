-- Painel admin — lista de produtos de uma loja, versão 3 (2026-09-18).
-- Igual à v2 mais as colunas da venda ao peso (sold_by_weight,
-- shelf_price_per_kg) e o filtro "produtos vendidos ao peso"
-- (p_only_by_weight, com default — o Flutter antigo que ainda chame a v2
-- continua a funcionar; a v2 fica intacta).

CREATE OR REPLACE FUNCTION public.admin_list_products_by_partner_v3(
  p_restaurant_id text,
  p_search text DEFAULT NULL,
  p_only_inactive boolean DEFAULT false,
  p_only_by_weight boolean DEFAULT false,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id text, name text, description text, price numeric, partner_shelf_price numeric,
  photo_url text, is_available boolean, is_popular boolean, category text,
  category_root text, taxonomy_section text, is_partner boolean, app_markup_pct numeric,
  sold_by_weight boolean, shelf_price_per_kg numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 100; END IF;

  RETURN QUERY
  SELECT p.id, p.name, p.description, p.price, p.partner_shelf_price, p.photo_url,
         p.is_available, COALESCE(p.is_popular, false), p.category, p.category_root,
         p.taxonomy_section, COALESCE(r.is_partner, false), r.app_markup_pct,
         COALESCE(p.sold_by_weight, false), p.shelf_price_per_kg
  FROM public.products p
  LEFT JOIN public.restaurants r ON r.id = p.restaurant_id
  WHERE p.restaurant_id = p_restaurant_id
    AND (p_search IS NULL
         OR p.name ILIKE '%' || p_search || '%'
         OR p.description ILIKE '%' || p_search || '%')
    AND (NOT p_only_inactive OR p.is_available = false)
    AND (NOT p_only_by_weight OR COALESCE(p.sold_by_weight, false))
  ORDER BY p.is_available DESC, p.name
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_products_by_partner_v3(text, text, boolean, boolean, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_products_by_partner_v3(text, text, boolean, boolean, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_products_by_partner_v3(text, text, boolean, boolean, integer, integer) TO authenticated;
