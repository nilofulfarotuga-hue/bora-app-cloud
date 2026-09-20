-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) a 20/09/2026 21:52 — versão 20260920205210.
-- Espelho exacto de supabase_migrations.schema_migrations (lido a 20/09 21:55 pelo Claude Code).
-- Zona vermelha (função do acerto semanal): a Trava do PC não a aplica; ficou aqui só como espelho
-- do que está no ar, para o repo não ficar atrás da produção.
CREATE OR REPLACE FUNCTION public.compute_driver_settlement(p_driver_id uuid, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
  v_total_deliveries INT := 0;
  v_total_earnings NUMERIC := 0;
  v_total_cash_received NUMERIC := 0;
  v_total_card_orders NUMERIC := 0;
  v_cash_adjustments_due NUMERIC := 0;
  v_total_reimbursements NUMERIC := 0;
  v_tokens_converted_value NUMERIC := 0;
  v_tvde_rides INT := 0;
  v_tvde_earnings NUMERIC := 0;
  v_tvde_cash NUMERIC := 0;
  v_tvde_online NUMERIC := 0;
  v_net_balance NUMERIC := 0;
  v_direction TEXT;
  v_settlement_id UUID;
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

  SELECT
    COUNT(*),
    COALESCE(SUM(driver_earnings), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash' THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method IN ('card','mbway') THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash'
                  THEN public.order_driver_reimbursement(id) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash'
                  THEN GREATEST(COALESCE(final_total, price, 0)
                                - COALESCE(driver_earnings, 0)
                                - public.order_driver_reimbursement(id), 0)
                  ELSE 0 END), 0)
  INTO v_total_deliveries, v_total_earnings, v_total_cash_received,
       v_total_card_orders, v_total_reimbursements, v_cash_adjustments_due
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status = 'delivered'
    AND delivered_at >= v_bounds.week_start
    AND delivered_at <= v_bounds.week_end;

  -- CONTAS CLARAS 2026-09-20: as corridas TVDE passam a entrar no acerto semanal.
  -- Ate esta data o acerto so olhava para as entregas, por isso o trabalho de TVDE
  -- nunca era pago nem cobrado por aqui. Mesma regra das entregas:
  --   ganho do motorista entra a credito; dinheiro recebido em mao entra a debito.
  -- Corrida paga online (cartao/MB Way): a Bora recebeu, logo deve o ganho ao motorista.
  -- Corrida paga a dinheiro: o motorista ja recebeu do passageiro, logo devolve a parte da Bora.
  SELECT
    COUNT(*),
    COALESCE(SUM(COALESCE(driver_earn_cents, 0)), 0) / 100.0,
    COALESCE(SUM(CASE WHEN payment_method = 'cash'
                  THEN COALESCE(final_fare_cents, est_fare_cents, 0) ELSE 0 END), 0) / 100.0,
    COALESCE(SUM(CASE WHEN payment_method IN ('card','mbway')
                  THEN COALESCE(final_fare_cents, est_fare_cents, 0) ELSE 0 END), 0) / 100.0
  INTO v_tvde_rides, v_tvde_earnings, v_tvde_cash, v_tvde_online
  FROM public.tvde_rides
  WHERE driver_id = p_driver_id
    AND status = 'finalizada'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  v_total_earnings      := v_total_earnings + v_tvde_earnings;
  v_total_cash_received := v_total_cash_received + v_tvde_cash;
  v_total_card_orders   := v_total_card_orders + v_tvde_online;

  SELECT COALESCE(SUM(amount), 0) INTO v_tokens_converted_value
  FROM public.driver_transactions
  WHERE driver_id = p_driver_id
    AND type = 'token_conversion'
    AND status = 'completed'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  -- FIX 2026-08-03: o que o estafeta adiantou nas compras volta para ele.
  v_net_balance := ROUND(v_total_earnings - v_total_cash_received
                       + v_total_reimbursements
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
      tvde_rides_count, tvde_earnings, tvde_cash_received,
      net_balance, direction, status
    ) VALUES (
      p_driver_id, v_bounds.week_start, v_bounds.week_end,
      v_total_deliveries, v_total_earnings, v_total_cash_received,
      v_total_card_orders, v_cash_adjustments_due, v_tokens_converted_value,
      v_tvde_rides, v_tvde_earnings, v_tvde_cash,
      v_net_balance, v_direction, 'pending'
    )
    ON CONFLICT (driver_id, week_start_at) DO UPDATE SET
      total_deliveries       = EXCLUDED.total_deliveries,
      total_earnings         = EXCLUDED.total_earnings,
      total_cash_received    = EXCLUDED.total_cash_received,
      total_card_orders      = EXCLUDED.total_card_orders,
      cash_adjustments_due   = EXCLUDED.cash_adjustments_due,
      tokens_converted_value = EXCLUDED.tokens_converted_value,
      tvde_rides_count       = EXCLUDED.tvde_rides_count,
      tvde_earnings          = EXCLUDED.tvde_earnings,
      tvde_cash_received     = EXCLUDED.tvde_cash_received,
      net_balance            = EXCLUDED.net_balance,
      direction              = EXCLUDED.direction
    WHERE public.driver_weekly_settlements.status NOT IN ('paid','received')
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
    'total_reimbursements', v_total_reimbursements,
    'tokens_converted_value', v_tokens_converted_value,
    'tvde_rides_count', v_tvde_rides,
    'tvde_earnings', v_tvde_earnings,
    'tvde_cash_received', v_tvde_cash,
    'net_balance', v_net_balance,
    'direction', v_direction,
    'settlement_id', v_settlement_id,
    'persisted', p_persist
  );
END;
$function$;
