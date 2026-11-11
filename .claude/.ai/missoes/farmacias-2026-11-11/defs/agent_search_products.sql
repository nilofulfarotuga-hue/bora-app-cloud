CREATE OR REPLACE FUNCTION public.agent_search_products(p_query text, p_loja text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_loja text;
  v_res  jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(btrim(COALESCE(p_query, ''))) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o produto'); END IF;
  IF NULLIF(btrim(COALESCE(p_loja, '')), '') IS NOT NULL THEN
    SELECT r.id INTO v_loja FROM public.restaurants r
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
       AND lower(extensions.unaccent(r.name)) LIKE '%' || lower(extensions.unaccent(btrim(p_loja))) || '%'
     ORDER BY length(r.name) LIMIT 1;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', s.name, 'loja', s.restaurant_name,
           'preco_na_app_eur', round(COALESCE(s.display_price, s.price), 2),
           'unidade', s.unit, 'so_maiores_18', COALESCE(s.maior_18, false))), '[]'::jsonb)
    INTO v_res
    FROM public.assistant_search_products(btrim(p_query), v_loja, 8, NULL, false) s;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'produtos', v_res,
    'nota', 'Preços da app. Nos mercados o valor final é o do talão.');
END $function$
;
