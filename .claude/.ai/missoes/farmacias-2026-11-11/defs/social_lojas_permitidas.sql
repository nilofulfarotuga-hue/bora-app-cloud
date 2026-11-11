CREATE OR REPLACE FUNCTION public.social_lojas_permitidas()
 RETURNS TABLE(id text, nome text, tipo text, categoria text, is_partner boolean, produtos_disponiveis bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id::text,
         r.name,
         'restaurant'::text,
         r.category::text,
         coalesce(r.is_partner, false),
         (select count(*) from public.products p
           where p.restaurant_id = r.id and coalesce(p.is_available, true))
    from public.restaurants r
   where coalesce(r.coming_soon, false) = false
     and coalesce(r.is_active_admin, true) = true
     and r.approval_status = 'approved'
     and r.id::text not like 'demo-%'
     and r.name not ilike '%demo%'
     and exists (select 1 from public.products p
                  where p.restaurant_id = r.id and coalesce(p.is_available, true))
  union all
  select s.id::text,
         s.name,
         'service_provider'::text,
         null::text,
         true,
         0::bigint
    from public.service_providers s
   where coalesce(s.coming_soon, false) = false
     and coalesce(s.is_active_admin, true) = true
     and s.approval_status = 'approved'
     and s.name not ilike '%demo%'
  order by 3, 2;
$function$
;
