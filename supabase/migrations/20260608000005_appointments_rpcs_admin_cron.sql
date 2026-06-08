-- ============================================================================
-- Serviços / Barbearias — crons, settlement semanal e RPCs admin
-- Reutiliza driver_settlement_week_bounds (Segunda 00:00 → Domingo 23:59 Lisbon).
-- ============================================================================

-- ---------- lembrete 24h ----------
CREATE OR REPLACE FUNCTION public._appointment_cron_send_reminders_24h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_enabled boolean; v_count int := 0; v_rec record;
BEGIN
  SELECT COALESCE((value::text)::boolean, true) INTO v_enabled FROM platform_settings WHERE key='appointment_reminder_24h_enabled';
  IF NOT COALESCE(v_enabled, true) THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT * FROM appointments
    WHERE status='confirmed' AND reminder_24h_sent_at IS NULL
      AND scheduled_at BETWEEN now() + interval '23 hours' AND now() + interval '25 hours'
  LOOP
    PERFORM public._appt_notify_client(v_rec.client_user_id, 'appointment_reminder', 'Lembrete de marcação',
      'Tens uma marcação amanhã às '||to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon','HH24:MI')||'.', v_rec.id::text);
    UPDATE appointments SET reminder_24h_sent_at=now() WHERE id=v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;

-- ---------- lembrete 2h ----------
CREATE OR REPLACE FUNCTION public._appointment_cron_send_reminders_2h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_enabled boolean; v_count int := 0; v_rec record;
BEGIN
  SELECT COALESCE((value::text)::boolean, true) INTO v_enabled FROM platform_settings WHERE key='appointment_reminder_2h_enabled';
  IF NOT COALESCE(v_enabled, true) THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT * FROM appointments
    WHERE status='confirmed' AND reminder_2h_sent_at IS NULL
      AND scheduled_at BETWEEN now() + interval '105 minutes' AND now() + interval '135 minutes'
  LOOP
    PERFORM public._appt_notify_client(v_rec.client_user_id, 'appointment_reminder', 'Marcação daqui a 2h',
      'A tua marcação é hoje às '||to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon','HH24:MI')||'.', v_rec.id::text);
    UPDATE appointments SET reminder_2h_sent_at=now() WHERE id=v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;

-- ---------- auto no-show ----------
CREATE OR REPLACE FUNCTION public._appointment_cron_auto_no_show()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_grace int; v_count int;
BEGIN
  SELECT COALESCE((value::text)::int,30) INTO v_grace FROM platform_settings WHERE key='appointment_no_show_grace_minutes';
  v_grace := COALESCE(v_grace,30);
  UPDATE appointments SET status='no_show', no_show_at=now(),
         deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END
   WHERE status='confirmed'
     AND scheduled_at < now() - (v_grace || ' minutes')::interval;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('marked_no_show', v_count, 'ran_at', now());
END $$;

-- ---------- settlement semanal por provider ----------
CREATE OR REPLACE FUNCTION public.compute_provider_weekly_payout(
  p_provider_id text, p_week_start timestamptz DEFAULT NULL, p_persist boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_bounds record; v_anchor timestamptz;
  v_booking_fee int; v_bora_cut int; v_partner_cut int;
  v_completed int; v_noshow int; v_cancel_ret int; v_service_rev int; v_deposits_retained int;
  v_consumed int; v_retained int; v_booking_fees int; v_deposit_cut int; v_net int; v_id uuid;
BEGIN
  v_anchor := COALESCE(p_week_start, now());
  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT COALESCE((value::text)::int,50)  INTO v_booking_fee FROM platform_settings WHERE key='appointment_booking_fee_cents';
  SELECT COALESCE((value::text)::int,50)  INTO v_bora_cut    FROM platform_settings WHERE key='appointment_deposit_bora_cut_cents';
  SELECT COALESCE((value::text)::int,250) INTO v_partner_cut FROM platform_settings WHERE key='appointment_deposit_partner_cut_cents';
  v_booking_fee := COALESCE(v_booking_fee,50); v_bora_cut := COALESCE(v_bora_cut,50); v_partner_cut := COALESCE(v_partner_cut,250);

  SELECT
    count(*) FILTER (WHERE status='completed'),
    count(*) FILTER (WHERE status='no_show'),
    count(*) FILTER (WHERE status='cancelled' AND deposit_status='retained'),
    COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND full_payment_method='app' AND full_payment_status='paid'),0),
    COALESCE(SUM(deposit_cents) FILTER (WHERE deposit_status='retained'),0)
  INTO v_completed, v_noshow, v_cancel_ret, v_service_rev, v_deposits_retained
  FROM appointments
  WHERE provider_id = p_provider_id
    AND scheduled_at >= v_bounds.week_start AND scheduled_at <= v_bounds.week_end;

  v_completed := COALESCE(v_completed,0); v_noshow := COALESCE(v_noshow,0); v_cancel_ret := COALESCE(v_cancel_ret,0);
  v_service_rev := COALESCE(v_service_rev,0); v_deposits_retained := COALESCE(v_deposits_retained,0);
  v_retained := v_noshow + v_cancel_ret;
  v_consumed := v_completed + v_retained;
  v_booking_fees := v_completed * v_booking_fee;
  v_deposit_cut := v_retained * v_bora_cut;
  v_net := v_consumed * v_partner_cut + v_service_rev;

  IF p_persist THEN
    INSERT INTO appointment_payouts(provider_id, week_start_at, week_end_at, total_appointments,
      total_service_revenue_cents, total_deposits_retained_cents, bora_booking_fees_cents,
      bora_deposit_cut_cents, net_payout_cents, direction, status)
    VALUES (p_provider_id, v_bounds.week_start, v_bounds.week_end, v_consumed,
      v_service_rev, v_deposits_retained, v_booking_fees, v_deposit_cut, v_net, 'bora_to_partner', 'pending')
    ON CONFLICT (provider_id, week_start_at) DO UPDATE SET
      week_end_at=EXCLUDED.week_end_at, total_appointments=EXCLUDED.total_appointments,
      total_service_revenue_cents=EXCLUDED.total_service_revenue_cents,
      total_deposits_retained_cents=EXCLUDED.total_deposits_retained_cents,
      bora_booking_fees_cents=EXCLUDED.bora_booking_fees_cents,
      bora_deposit_cut_cents=EXCLUDED.bora_deposit_cut_cents,
      net_payout_cents=EXCLUDED.net_payout_cents
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('provider_id', p_provider_id, 'week_start', v_bounds.week_start,
    'total_appointments', v_consumed, 'net_payout_cents', v_net,
    'bora_revenue_cents', v_booking_fees + v_deposit_cut, 'payout_id', v_id);
END $$;

-- ---------- settlement semanal de todos os providers (cron) ----------
CREATE OR REPLACE FUNCTION public.compute_all_provider_weekly_payouts()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_anchor timestamptz := now() - interval '1 day'; v_p record; v_count int := 0;
BEGIN
  FOR v_p IN
    SELECT DISTINCT a.provider_id
    FROM appointments a, public.driver_settlement_week_bounds(now() - interval '1 day') b
    WHERE a.scheduled_at >= b.week_start AND a.scheduled_at <= b.week_end
      AND a.status IN ('completed','no_show','cancelled')
  LOOP
    PERFORM public.compute_provider_weekly_payout(v_p.provider_id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;

-- ---------- admin: métricas ----------
CREATE OR REPLACE FUNCTION public.admin_appointments_metrics(
  p_provider_id text DEFAULT NULL, p_from timestamptz DEFAULT NULL, p_to timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_from timestamptz; v_to timestamptz; v_booking_fee int; v_bora_cut int; r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  v_from := COALESCE(p_from, now() - interval '30 days');
  v_to := COALESCE(p_to, now());
  SELECT COALESCE((value::text)::int,50) INTO v_booking_fee FROM platform_settings WHERE key='appointment_booking_fee_cents';
  SELECT COALESCE((value::text)::int,50) INTO v_bora_cut FROM platform_settings WHERE key='appointment_deposit_bora_cut_cents';
  v_booking_fee := COALESCE(v_booking_fee,50); v_bora_cut := COALESCE(v_bora_cut,50);
  SELECT jsonb_build_object(
    'from', v_from, 'to', v_to,
    'total', count(*),
    'confirmed', count(*) FILTER (WHERE status='confirmed'),
    'completed', count(*) FILTER (WHERE status='completed'),
    'no_show',   count(*) FILTER (WHERE status='no_show'),
    'cancelled', count(*) FILTER (WHERE status='cancelled'),
    'walk_ins',  count(*) FILTER (WHERE is_walk_in),
    'no_show_rate_pct', CASE WHEN count(*) FILTER (WHERE status IN ('completed','no_show'))>0
        THEN ROUND(100.0*count(*) FILTER (WHERE status='no_show')/count(*) FILTER (WHERE status IN ('completed','no_show')),1) ELSE 0 END,
    'bora_revenue_cents',
        COALESCE(SUM(CASE WHEN status='completed' THEN v_booking_fee ELSE 0 END),0)
      + COALESCE(SUM(CASE WHEN status='no_show' OR (status='cancelled' AND deposit_status='retained') THEN v_bora_cut ELSE 0 END),0),
    'service_revenue_app_cents', COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND full_payment_method='app' AND full_payment_status='paid'),0)
  ) INTO r
  FROM appointments
  WHERE scheduled_at >= v_from AND scheduled_at <= v_to
    AND (p_provider_id IS NULL OR provider_id = p_provider_id);
  RETURN r;
END $$;

-- ---------- admin: listar payouts ----------
CREATE OR REPLACE FUNCTION public.admin_list_appointment_payouts(
  p_provider_id text DEFAULT NULL, p_status text DEFAULT NULL, p_limit int DEFAULT 200
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO r FROM (
    SELECT ap.*, sp.name AS provider_name
    FROM appointment_payouts ap JOIN service_providers sp ON sp.id = ap.provider_id
    WHERE (p_provider_id IS NULL OR ap.provider_id = p_provider_id)
      AND (p_status IS NULL OR ap.status = p_status)
    ORDER BY ap.week_start_at DESC
    LIMIT p_limit
  ) t;
  RETURN r;
END $$;

-- ---------- admin: marcar payouts pagos ----------
CREATE OR REPLACE FUNCTION public.admin_mark_appointment_payouts_paid(
  p_provider_id text, p_payout_external_id uuid DEFAULT gen_random_uuid()
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int; v_total int;
BEGIN
  PERFORM public._admin_op_guard();
  WITH updated AS (
    UPDATE appointment_payouts
    SET status='paid', paid_at=now(), payment_reference=p_payout_external_id::text, paid_by=auth.uid()
    WHERE provider_id=p_provider_id AND status='pending'
    RETURNING net_payout_cents
  )
  SELECT count(*), COALESCE(SUM(net_payout_cents),0) INTO v_count, v_total FROM updated;
  PERFORM public.log_admin_action('appointment_payouts_marked_paid','service_provider',p_provider_id,
    jsonb_build_object('count',v_count,'total_cents',v_total,'external_id',p_payout_external_id));
  RETURN jsonb_build_object('success',true,'count',v_count,'total_cents',v_total,'payout_external_id',p_payout_external_id);
END $$;

-- ---------- admin: aprovar / rejeitar provider ----------
CREATE OR REPLACE FUNCTION public.admin_appointment_provider_approve(p_provider_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  UPDATE service_providers SET approval_status='approved', approved_at=now(), approved_by=auth.uid(), rejection_reason=NULL
   WHERE id=p_provider_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'provider_not_found'; END IF;
  PERFORM public.log_admin_action('service_provider_approved','service_provider',p_provider_id,'{}'::jsonb);
  RETURN jsonb_build_object('success',true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_appointment_provider_reject(p_provider_id text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  UPDATE service_providers SET approval_status='rejected', rejection_reason=p_reason, is_online=false
   WHERE id=p_provider_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'provider_not_found'; END IF;
  PERFORM public.log_admin_action('service_provider_rejected','service_provider',p_provider_id, jsonb_build_object('reason',p_reason));
  RETURN jsonb_build_object('success',true);
END $$;

-- ---------- admin: cancelar marcação em nome do cliente ----------
CREATE OR REPLACE FUNCTION public.admin_cancel_appointment_on_behalf_of(
  p_appointment_id uuid, p_reason text DEFAULT NULL, p_refund boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_appt record; v_dep text;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_appt.deposit_status='paid' THEN
    v_dep := CASE WHEN p_refund THEN 'refunded' ELSE 'retained' END;
  ELSE v_dep := v_appt.deposit_status; END IF;
  UPDATE appointments SET status='cancelled', cancelled_at=now(), cancel_reason=p_reason,
         cancelled_by='admin', deposit_status=v_dep WHERE id=p_appointment_id;
  PERFORM public.log_admin_action('appointment_cancelled_admin','appointment',p_appointment_id::text,
    jsonb_build_object('reason',p_reason,'refund',p_refund));
  IF v_appt.client_user_id IS NOT NULL THEN
    PERFORM public._appt_notify_client(v_appt.client_user_id,'appointment_cancelled','Marcação cancelada',
      'A tua marcação foi cancelada.',p_appointment_id::text);
  END IF;
  RETURN jsonb_build_object('success',true,'will_refund',(v_dep='refunded'),'deposit_pi',v_appt.deposit_pi);
END $$;
