CREATE OR REPLACE FUNCTION public.home_mais_pedidos(p_limit integer DEFAULT 10)
 RETURNS TABLE(id text, name text, category text, cuisine_type text, photo_url text, cover_url text, is_partner boolean, coming_soon boolean, pedidos_30d bigint, avg_rating numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
         coalesce(r.coming_soon,false),
         (select count(*) from public.orders o where o.restaurant_id=r.id
            and o.status in ('delivered','completed') and o.created_at > now() - interval '30 days'),
         r.avg_rating
  from public.restaurants r
  where r.approval_status='approved' and coalesce(r.is_online,true) and coalesce(r.is_active_admin,true)
    and coalesce(r.coming_soon,false)=false and r.category in ('restaurant','festas')
  order by 9 desc, r.avg_rating desc nulls last, r.created_at desc
  limit greatest(1, least(p_limit, 30));
$function$
;
