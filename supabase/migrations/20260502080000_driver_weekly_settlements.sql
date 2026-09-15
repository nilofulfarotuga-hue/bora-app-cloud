-- ============================================================================
-- BORA — FASE 3: driver_weekly_settlements (segunda → domingo Lisbon)
-- ============================================================================
-- Ciclo de pagamento semanal. Settlement processado pelo admin via MBWay
-- na segunda-feira de manhã. Cron 'close-weekly-settlements' corre seg 00:05
-- UTC e cria 1 row por driver com entregas na semana fechada.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.driver_weekly_settlements (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id                UUID NOT NULL REFERENCES public.drivers(id),
  week_start_at            TIMESTAMPTZ NOT NULL,
  week_end_at              TIMESTAMPTZ NOT NULL,
  total_deliveries         INT NOT NULL DEFAULT 0,
  total_earnings           NUMERIC NOT NULL DEFAULT 0,
  total_cash_received      NUMERIC NOT NULL DEFAULT 0,
  total_card_orders        NUMERIC NOT NULL DEFAULT 0,
  cash_adjustments_due     NUMERIC NOT NULL DEFAULT 0,
  tokens_converted_value   NUMERIC NOT NULL DEFAULT 0,
  net_balance              NUMERIC NOT NULL DEFAULT 0,
  direction                TEXT NOT NULL
    CHECK (direction IN ('bora_pays_driver','driver_pays_bora','zero')),
  status                   TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','paid','received','disputed')),
  payment_method           TEXT DEFAULT 'mbway',
  payment_reference        TEXT,
  paid_at                  TIMESTAMPTZ,
  paid_by                  UUID,
  notes                    TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(driver_id, week_start_at)
);

CREATE INDEX IF NOT EXISTS idx_settlements_status
  ON public.driver_weekly_settlements(status);
CREATE INDEX IF NOT EXISTS idx_settlements_week
  ON public.driver_weekly_settlements(week_start_at);
CREATE INDEX IF NOT EXISTS idx_settlements_driver_week
  ON public.driver_weekly_settlements(driver_id, week_start_at);

ALTER TABLE public.driver_weekly_settlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS settlements_driver_read_own ON public.driver_weekly_settlements;
CREATE POLICY settlements_driver_read_own
  ON public.driver_weekly_settlements FOR SELECT
  USING (driver_id = auth.uid());

-- Helper: week boundaries para Lisbon TZ.
CREATE OR REPLACE FUNCTION public.driver_settlement_week_bounds(p_anchor TIMESTAMPTZ)
RETURNS TABLE(week_start TIMESTAMPTZ, week_end TIMESTAMPTZ)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_lisbon TIMESTAMP;
  v_start_lisbon TIMESTAMP;
BEGIN
  v_lisbon := p_anchor AT TIME ZONE 'Europe/Lisbon';
  v_start_lisbon := date_trunc('week', v_lisbon);
  week_start := v_start_lisbon AT TIME ZONE 'Europe/Lisbon';
  week_end := week_start + interval '7 days' - interval '1 second';
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_driver_orders_in_week(
  p_driver_id UUID,
  p_week_start TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(
  order_id        TEXT,
  delivered_at    TIMESTAMPTZ,
  payment_method  TEXT,
  service_type    TEXT,
  vendor_name     TEXT,
  final_total     NUMERIC,
  driver_earnings NUMERIC,
  cash_adjust_due NUMERIC,
  net_per_order   NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  IF v_caller <> p_driver_id THEN
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
        THEN GREATEST(ROUND((COALESCE(o.final_total, o.price, 0)
                            - COALESCE(o.driver_earnings, 0))::numeric, 2), 0)
        ELSE 0::numeric
      END,
      CASE WHEN o.payment_method = 'cash'
        THEN ROUND((2 * COALESCE(o.driver_earnings, 0)
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

REVOKE ALL ON FUNCTION public.list_driver_orders_in_week(UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_driver_orders_in_week(UUID, TIMESTAMPTZ) TO authenticated;

CREATE OR REPLACE FUNCTION public.compute_driver_settlement(
  p_driver_id UUID,
  p_week_start TIMESTAMPTZ DEFAULT NULL,
  p_persist BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  IF v_caller <> p_driver_id THEN
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

  v_tokens_converted_value := 0;  -- TODO: token conversion table

  v_net_balance := ROUND(v_total_earnings - v_cash_adjustments_due
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
    'driver_id',                p_driver_id,
    'week_start',               v_bounds.week_start,
    'week_end',                 v_bounds.week_end,
    'total_deliveries',         v_total_deliveries,
    'total_earnings',           v_total_earnings,
    'total_cash_received',      v_total_cash_received,
    'total_card_orders',        v_total_card_orders,
    'cash_adjustments_due',     v_cash_adjustments_due,
    'tokens_converted_value',   v_tokens_converted_value,
    'net_balance',              v_net_balance,
    'direction',                v_direction,
    'settlement_id',            v_settlement_id,
    'persisted',                p_persist
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.compute_driver_settlement(UUID, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_driver_settlement(UUID, TIMESTAMPTZ, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.close_previous_week_settlements()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';
  v_drv RECORD;
BEGIN
  FOR v_drv IN
    SELECT DISTINCT assigned_driver_id::uuid AS id
    FROM public.orders o, public.driver_settlement_week_bounds(v_anchor) b
    WHERE o.status = 'delivered'
      AND o.delivered_at >= b.week_start
      AND o.delivered_at <= b.week_end
      AND o.assigned_driver_id ~ '^[0-9a-f]{8}-'
  LOOP
    PERFORM public.compute_driver_settlement(v_drv.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.close_previous_week_settlements() FROM PUBLIC;

DO $$
BEGIN
  PERFORM cron.unschedule('close-weekly-settlements');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'close-weekly-settlements',
  '5 0 * * 1',
  $$SELECT public.close_previous_week_settlements();$$
);

COMMIT;
