-- 2026-09-14 (missao painel-admin-limpo): os dois cartoes de cima que ja
-- existiam no painel — "AGORA" (admin_realtime_metrics) e "Reservas hoje"
-- (admin_reservations_today) — contavam pedidos/estafetas de demonstracao e
-- o segundo usava CURRENT_DATE (UTC). Passam a ignorar demo (salvo
-- admin_show_demo_data) e a contar o dia de Lisboa.

CREATE OR REPLACE FUNCTION public.admin_realtime_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pending int;
  v_active int;
  v_drivers_online int;
  v_avg_minutes numeric;
  v_stale int;
  v_now timestamptz := NOW();
  v_demo boolean := public.admin_demo_visible();
BEGIN
  PERFORM public._admin_op_guard();

  SELECT COUNT(*) INTO v_pending
  FROM public.orders o
  WHERE o.status IN ('created', 'preparing', 'callingDriver')
    AND (v_demo OR NOT public.is_demo_order(o));

  SELECT COUNT(*) INTO v_active
  FROM public.orders o
  WHERE o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
    AND (v_demo OR NOT public.is_demo_order(o));

  SELECT COUNT(*) INTO v_drivers_online
  FROM public.drivers d
  WHERE COALESCE(d.is_online, false) = true
    AND (v_demo OR NOT public.is_demo_driver(d.id::text));

  SELECT AVG(EXTRACT(EPOCH FROM (o.delivered_at - o.created_at)) / 60.0)
    INTO v_avg_minutes
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.delivered_at IS NOT NULL
    AND o.delivered_at > v_now - INTERVAL '24 hours'
    AND (v_demo OR NOT public.is_demo_order(o));

  SELECT COUNT(*) INTO v_stale
  FROM public.orders o
  WHERE o.status = 'callingDriver'
    AND o.created_at < v_now - INTERVAL '30 minutes'
    AND (v_demo OR NOT public.is_demo_order(o));

  RETURN JSONB_BUILD_OBJECT(
    'pending_orders', v_pending,
    'active_orders', v_active,
    'drivers_online', v_drivers_online,
    'avg_delivery_min_24h', COALESCE(ROUND(v_avg_minutes::numeric, 1), NULL),
    'stale_pending_count', v_stale,
    'has_stale_order', v_stale > 0,
    'demo_visivel', v_demo,
    'generated_at', v_now
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reservations_today()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_pending int; v_approved int; v_next jsonb; v_demo boolean := public.admin_demo_visible();
  v_day_start timestamptz := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
BEGIN
  PERFORM public._admin_op_guard();
  SELECT
    COUNT(*) FILTER (WHERE status='pending'),
    COUNT(*) FILTER (WHERE status='approved')
  INTO v_pending, v_approved
  FROM public.reservations r
  WHERE r.reserved_for >= v_day_start AND r.reserved_for < v_day_start + interval '1 day'
    AND (v_demo OR NOT (public.is_demo_user(r.client_user_id) OR public.is_demo_restaurant(r.restaurant_id)));

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'reserved_for', reserved_for, 'people', people,
    'status', status, 'restaurant_id', restaurant_id,
    'client_name', client_name
  ) ORDER BY reserved_for ASC), '[]'::jsonb)
  INTO v_next
  FROM (
    SELECT * FROM public.reservations r
    WHERE r.reserved_for >= NOW()
      AND r.status IN ('pending','approved')
      AND (v_demo OR NOT (public.is_demo_user(r.client_user_id) OR public.is_demo_restaurant(r.restaurant_id)))
    ORDER BY r.reserved_for ASC LIMIT 5
  ) t;

  RETURN jsonb_build_object(
    'pending', v_pending,
    'approved', v_approved,
    'next', v_next
  );
END;
$function$;
