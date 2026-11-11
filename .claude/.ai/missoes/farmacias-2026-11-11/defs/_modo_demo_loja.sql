CREATE OR REPLACE FUNCTION public._modo_demo_loja(p_rid text, p_uid uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (d->>'restaurant_id') = p_rid
                      and now() >= (d->>'inicio')::timestamptz and now() < (d->>'fim')::timestamptz
                      and (p_uid is null or (d->>'cliente_user_id')::uuid = p_uid)
                     from (select public._modo_demo_def() as d) s where s.d is not null), false) $function$
;
