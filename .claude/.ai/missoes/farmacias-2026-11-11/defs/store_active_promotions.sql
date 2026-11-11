CREATE OR REPLACE FUNCTION public.store_active_promotions(p_restaurant_id text)
 RETURNS TABLE(product_id text, price numeric, discount_price numeric, starts_at timestamp with time zone, ends_at timestamp with time zone, lowest_price_30d numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id,
         p.price::numeric,
         p.discount_price::numeric,
         p.discount_starts_at,
         p.discount_ends_at,
         public.product_lowest_price_30d(p.id)
    from public.products p
   where p.restaurant_id = p_restaurant_id
     and public._promotions_enabled()
     and public._promotions_server_ready()
     and not coalesce(p.sold_by_weight, false)
     and public.product_promo_active(
           p.price::numeric, p.discount_price::numeric, p.discount_enabled,
           p.discount_starts_at, p.discount_ends_at, now());
$function$
;
