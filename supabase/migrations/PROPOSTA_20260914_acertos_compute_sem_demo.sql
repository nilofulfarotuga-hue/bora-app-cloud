-- ============================================================================
-- PROPOSTA — NAO APLICADA. Missao painel-admin-limpo, 2026-09-14.
--
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Esta tudo pronto — o Danilo confirma e
-- aplica-se por MCP (a Trava bloqueia DDL sobre estas tres funcoes, por
-- desenho; ver .claude/hooks/protege-banco.sh, lista MONEYFN).
--
-- O que ja esta em producao SEM esta proposta (migration 20260913234634):
--   trigger BEFORE INSERT nas 5 tabelas de acerto — um SUJEITO demo (estafeta,
--   parceiro, barbeiro, limpador, lavador) nunca ganha linha de acerto.
--
-- O que so esta proposta resolve (caso raro, mas possivel):
--   um PEDIDO/MARCACAO de demo atribuido a uma pessoa REAL. Hoje o calculo
--   soma-o. Com o filtro abaixo, deixa de somar. Alem disso:
--   · compute_provider_weekly_payout ganha a guarda `status NOT IN
--     ('paid','received')` no ON CONFLICT, que as outras duas ja tem — hoje um
--     recalculo sobrescreve um payout ja pago.
--
-- O que muda em numeros reais desta semana (2026-09-06 23:00+00): NADA.
--   Danilo 1,10 · Valdemir 5,94 · Goola 21,80 · Ouro e Prata 11,50 — nenhum
--   destes tem pedido/marcacao de demo atribuido (provado por SQL a 14/09).
--
-- Como se reverte: reaplicar a definicao anterior de cada funcao (esta em
--   supabase/schema.sql e no historico de migrations), ou simplesmente nao
--   aplicar isto.
--
-- Diff resumido:
--   compute_driver_settlement ........ + AND NOT public.is_demo_order(orders)
--   compute_partner_weekly_settlement  + AND NOT public.is_demo_order(o)
--   compute_provider_weekly_payout ... + AND NOT public.is_demo_user(client_user_id)
--                                      + WHERE appointment_payouts.status NOT IN ('paid','received')
-- ============================================================================

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
    AND delivered_at <= v_bounds.week_end
    -- 2026-09-14: pedido de demonstracao nunca entra no acerto.
    AND NOT public.is_demo_order(orders);

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
    'net_balance', v_net_balance,
    'direction', v_direction,
    'settlement_id', v_settlement_id,
    'persisted', p_persist
  );
