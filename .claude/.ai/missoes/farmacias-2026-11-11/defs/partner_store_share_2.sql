CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    ELSE public.partner_store_share(p_subtotal)
  END;
$function$
;
