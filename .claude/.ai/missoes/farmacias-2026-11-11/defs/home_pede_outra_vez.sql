CREATE OR REPLACE FUNCTION public.home_pede_outra_vez(p_limit integer DEFAULT 8)
 RETURNS TABLE(id text, name text, category text, cuisine_type text, photo_url text, cover_url text, is_partner boolean, coming_soon boolean, ultimo_pedido timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
         coalesce(r.coming_soon,false), max(o.created_at)
  from public.orders o join public.restaurants r on r.id=o.restaurant_id
  where o.user_id = auth.uid() and o.status in ('delivered','completed')
    and r.approval_status='approved' and coalesce(r.is_online,true)
  group by r.id
  order by max(o.created_at) desc
  limit greatest(1, least(p_limit, 20));
$function$
;
