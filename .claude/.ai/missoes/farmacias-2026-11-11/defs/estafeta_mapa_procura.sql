CREATE OR REPLACE FUNCTION public.estafeta_mapa_procura(p_dias integer DEFAULT 30)
 RETURNS TABLE(hora smallint, lat_celula double precision, lng_celula double precision, pedidos integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_dias integer := greatest(1, least(coalesce(p_dias, 30), 60));
  v_lat_passo constant double precision := 0.0045;
  v_lng_passo constant double precision := 0.0059;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not (
    public.is_admin()
    or exists (select 1 from public.drivers d
                where d.user_id = v_uid
                  and d.approval_status = 'approved'
                  and coalesce(d.is_banned, false) = false)
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select (extract(hour from (o.created_at at time zone 'Europe/Lisbon')))::smallint as hora,
         (floor(coalesce(o.pickup_lat::double precision, r.lat) / v_lat_passo) * v_lat_passo + v_lat_passo / 2) as lat_celula,
         (floor(coalesce(o.pickup_lng::double precision, r.lng) / v_lng_passo) * v_lng_passo + v_lng_passo / 2) as lng_celula,
         count(*)::integer as pedidos
    from public.orders o
    left join public.restaurants r on r.id = o.restaurant_id
   where o.restaurant_id is not null
     and o.created_at >= now() - make_interval(days => v_dias)
     and o.status not in ('cancelled', 'rejected')
     and coalesce(o.pickup_lat::double precision, r.lat) is not null
     and coalesce(o.pickup_lng::double precision, r.lng) is not null
   group by 1, 2, 3
   order by 1, 4 desc;
end;
$function$
;
