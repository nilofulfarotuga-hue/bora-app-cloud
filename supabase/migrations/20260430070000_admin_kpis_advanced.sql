-- ============================================================================
-- BORA — Admin KPIs avançado (T13)
-- ============================================================================
-- Extensão ao admin_dashboard_metrics existente:
--   1. admin_kpi_hot_zones        — top zonas por volume de pedidos (geo-buckets)
--   2. admin_kpi_avg_ticket       — ticket médio por janela temporal
--   3. admin_kpi_conversion       — pedidos criados vs entregues vs cancelados
-- ============================================================================

BEGIN;

-- 1. Hot zones: bucketize por (lat,lng) round 2 decimais (~1.1km cell em Portugal)
CREATE OR REPLACE FUNCTION public.admin_kpi_hot_zones(
  p_days_back INT DEFAULT 30,
  p_limit     INT DEFAULT 20
)
RETURNS TABLE (
  cell_lat       NUMERIC,
  cell_lng       NUMERIC,
  order_count    BIGINT,
  total_revenue  NUMERIC,
  avg_distance   NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;
  IF p_limit < 1 OR p_limit > 100 THEN p_limit := 20; END IF;

  RETURN QUERY
  SELECT
    ROUND(o.dropoff_lat::numeric, 2)               AS cell_lat,
    ROUND(o.dropoff_lng::numeric, 2)               AS cell_lng,
    count(*)::BIGINT                               AS order_count,
    ROUND(sum(o.price)::numeric, 2)                AS total_revenue,
    ROUND(avg(o.distance_km)::numeric, 2)          AS avg_distance
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.created_at >= now() - (p_days_back || ' days')::INTERVAL
    AND o.dropoff_lat IS NOT NULL
    AND o.dropoff_lng IS NOT NULL
  GROUP BY 1, 2
  ORDER BY count(*) DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_kpi_hot_zones(INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpi_hot_zones(INT, INT) TO authenticated;


-- 2. Average ticket
CREATE OR REPLACE FUNCTION public.admin_kpi_avg_ticket(
  p_days_back INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin       RECORD;
  v_avg_total   NUMERIC;
  v_avg_partner NUMERIC;
  v_avg_market  NUMERIC;
  v_count       BIGINT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;

  SELECT
    count(*),
    ROUND(avg(price)::numeric, 2),
    ROUND(avg(price) FILTER (WHERE is_partner_store)::numeric, 2),
    ROUND(avg(price) FILTER (WHERE NOT is_partner_store)::numeric, 2)
  INTO v_count, v_avg_total, v_avg_partner, v_avg_market
  FROM public.orders
  WHERE status = 'delivered'
    AND created_at >= now() - (p_days_back || ' days')::INTERVAL;

  RETURN jsonb_build_object(
    'days_back',         p_days_back,
    'order_count',       v_count,
    'avg_ticket_total',  v_avg_total,
    'avg_ticket_partner',v_avg_partner,
    'avg_ticket_market', v_avg_market
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_kpi_avg_ticket(INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpi_avg_ticket(INT) TO authenticated;


-- 3. Conversion funnel
CREATE OR REPLACE FUNCTION public.admin_kpi_conversion(
  p_days_back INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin     RECORD;
  v_created   BIGINT;
  v_delivered BIGINT;
  v_cancelled BIGINT;
  v_rejected  BIGINT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;

  SELECT
    count(*),
    count(*) FILTER (WHERE status = 'delivered'),
    count(*) FILTER (WHERE status = 'cancelled'),
    count(*) FILTER (WHERE status = 'rejected')
  INTO v_created, v_delivered, v_cancelled, v_rejected
  FROM public.orders
  WHERE created_at >= now() - (p_days_back || ' days')::INTERVAL;

  RETURN jsonb_build_object(
    'days_back',           p_days_back,
    'orders_created',      v_created,
    'orders_delivered',    v_delivered,
    'orders_cancelled',    v_cancelled,
    'orders_rejected',     v_rejected,
    'conversion_rate',     CASE WHEN v_created = 0 THEN 0
                                ELSE ROUND(((v_delivered::numeric / v_created) * 100), 2) END,
    'cancel_rate',         CASE WHEN v_created = 0 THEN 0
                                ELSE ROUND(((v_cancelled::numeric / v_created) * 100), 2) END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_kpi_conversion(INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpi_conversion(INT) TO authenticated;


COMMIT;
