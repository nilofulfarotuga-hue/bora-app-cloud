CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT ROUND(
    p_subtotal
      * (1 - COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings
                        WHERE key = 'partner_visible_commission_pct'), 0.10))
      / (1 + COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings
                        WHERE key = 'partner_hidden_markup_pct'), 0.05))
  , 2);
$function$
;
