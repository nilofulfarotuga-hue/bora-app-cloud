-- B2: Sales summary per partner (7d / 30d / 90d). Returns aggregates +
-- order list. Uses 10+5+5% commission decomposition (BR §2.4):
--   visible 10% partner pays at settlement
--   hidden  5% markup baked into product price
--   service  5% taxa visible to cliente
CREATE OR REPLACE FUNCTION public.admin_partner_sales_summary(
  p_partner_id text,
  p_from timestamptz DEFAULT (NOW() - INTERVAL '30 days'),
  p_to timestamptz DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_orders int;
  v_gross numeric;
  v_visible numeric;
  v_hidden numeric;
  v_service numeric;
  v_total_commission numeric;
  v_partner_net numeric;
  v_orders_json jsonb;
BEGIN
  PERFORM public._admin_op_guard();

  SELECT
    COUNT(*),
    COALESCE(SUM(price), 0),
    COALESCE(SUM(COALESCE(partner_commission_visible, price * 0.10)), 0),
    COALESCE(SUM(COALESCE(partner_markup_hidden, price * 0.05)), 0),
    COALESCE(SUM(COALESCE(partner_service_fee_client, service_fee)), 0)
  INTO v_total_orders, v_gross, v_visible, v_hidden, v_service
  FROM public.orders
  WHERE (vendor_name = p_partner_id
         OR (assigned_driver_id IS NOT NULL AND assigned_driver_id::text = p_partner_id))
    AND status = 'delivered'
    AND created_at >= p_from
    AND created_at < p_to;

  IF v_total_orders = 0 THEN
    SELECT
      COUNT(*),
      COALESCE(SUM(o.price), 0),
      COALESCE(SUM(COALESCE(o.partner_commission_visible, o.price * 0.10)), 0),
      COALESCE(SUM(COALESCE(o.partner_markup_hidden, o.price * 0.05)), 0),
      COALESCE(SUM(COALESCE(o.partner_service_fee_client, o.service_fee)), 0)
    INTO v_total_orders, v_gross, v_visible, v_hidden, v_service
    FROM public.orders o
    JOIN public.restaurants r ON r.name = o.vendor_name
    WHERE r.id::text = p_partner_id
      AND o.status = 'delivered'
      AND o.created_at >= p_from
      AND o.created_at < p_to;
  END IF;

  v_total_commission := v_visible + v_hidden + v_service;
  v_partner_net := v_gross - v_total_commission;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'created_at', o.created_at,
    'status', o.status,
    'price', o.price,
    'customer_name', o.customer_name,
    'service_type', o.service_type,
    'commission_total',
      COALESCE(o.partner_commission_visible, o.price * 0.10) +
      COALESCE(o.partner_markup_hidden, o.price * 0.05) +
      COALESCE(o.partner_service_fee_client, o.service_fee)
  ) ORDER BY o.created_at DESC), '[]'::jsonb)
  INTO v_orders_json
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.name = o.vendor_name
  WHERE (o.vendor_name = p_partner_id OR r.id::text = p_partner_id)
    AND o.status = 'delivered'
    AND o.created_at >= p_from
    AND o.created_at < p_to
  ORDER BY o.created_at DESC
  LIMIT 100;

  RETURN jsonb_build_object(
    'total_orders', v_total_orders,
    'gross_revenue', v_gross,
    'commission_visible_10', v_visible,
    'commission_markup_hidden_5', v_hidden,
    'commission_service_fee_5', v_service,
    'commission_total_20', v_total_commission,
    'partner_net', v_partner_net,
    'period_from', p_from,
    'period_to', p_to,
    'orders', v_orders_json
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_partner_sales_summary(text, timestamptz, timestamptz) TO authenticated;
COMMENT ON FUNCTION public.admin_partner_sales_summary IS
  'Partner sales rollup with 10+5+5% commission decomposition (B2). _admin_op_guard.';
