-- BUG 5: Sync settlement RPCs in Git with prod state.
--
-- Two divergences detected vs 20260502080000_driver_weekly_settlements.sql:
--
-- 1. compute_driver_settlement: prod allows v_caller IS NULL (cron / superuser
--    context under SECURITY DEFINER). Git raised 'unauthenticated'.
-- 2. list_driver_orders_in_week: prod returns column `cash_received`; git
--    returned `cash_adjust_due`.
--
-- Zero functional changes vs current prod — this migration is a pure snapshot
-- so future devs deploying from a clean DB land on the prod-equivalent code.

CREATE OR REPLACE FUNCTION public.compute_driver_settlement(
  p_driver_id uuid,
  p_week_start timestamptz DEFAULT NULL,
  p_persist boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
  v_total_deliveries INT := 0;
  v_total_earnings NUMERIC := 0;
  v_total_cash_received NUMERIC := 0;
  v_total_card_orders NUMERIC := 0;
  v_cash_adjustments_due NUMERIC := 0;
  v_tokens_converted_value NUMERIC := 0;
  v_net_balance NUMERIC := 0;
  v_direction TEXT;
  v_settlement_id UUID;
BEGIN
  -- Skip auth check if called by superuser/cron (auth.uid() NULL means SECURITY DEFINER context)
  IF v_caller IS NOT NULL AND v_caller <> p_driver_id THEN
    IF NOT EXISTS (SELECT 1 FROM auth.users
                    WHERE id = v_caller
                      AND raw_app_meta_data->>'role' = 'admin') THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT
    COUNT(*),
    COALESCE(SUM(driver_earnings), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash' THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method IN ('card','mbway') THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash'
                  THEN GREATEST(COALESCE(final_total, price, 0) - COALESCE(driver_earnings, 0), 0)
                  ELSE 0 END), 0)
  INTO v_total_deliveries, v_total_earnings, v_total_cash_received,
       v_total_card_orders, v_cash_adjustments_due
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status = 'delivered'
    AND delivered_at >= v_bounds.week_start
    AND delivered_at <= v_bounds.week_end;

  v_net_balance := ROUND(v_total_earnings - v_total_cash_received
                       + v_tokens_converted_value, 2);
  v_direction := CASE
    WHEN v_net_balance > 0 THEN 'bora_pays_driver'
    WHEN v_net_balance < 0 THEN 'driver_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.driver_weekly_settlements (
      driver_id, week_start_at, week_end_at,
      total_deliveries, total_earnings, total_cash_received,
      total_card_orders, cash_adjustments_due, tokens_converted_value,
      net_balance, direction, status
    ) VALUES (
      p_driver_id, v_bounds.week_start, v_bounds.week_end,
      v_total_deliveries, v_total_earnings, v_total_cash_received,
      v_total_card_orders, v_cash_adjustments_due, v_tokens_converted_value,
      v_net_balance, v_direction, 'pending'
    )
    ON CONFLICT (driver_id, week_start_at) DO UPDATE SET
      total_deliveries       = EXCLUDED.total_deliveries,
      total_earnings         = EXCLUDED.total_earnings,
      total_cash_received    = EXCLUDED.total_cash_received,
      total_card_orders      = EXCLUDED.total_card_orders,
      cash_adjustments_due   = EXCLUDED.cash_adjustments_due,
      tokens_converted_value = EXCLUDED.tokens_converted_value,
      net_balance            = EXCLUDED.net_balance,
      direction              = EXCLUDED.direction
    RETURNING id INTO v_settlement_id;
  END IF;

  RETURN jsonb_build_object(
    'driver_id', p_driver_id,
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'total_deliveries', v_total_deliveries,
    'total_earnings', v_total_earnings,
    'total_cash_received', v_total_cash_received,
    'total_card_orders', v_total_card_orders,
    'cash_adjustments_due', v_cash_adjustments_due,
    'tokens_converted_value', v_tokens_converted_value,
    'net_balance', v_net_balance,
    'direction', v_direction,
    'settlement_id', v_settlement_id,
    'persisted', p_persist
  );
END;
$function$;

-- list_driver_orders_in_week — return signature changed:
-- cash_adjust_due → cash_received. Drop the old signature first to avoid
-- "cannot change return type" error on CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.list_driver_orders_in_week(uuid, timestamptz);

CREATE OR REPLACE FUNCTION public.list_driver_orders_in_week(
  p_driver_id uuid,
  p_week_start timestamptz DEFAULT NULL
)
RETURNS TABLE(
  order_id text,
  delivered_at timestamptz,
  payment_method text,
  service_type text,
  vendor_name text,
  final_total numeric,
  driver_earnings numeric,
  cash_received numeric,
  net_per_order numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
BEGIN
  IF v_caller IS NOT NULL AND v_caller <> p_driver_id THEN
    IF NOT EXISTS (SELECT 1 FROM auth.users
                    WHERE id = v_caller
                      AND raw_app_meta_data->>'role' = 'admin') THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  RETURN QUERY
    SELECT
      o.id,
      o.delivered_at,
      o.payment_method,
      o.service_type,
      o.vendor_name,
      ROUND(COALESCE(o.final_total, o.price, 0)::numeric, 2),
      ROUND(COALESCE(o.driver_earnings, 0)::numeric, 2),
      CASE WHEN o.payment_method = 'cash'
        THEN ROUND(COALESCE(o.final_total, o.price, 0)::numeric, 2)
        ELSE 0::numeric
      END,
      CASE WHEN o.payment_method = 'cash'
        THEN ROUND((COALESCE(o.driver_earnings, 0)
                  - COALESCE(o.final_total, o.price, 0))::numeric, 2)
        ELSE ROUND(COALESCE(o.driver_earnings, 0)::numeric, 2)
      END
    FROM public.orders o
    WHERE o.assigned_driver_id = p_driver_id::text
      AND o.status = 'delivered'
      AND o.delivered_at >= v_bounds.week_start
      AND o.delivered_at <= v_bounds.week_end
    ORDER BY o.delivered_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.compute_driver_settlement(uuid, timestamptz, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_driver_settlement(uuid, timestamptz, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.list_driver_orders_in_week(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_driver_orders_in_week(uuid, timestamptz) TO authenticated;