END;
$function$;

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
  v_commission numeric := 0;
  v_net numeric := 0;
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
    COALESCE(SUM(o.subtotal), 0),
    COALESCE(SUM(ls.share), 0),
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND o.takeaway_picked_up_at IS NOT NULL
                  THEN COALESCE(o.final_total, o.total, o.price, 0)
                  ELSE 0 END), 0)
  INTO v_total_orders, v_gross, v_share, v_cash_partner
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
    AND o.delivered_at <= v_bounds.week_end
    -- 2026-09-14: pedido de demonstracao nunca entra no acerto.
    AND NOT public.is_demo_order(o);

  v_commission := ROUND(v_gross - v_share, 2);
  v_net := ROUND(v_share - v_cash_partner, 2);
  v_direction := CASE
    WHEN v_net > 0 THEN 'bora_pays_partner'
    WHEN v_net < 0 THEN 'partner_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.partner_weekly_settlements (
      partner_id, week_start_at, week_end_at,
      total_orders, gross_sales, commission_total, partner_share,
      cash_kept_by_partner, net_balance, direction, status
    ) VALUES (
      p_partner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_orders, v_gross, v_commission, v_share,
      v_cash_partner, v_net, v_direction, 'pending'
    )
    ON CONFLICT (partner_id, week_start_at) DO UPDATE SET
      total_orders         = EXCLUDED.total_orders,
      gross_sales          = EXCLUDED.gross_sales,
      commission_total     = EXCLUDED.commission_total,
      partner_share        = EXCLUDED.partner_share,
      cash_kept_by_partner = EXCLUDED.cash_kept_by_partner,
      net_balance          = EXCLUDED.net_balance,
      direction            = EXCLUDED.direction
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
    'net_balance', v_net,
    'direction', v_direction,
    'settlement_id', v_id,
    'persisted', p_persist
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_provider_weekly_payout(p_provider_id text, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds record; v_anchor timestamptz;
  v_fee int; v_walkin_fee int;
  v_completed int; v_walkins int; v_paid_bookings int;
  v_revenue int; v_retained int; v_retained_cents int;
  v_fees_total int; v_walkin_fees int; v_net int;
  v_direction text; v_id uuid;
BEGIN
  v_anchor := COALESCE(p_week_start, now());
  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT COALESCE((value::text)::int,50) INTO v_fee        FROM platform_settings WHERE key='appointment_booking_fee_cents';
  SELECT COALESCE((value::text)::int,50) INTO v_walkin_fee FROM platform_settings WHERE key='appointment_walkin_fee_cents';
  v_fee := COALESCE(v_fee,50); v_walkin_fee := COALESCE(v_walkin_fee,50);

  SELECT
    count(*) FILTER (WHERE status='completed'),
    count(*) FILTER (WHERE status='completed' AND is_walk_in=true),
    count(*) FILTER (WHERE status='completed' AND is_walk_in=false),
    COALESCE(SUM(deposit_cents) FILTER (WHERE status='completed' AND deposit_status='paid'),0)
      + COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND full_payment_method='app' AND full_payment_status='paid'),0),
    count(*) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),
    COALESCE(SUM(deposit_cents) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),0)
  INTO v_completed, v_walkins, v_paid_bookings, v_revenue, v_retained, v_retained_cents
  FROM appointments
  WHERE provider_id = p_provider_id
    AND scheduled_at >= v_bounds.week_start AND scheduled_at <= v_bounds.week_end
    -- 2026-09-14: marcacao de cliente de demonstracao nunca entra no acerto.
    AND NOT public.is_demo_user(client_user_id);

  v_completed := COALESCE(v_completed,0); v_walkins := COALESCE(v_walkins,0);
  v_paid_bookings := COALESCE(v_paid_bookings,0); v_revenue := COALESCE(v_revenue,0);
  v_retained := COALESCE(v_retained,0); v_retained_cents := COALESCE(v_retained_cents,0);

  v_walkin_fees := v_walkins * v_walkin_fee;
  v_fees_total  := v_paid_bookings * v_fee + v_walkin_fees;
  v_net := v_revenue - v_fees_total;
  v_direction := CASE WHEN v_net >= 0 THEN 'bora_to_partner' ELSE 'partner_to_bora' END;

  IF p_persist THEN
    INSERT INTO appointment_payouts(provider_id, week_start_at, week_end_at, total_appointments,
      total_service_revenue_cents, total_deposits_retained_cents, bora_booking_fees_cents,
      bora_deposit_cut_cents, net_payout_cents, direction, status,
      total_walkins, total_walkin_fees_cents)
    VALUES (p_provider_id, v_bounds.week_start, v_bounds.week_end, v_completed,
      v_revenue, v_retained_cents, v_fees_total, 0, v_net, v_direction, 'pending',
      v_walkins, v_walkin_fees)
    ON CONFLICT (provider_id, week_start_at) DO UPDATE SET
      week_end_at=EXCLUDED.week_end_at, total_appointments=EXCLUDED.total_appointments,
      total_service_revenue_cents=EXCLUDED.total_service_revenue_cents,
      total_deposits_retained_cents=EXCLUDED.total_deposits_retained_cents,
      bora_booking_fees_cents=EXCLUDED.bora_booking_fees_cents,
      bora_deposit_cut_cents=EXCLUDED.bora_deposit_cut_cents,
      net_payout_cents=EXCLUDED.net_payout_cents,
      direction=EXCLUDED.direction,
      total_walkins=EXCLUDED.total_walkins,
      total_walkin_fees_cents=EXCLUDED.total_walkin_fees_cents
    -- 2026-09-14: um recalculo nunca toca num payout ja pago/recebido (as
    -- funcoes dos estafetas e dos parceiros ja tinham esta guarda; esta nao).
    WHERE appointment_payouts.status NOT IN ('paid','received')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('provider_id', p_provider_id, 'week_start', v_bounds.week_start,
    'total_appointments', v_completed, 'total_walkins', v_walkins,
    'revenue_recebida_cents', v_revenue,
    'taxa_bora_cents', v_fees_total,
    'retido_no_show_cents', v_retained_cents,
    'walkin_fees_cents', v_walkin_fees, 'net_payout_cents', v_net, 'direction', v_direction,
    'bora_revenue_cents', v_fees_total + v_retained_cents, 'payout_id', v_id);
END $function$;
