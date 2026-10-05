-- PROPOSTA (NAO APLICADA) — ronda 04/10, Bloco B, item 6.
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- compute_provider_weekly_payout e funcao protegida pela Trava (lista de dinheiro), por isso
-- nao foi aplicada pelo agente. Unica mudanca face a versao no ar (lida a 05/10 com
-- pg_get_functiondef): o valor cheio "pago na app" so entra no repasse da barbearia quando
-- houve pagamento REAL (full_payment_pi preenchido), e nao so porque o parceiro carregou em
-- "pagou na app". Hoje ha 1 marcacao nessa situacao (app/paid sem pagamento).
-- O gatilho trg_acerto_pago_congelado (20261005090504) ja impede que este recalculo mude
-- semanas pagas/recebidas.

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
      + COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND full_payment_method='app' AND full_payment_status='paid'
                                                    AND full_payment_pi IS NOT NULL),0),
    count(*) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),
    COALESCE(SUM(deposit_cents) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),0)
  INTO v_completed, v_walkins, v_paid_bookings, v_revenue, v_retained, v_retained_cents
  FROM appointments
  WHERE provider_id = p_provider_id
    AND scheduled_at >= v_bounds.week_start AND scheduled_at <= v_bounds.week_end;

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
