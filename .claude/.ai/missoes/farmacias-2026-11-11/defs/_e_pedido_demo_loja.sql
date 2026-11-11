CREATE OR REPLACE FUNCTION public._e_pedido_demo_loja(p_order_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.orders o, (select public._modo_demo_def() as d) s
                  where o.id = p_order_id and coalesce(o.is_test_order, false) and s.d is not null
                    and o.restaurant_id = s.d->>'restaurant_id' and o.user_id = (s.d->>'cliente_user_id')::uuid) $function$
;
