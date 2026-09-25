-- ============================================================================
-- Serviços / Barbearias — RPCs core (helpers + slots + cliente + parceiro)
-- Padrão reservas: SECURITY DEFINER, search_path public. Sem ledger_entries.
-- Refund é fire-and-forget na app (a RPC devolve deposit_pi). Push: in-app +
-- (cliente) FCM via notify-client.
-- ============================================================================

-- ---------- helpers de notificação ----------
CREATE OR REPLACE FUNCTION public._appt_notify_client(
  p_client_user_id uuid, p_kind text, p_title text, p_body text, p_appointment_id text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_url text; v_key text;
BEGIN
  IF p_client_user_id IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(p_client_user_id, p_kind, p_title, p_body, p_appointment_id);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('clientId', p_client_user_id::text, 'reservationId', COALESCE(p_appointment_id,''),
                                   'title', p_title, 'body', p_body, 'kind', p_kind, 'type', 'appointment_status')
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

CREATE OR REPLACE FUNCTION public._appt_notify_partner(
  p_provider_id text, p_kind text, p_title text, p_body text, p_appointment_id text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_owner uuid;
BEGIN
  SELECT user_id INTO v_owner FROM public.service_providers WHERE id = p_provider_id;
  IF v_owner IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(v_owner, p_kind, p_title, p_body, p_appointment_id);
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- ---------- assert ownership do provider ----------
CREATE OR REPLACE FUNCTION public._appt_assert_provider_owner(p_provider_id text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT user_id INTO v_owner FROM public.service_providers WHERE id = p_provider_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'provider_not_found'; END IF;
  IF v_owner <> v_uid AND NOT public.is_admin() THEN RAISE EXCEPTION 'not_provider_owner'; END IF;
END $$;

-- ---------- get_available_slots ----------
CREATE OR REPLACE FUNCTION public.get_available_slots(
  p_staff_id text, p_service_id text, p_date date
) RETURNS TABLE(slot_start timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_duration int; v_dow int; v_avail record; v_min_advance int;
  v_day_start timestamptz; v_day_end timestamptz; v_slot timestamptz;
BEGIN
  SELECT duration_minutes INTO v_duration FROM provider_services WHERE id = p_service_id AND is_active;
  IF v_duration IS NULL OR v_duration <= 0 THEN RETURN; END IF;

  SELECT COALESCE((value::text)::int,30) INTO v_min_advance FROM platform_settings WHERE key='appointment_min_advance_minutes';
  v_min_advance := COALESCE(v_min_advance, 30);

  v_dow := EXTRACT(DOW FROM p_date)::int;   -- 0=Dom..6=Sáb (== staff_availability.day_of_week)
  SELECT * INTO v_avail FROM staff_availability
    WHERE staff_id = p_staff_id AND day_of_week = v_dow AND is_working;
  IF v_avail IS NULL THEN RETURN; END IF;

  v_day_start := (p_date + v_avail.start_time) AT TIME ZONE 'Europe/Lisbon';
  v_day_end   := (p_date + v_avail.end_time)   AT TIME ZONE 'Europe/Lisbon';

  v_slot := v_day_start;
  WHILE v_slot + (v_duration || ' minutes')::interval <= v_day_end LOOP
    IF v_slot >= now() + (v_min_advance || ' minutes')::interval THEN
      IF NOT EXISTS (
        SELECT 1 FROM appointments a
        WHERE a.staff_id = p_staff_id
          AND a.status IN ('pending_payment','confirmed','completed','blocked')
          AND tstzrange(a.scheduled_at, a.scheduled_at + (a.duration_minutes || ' minutes')::interval, '[)')
              && tstzrange(v_slot, v_slot + (v_duration || ' minutes')::interval, '[)')
      ) THEN
        slot_start := v_slot;
        RETURN NEXT;
      END IF;
    END IF;
    v_slot := v_slot + (v_duration || ' minutes')::interval;
  END LOOP;
  RETURN;
END $$;

-- ---------- client_book_appointment ----------
CREATE OR REPLACE FUNCTION public.client_book_appointment(
  p_service_id text, p_staff_id text, p_scheduled_at timestamptz, p_client_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_svc record; v_deposit int; v_max_days int;
  v_appt_id uuid; v_name text; v_phone text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT ps.duration_minutes, ps.price_cents, sp.id AS prov_id
    INTO v_svc
    FROM provider_services ps
    JOIN service_providers sp ON sp.id = ps.provider_id
    WHERE ps.id = p_service_id AND ps.is_active AND sp.approval_status='approved';
  IF v_svc IS NULL THEN RAISE EXCEPTION 'service_not_found'; END IF;

  IF NOT EXISTS (SELECT 1 FROM staff_members WHERE id=p_staff_id AND provider_id=v_svc.prov_id AND is_active) THEN
    RAISE EXCEPTION 'staff_not_found';
  END IF;

  SELECT COALESCE((value::text)::int,300) INTO v_deposit FROM platform_settings WHERE key='appointment_deposit_cents';
  v_deposit := COALESCE(v_deposit,300);
  SELECT COALESCE((value::text)::int,30) INTO v_max_days FROM platform_settings WHERE key='appointment_max_advance_days';
  v_max_days := COALESCE(v_max_days,30);

  IF p_scheduled_at <= now() THEN RAISE EXCEPTION 'slot_in_past'; END IF;
  IF p_scheduled_at > now() + (v_max_days || ' days')::interval THEN RAISE EXCEPTION 'too_far_in_advance'; END IF;

  IF EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.staff_id = p_staff_id
      AND a.status IN ('pending_payment','confirmed','completed','blocked')
      AND tstzrange(a.scheduled_at, a.scheduled_at + (a.duration_minutes||' minutes')::interval,'[)')
          && tstzrange(p_scheduled_at, p_scheduled_at + (v_svc.duration_minutes||' minutes')::interval,'[)')
  ) THEN RAISE EXCEPTION 'slot_taken'; END IF;

  SELECT COALESCE(name,''), COALESCE(phone,'') INTO v_name, v_phone FROM users WHERE id=v_uid;

  INSERT INTO appointments(provider_id, staff_id, service_id, client_user_id, client_name, client_phone,
                           scheduled_at, duration_minutes, service_price_cents, deposit_cents, deposit_status,
                           status, client_notes)
  VALUES (v_svc.prov_id, p_staff_id, p_service_id, v_uid, v_name, v_phone,
          p_scheduled_at, v_svc.duration_minutes, v_svc.price_cents, v_deposit, 'pending',
          'pending_payment', p_client_notes)
  RETURNING id INTO v_appt_id;

  RETURN jsonb_build_object('appointment_id', v_appt_id, 'deposit_cents', v_deposit, 'service_price_cents', v_svc.price_cents);
END $$;

-- ---------- client_confirm_appointment_payment ----------
CREATE OR REPLACE FUNCTION public.client_confirm_appointment_payment(p_appointment_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_appt record; v_when text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_appt.client_user_id <> v_uid THEN RAISE EXCEPTION 'not_your_appointment'; END IF;
  IF v_appt.status NOT IN ('pending_payment','confirmed') THEN RAISE EXCEPTION 'invalid_status'; END IF;

  IF v_appt.status = 'pending_payment' THEN
    UPDATE appointments SET status='confirmed', deposit_status='paid', confirmed_at=now()
      WHERE id=p_appointment_id;
    v_when := to_char(v_appt.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI');
    PERFORM public._appt_notify_partner(v_appt.provider_id, 'appointment_new', 'Nova marcação',
            'Nova marcação confirmada para '||v_when, p_appointment_id::text);
    PERFORM public._appt_notify_client(v_uid, 'appointment_confirmed', 'Marcação confirmada',
            'A tua marcação para '||v_when||' está confirmada.', p_appointment_id::text);
  END IF;
  RETURN jsonb_build_object('success', true, 'status', 'confirmed');
END $$;

-- ---------- client_cancel_appointment ----------
CREATE OR REPLACE FUNCTION public.client_cancel_appointment(p_appointment_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_appt record; v_window int; v_diff_h numeric; v_refund boolean; v_dep_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_appt.client_user_id <> v_uid THEN RAISE EXCEPTION 'not_your_appointment'; END IF;
  IF v_appt.status NOT IN ('pending_payment','confirmed') THEN RAISE EXCEPTION 'cannot_cancel'; END IF;

  SELECT COALESCE((value::text)::int,24) INTO v_window FROM platform_settings WHERE key='appointment_cancel_window_hours';
  v_window := COALESCE(v_window,24);
  v_diff_h := EXTRACT(EPOCH FROM (v_appt.scheduled_at - now()))/3600.0;
  v_refund := v_diff_h >= v_window;

  IF v_appt.deposit_status <> 'paid' THEN
    v_dep_status := v_appt.deposit_status; v_refund := false;
  ELSIF v_refund THEN
    v_dep_status := 'refunded';
  ELSE
    v_dep_status := 'retained';
  END IF;

  UPDATE appointments SET status='cancelled', cancelled_at=now(), cancel_reason=p_reason,
         cancelled_by='client', deposit_status=v_dep_status
    WHERE id=p_appointment_id;

  PERFORM public._appt_notify_partner(v_appt.provider_id, 'appointment_cancelled', 'Marcação cancelada',
          'Uma marcação foi cancelada pelo cliente.', p_appointment_id::text);

  RETURN jsonb_build_object('success', true, 'will_refund', v_refund,
                            'deposit_pi', v_appt.deposit_pi, 'deposit_status', v_dep_status);
END $$;

-- ---------- partner_complete_appointment ----------
CREATE OR REPLACE FUNCTION public.partner_complete_appointment(p_appointment_id uuid, p_payment_method text DEFAULT 'on_site')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_appt record;
BEGIN
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_appt.provider_id);
  IF v_appt.status <> 'confirmed' THEN RAISE EXCEPTION 'invalid_status'; END IF;
  IF p_payment_method NOT IN ('on_site','app') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  UPDATE appointments SET status='completed', completed_at=now(),
         full_payment_method=p_payment_method,
         full_payment_status = CASE WHEN p_payment_method='app' THEN 'paid' ELSE 'pending' END
    WHERE id=p_appointment_id;

  IF v_appt.client_user_id IS NOT NULL THEN
    PERFORM public._appt_notify_client(v_appt.client_user_id, 'appointment_completed', 'Obrigado!',
            'A tua marcação foi concluída. Até à próxima!', p_appointment_id::text);
  END IF;
  RETURN jsonb_build_object('success', true, 'status','completed');
END $$;

-- ---------- partner_mark_no_show ----------
CREATE OR REPLACE FUNCTION public.partner_mark_no_show(p_appointment_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_appt record;
BEGIN
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_appt.provider_id);
  IF v_appt.status <> 'confirmed' THEN RAISE EXCEPTION 'invalid_status'; END IF;

  UPDATE appointments SET status='no_show', no_show_at=now(),
         deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END
    WHERE id=p_appointment_id;
  RETURN jsonb_build_object('success', true, 'status','no_show');
END $$;

-- ---------- partner_add_walk_in ----------
CREATE OR REPLACE FUNCTION public.partner_add_walk_in(
  p_provider_id text, p_service_id text, p_staff_id text, p_scheduled_at timestamptz, p_client_name text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_svc record; v_id uuid;
BEGIN
  PERFORM public._appt_assert_provider_owner(p_provider_id);
  SELECT duration_minutes, price_cents INTO v_svc FROM provider_services WHERE id=p_service_id AND provider_id=p_provider_id;
  IF v_svc IS NULL THEN RAISE EXCEPTION 'service_not_found'; END IF;

  INSERT INTO appointments(provider_id, staff_id, service_id, client_user_id, client_name,
                           scheduled_at, duration_minutes, service_price_cents, deposit_cents,
                           deposit_status, status, is_walk_in)
  VALUES (p_provider_id, p_staff_id, p_service_id, NULL, COALESCE(p_client_name,''),
          p_scheduled_at, v_svc.duration_minutes, v_svc.price_cents, 0,
          'waived', 'confirmed', true)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('appointment_id', v_id);
END $$;

-- ---------- partner_block_slot ----------
CREATE OR REPLACE FUNCTION public.partner_block_slot(
  p_staff_id text, p_start_at timestamptz, p_end_at timestamptz, p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_provider text; v_dur int; v_id uuid;
BEGIN
  SELECT provider_id INTO v_provider FROM staff_members WHERE id=p_staff_id;
  IF v_provider IS NULL THEN RAISE EXCEPTION 'staff_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_provider);
  v_dur := GREATEST(1, (EXTRACT(EPOCH FROM (p_end_at - p_start_at))/60)::int);

  INSERT INTO appointments(provider_id, staff_id, service_id, scheduled_at, duration_minutes,
                           service_price_cents, deposit_cents, deposit_status, status, is_walk_in, partner_notes)
  VALUES (v_provider, p_staff_id, NULL, p_start_at, v_dur, 0, 0, 'waived', 'blocked', false, p_reason)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('appointment_id', v_id);
END $$;
