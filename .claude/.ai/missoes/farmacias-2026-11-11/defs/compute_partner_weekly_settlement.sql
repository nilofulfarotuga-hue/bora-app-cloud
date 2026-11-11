CREATE OR REPLACE FUNCTION public.compute_partner_weekly_settlement(p_partner_id text, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_bounds record;
  v_total_orders int := 0;
  v_gross numeric := 0;
  v_share numeric := 0;
  v_cash_partner numeric := 0;
  v_pago_recolha numeric := 0; -- 10/11/2026 pagar-na-loja: estafeta pagou a loja em mao na recolha
  v_commission numeric := 0;
  v_net numeric := 0;
  v_deposit numeric := 0;   -- 09/11/2026 Volta
  v_direction text;
  v_id uuid;
BEGIN
  IF v_caller IS NOT NULL AND NOT public._is_admin(v_caller) THEN
    IF NOT EXISTS (SELECT 1 FROM public.restaurants r
                    WHERE r.id = p_partner_id
                      AND COALESCE(r.user_id, r.user_) = v_caller) THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT
    COUNT(*),
    COALESCE(SUM(COALESCE(o.subtotal, 0) + CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.partner_commission_visible, 0) ELSE 0 END), 0),
    COALESCE(SUM(ls.share), 0),
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND (o.takeaway_picked_up_at IS NOT NULL OR public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id))
                  THEN COALESCE(o.final_total, o.total, o.price, 0)
                  ELSE 0 END), 0),
    -- 10/11/2026 pagar-na-loja: pedido de app a dinheiro em loja parceira em que o estafeta
    -- pagou a loja na recolha. A loja ja recebeu este valor em mao.
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND COALESCE(o.is_partner_store, false)
                       AND COALESCE(o.is_purchase_finalized, false)
                       AND o.takeaway_picked_up_at IS NULL
                       AND NOT public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id)
                  THEN COALESCE(o.final_purchase_value, 0)
                  ELSE 0 END), 0)
  INTO v_total_orders, v_gross, v_share, v_cash_partner, v_pago_recolha
  FROM public.orders o
  LEFT JOIN LATERAL (
    SELECT SUM(le.amount) AS share
    FROM public.ledger_entries le
    WHERE le.order_id::text = o.id
      AND le.user_type = 'restaurant'
      AND le.type = 'earning'
  ) ls ON true
  WHERE o.restaurant_id = p_partner_id
    AND o.status = 'delivered'
    AND o.delivered_at >= v_bounds.week_start
    AND o.delivered_at <= v_bounds.week_end;

  v_cash_partner := ROUND(v_cash_partner + v_pago_recolha, 2);
  v_commission := ROUND(v_gross - v_share, 2);
  -- 09/11/2026 Volta: depositos dos pedidos da semana, 100 % do parceiro, a parte da comissao.
  SELECT COALESCE(SUM(le.amount), 0) INTO v_deposit
    FROM public.ledger_entries le
    JOIN public.orders o ON o.id = le.order_id::text
   WHERE le.user_type = 'restaurant' AND le.type = 'deposit_volta'
     AND o.restaurant_id = p_partner_id
     AND o.status = 'delivered'
     AND o.delivered_at >= v_bounds.week_start
     AND o.delivered_at <= v_bounds.week_end;
  v_net := ROUND(v_share + v_deposit - v_cash_partner, 2);
  v_direction := CASE
    WHEN v_net > 0 THEN 'bora_pays_partner'
    WHEN v_net < 0 THEN 'partner_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.partner_weekly_settlements (
      partner_id, week_start_at, week_end_at,
      total_orders, gross_sales, commission_total, partner_share,
      cash_kept_by_partner, net_balance, direction, status, deposit_volta_total,
      pago_em_mao_na_recolha
    ) VALUES (
      p_partner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_orders, v_gross, v_commission, v_share,
      v_cash_partner, v_net, v_direction, 'pending', v_deposit,
      v_pago_recolha
    )
    ON CONFLICT (partner_id, week_start_at) DO UPDATE SET
      total_orders           = EXCLUDED.total_orders,
      gross_sales            = EXCLUDED.gross_sales,
      commission_total       = EXCLUDED.commission_total,
      partner_share          = EXCLUDED.partner_share,
      cash_kept_by_partner   = EXCLUDED.cash_kept_by_partner,
      net_balance            = EXCLUDED.net_balance,
      deposit_volta_total    = EXCLUDED.deposit_volta_total,
      pago_em_mao_na_recolha = EXCLUDED.pago_em_mao_na_recolha,
      direction              = EXCLUDED.direction
    WHERE public.partner_weekly_settlements.status NOT IN ('paid','received')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'total_orders', v_total_orders,
    'gross_sales', v_gross,
    'commission_total', v_commission,
    'partner_share', v_share,
    'cash_kept_by_partner', v_cash_partner,
    'pago_em_mao_na_recolha', v_pago_recolha,
    'net_balance', v_net,
    'deposit_volta_total', v_deposit,
    'direction', v_direction,
    'settlement_id', v_id,
    'persisted', p_persist
  );
END;
$function$
;
