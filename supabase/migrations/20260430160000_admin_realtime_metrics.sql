-- D1: Single-call realtime ops dashboard. Replaces 5 separate count/select
-- queries previously done by AdminRealtimeMetricsCard (10s polling).
CREATE OR REPLACE FUNCTION public.admin_realtime_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending int;
  v_active int;
  v_drivers_online int;
  v_avg_minutes numeric;
  v_stale int;
  v_now timestamptz := NOW();
BEGIN
  PERFORM public._admin_op_guard();

  SELECT COUNT(*) INTO v_pending
  FROM public.orders
  WHERE status IN ('created', 'preparing', 'callingDriver');

  SELECT COUNT(*) INTO v_active
  FROM public.orders
  WHERE status IN ('driverAccepted', 'pickedUp', 'onTheWay');

  SELECT COUNT(*) INTO v_drivers_online
  FROM public.drivers
  WHERE COALESCE(is_online, false) = true;

  SELECT AVG(EXTRACT(EPOCH FROM (delivered_at - created_at)) / 60.0)
    INTO v_avg_minutes
  FROM public.orders
  WHERE status = 'delivered'
    AND delivered_at IS NOT NULL
    AND delivered_at > v_now - INTERVAL '24 hours';

  SELECT COUNT(*) INTO v_stale
  FROM public.orders
  WHERE status = 'callingDriver'
    AND created_at < v_now - INTERVAL '30 minutes';

  RETURN JSONB_BUILD_OBJECT(
    'pending_orders', v_pending,
    'active_orders', v_active,
    'drivers_online', v_drivers_online,
    'avg_delivery_min_24h', COALESCE(ROUND(v_avg_minutes::numeric, 1), NULL),
    'stale_pending_count', v_stale,
    'has_stale_order', v_stale > 0,
    'generated_at', v_now
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_realtime_metrics() TO authenticated;
COMMENT ON FUNCTION public.admin_realtime_metrics() IS
  'Single-call realtime ops dashboard (D1). Returns counts + 24h avg delivery + stale alert. SECURITY DEFINER, _admin_op_guard.';
