-- ============================================================================
-- LIMPEZA — RPCs admin (com _admin_op_guard + log_admin_action) + crons
-- + geração de recorrências (série tenta SEMPRE a mesma profissional primeiro).
-- ============================================================================

-- ---------- paragem de série de recorrência ----------
CREATE TABLE IF NOT EXISTS public.cleaning_recurrence_stops (
  group_id   UUID PRIMARY KEY,
  stopped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  stopped_by UUID
);
ALTER TABLE public.cleaning_recurrence_stops ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.cancel_cleaning_series(p_group_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_count int := 0; v_rec record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cleaning_bookings
                 WHERE recurrence_group_id = p_group_id AND client_user_id = v_uid) THEN
    RAISE EXCEPTION 'series_not_yours';
  END IF;
  INSERT INTO cleaning_recurrence_stops (group_id, stopped_by)
  VALUES (p_group_id, v_uid)
  ON CONFLICT (group_id) DO NOTHING;

  -- cancela ocorrências futuras ainda sem custo (>24h ou ainda sem profissional)
  FOR v_rec IN
    SELECT id FROM cleaning_bookings
    WHERE recurrence_group_id = p_group_id
      AND status IN ('scheduled','accepted')
      AND scheduled_at > now() + interval '24 hours'
  LOOP
    UPDATE cleaning_bookings
    SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
        cancel_reason = 'serie_terminada', cancel_fee_cents = 0,
        offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public.cancel_cleaning_series(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cancel_cleaning_series(uuid) TO authenticated;

-- ---------- ADMIN: listar limpezas (filtros estado/data/profissional/pesquisa) ----------
CREATE OR REPLACE FUNCTION public.admin_list_cleanings(
  p_status text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_cleaner_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 200
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(row_data ORDER BY (row_data ->> 'scheduled_at') DESC)
    FROM (
      SELECT to_jsonb(b) ||
             jsonb_build_object(
               'cleaner_name', c.name,
               'client_email', u.email
             ) AS row_data
      FROM cleaning_bookings b
      LEFT JOIN cleaners c ON c.id = b.cleaner_id
      LEFT JOIN auth.users u ON u.id = b.client_user_id
      WHERE (p_status IS NULL OR b.status = p_status)
        AND (p_from IS NULL OR b.scheduled_at >= p_from)
        AND (p_to IS NULL OR b.scheduled_at <= p_to)
        AND (p_cleaner_id IS NULL OR b.cleaner_id = p_cleaner_id)
        AND (p_search IS NULL OR p_search = ''
             OR u.email ILIKE '%' || p_search || '%'
             OR c.name ILIKE '%' || p_search || '%'
             OR b.address_street ILIKE '%' || p_search || '%'
             OR b.id::text ILIKE '%' || p_search || '%')
      ORDER BY b.scheduled_at DESC
      LIMIT LEAST(COALESCE(p_limit, 200), 500)
    ) t
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_cleanings(text, timestamptz, timestamptz, uuid, text, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_cleanings(text, timestamptz, timestamptz, uuid, text, integer) TO authenticated;

-- ---------- ADMIN: listar profissionais ----------
CREATE OR REPLACE FUNCTION public.admin_list_cleaners(p_status text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(c) || jsonb_build_object(
             'late_cancels_30d', (SELECT count(*) FROM cleaner_cancel_events e
                                  WHERE e.cleaner_id = c.id AND e.was_late
                                    AND e.created_at > now() - interval '30 days'),
             'completed_total_cents', (SELECT COALESCE(sum(cleaner_earnings_cents),0)
                                       FROM cleaning_bookings b
                                       WHERE b.cleaner_id = c.id AND b.status = 'completed'),
             'cash_bora_due_cents', (SELECT COALESCE(sum(bora_fee_cents),0)
                                     FROM cleaning_bookings b
                                     WHERE b.cleaner_id = c.id
                                       AND b.payment_method = 'cash'
                                       AND b.payment_status = 'cash_pending')
           ) ORDER BY c.created_at DESC)
    FROM cleaners c
    WHERE (p_status IS NULL OR c.approval_status = p_status)
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_cleaners(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_cleaners(text) TO authenticated;

-- ---------- ADMIN: aprovar / rejeitar / suspender / reativar ----------
CREATE OR REPLACE FUNCTION public.admin_review_cleaner(
  p_cleaner_id uuid, p_action text, p_reason text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_admin RECORD; v_c cleaners; v_new_status text; v_msg text;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_c FROM cleaners WHERE id = p_cleaner_id FOR UPDATE;
  IF v_c.id IS NULL THEN RAISE EXCEPTION 'cleaner_not_found'; END IF;

  v_new_status := CASE p_action
    WHEN 'approve'    THEN 'approved'
    WHEN 'reject'     THEN 'rejected'
    WHEN 'suspend'    THEN 'suspended'
    WHEN 'reactivate' THEN 'approved'
    ELSE NULL END;
  IF v_new_status IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;

  UPDATE cleaners
  SET approval_status = v_new_status,
      approved_at = CASE WHEN v_new_status = 'approved' THEN now() ELSE approved_at END,
      approved_by = CASE WHEN v_new_status = 'approved' THEN v_admin.admin_id ELSE approved_by END,
      rejection_reason = CASE WHEN v_new_status IN ('rejected','suspended')
                              THEN NULLIF(p_reason,'') ELSE NULL END,
      flagged_low_rating = CASE WHEN p_action = 'reactivate' THEN false ELSE flagged_low_rating END
  WHERE id = p_cleaner_id;

  PERFORM public.log_admin_action(
    'cleaner_' || p_action, 'cleaner', p_cleaner_id::text,
    jsonb_build_object('name', v_c.name, 'reason', p_reason,
                       'old_status', v_c.approval_status, 'new_status', v_new_status));

  v_msg := CASE p_action
    WHEN 'approve'    THEN 'A tua candidatura foi aprovada! Já podes receber limpezas. 🎉'
    WHEN 'reject'     THEN 'A tua candidatura não foi aprovada.' ||
                           CASE WHEN COALESCE(p_reason,'') <> '' THEN ' Motivo: ' || p_reason ELSE '' END
    WHEN 'suspend'    THEN 'A tua conta de profissional foi suspensa.' ||
                           CASE WHEN COALESCE(p_reason,'') <> '' THEN ' Motivo: ' || p_reason ELSE '' END
    ELSE 'A tua conta de profissional foi reativada. Bem-vinda de volta!' END;
  PERFORM public._cleaning_notify_user(v_c.user_id, 'cleaner_review', 'Bora Limpezas', v_msg, NULL);

  RETURN (SELECT to_jsonb(c) FROM cleaners c WHERE c.id = p_cleaner_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_review_cleaner(uuid, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_cleaner(uuid, text, text) TO authenticated;

-- ---------- ADMIN: editar raio / ativo ----------
CREATE OR REPLACE FUNCTION public.admin_update_cleaner(
  p_cleaner_id uuid, p_service_radius_km numeric DEFAULT NULL, p_is_active boolean DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_c cleaners;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_c FROM cleaners WHERE id = p_cleaner_id;
  IF v_c.id IS NULL THEN RAISE EXCEPTION 'cleaner_not_found'; END IF;
  UPDATE cleaners SET
    service_radius_km = COALESCE(p_service_radius_km, service_radius_km),
    is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_cleaner_id;
  PERFORM public.log_admin_action('cleaner_updated', 'cleaner', p_cleaner_id::text,
    jsonb_build_object('service_radius_km', p_service_radius_km, 'is_active', p_is_active));
  RETURN (SELECT to_jsonb(c) FROM cleaners c WHERE c.id = p_cleaner_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_update_cleaner(uuid, numeric, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_cleaner(uuid, numeric, boolean) TO authenticated;

-- ---------- ADMIN: cancelar limpeza (sem taxa) ----------
CREATE OR REPLACE FUNCTION public.admin_cancel_cleaning(p_booking_id uuid, p_reason text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way','in_progress','done') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  UPDATE cleaning_bookings
  SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'admin',
      cancel_reason = COALESCE(NULLIF(p_reason,''), 'cancelado_pelo_suporte'),
      cancel_fee_cents = 0,
      payment_status = CASE WHEN payment_status = 'held' THEN 'estornado' ELSE payment_status END,
      offer_cleaner_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public.log_admin_action('cleaning_cancelled', 'cleaning_booking', p_booking_id::text,
    jsonb_build_object('reason', p_reason, 'previous_status', v_b.status));

  PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_cancelled',
    'Limpeza cancelada pelo suporte',
    'A tua limpeza foi cancelada pela equipa Bora. Sem qualquer custo.', p_booking_id::text);
  IF v_b.cleaner_id IS NOT NULL THEN
    PERFORM public._cleaning_notify_user(
      (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
      'cleaning_cancelled', 'Limpeza cancelada pelo suporte',
      'Uma limpeza da tua agenda foi cancelada pela equipa Bora.', p_booking_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_cancel_cleaning(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_cleaning(uuid, text) TO authenticated;

-- ---------- ADMIN: reagendar ----------
CREATE OR REPLACE FUNCTION public.admin_reschedule_cleaning(
  p_booking_id uuid, p_new_scheduled_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings; v_keep boolean := false;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted') THEN
    RAISE EXCEPTION 'cannot_reschedule_from_%', v_b.status;
  END IF;
  IF p_new_scheduled_at < now() THEN RAISE EXCEPTION 'new_time_in_past'; END IF;

  -- mantém a profissional se continuar disponível no novo horário
  IF v_b.cleaner_id IS NOT NULL THEN
    v_keep := public._cleaning_is_available(v_b.cleaner_id, p_new_scheduled_at, v_b.duration_min);
  END IF;

  UPDATE cleaning_bookings
  SET scheduled_at = p_new_scheduled_at,
      status = CASE WHEN v_keep THEN 'accepted' ELSE 'scheduled' END,
      cleaner_id = CASE WHEN v_keep THEN cleaner_id ELSE NULL END,
      accepted_at = CASE WHEN v_keep THEN accepted_at ELSE NULL END,
      offer_cleaner_id = NULL, offer_expires_at = NULL,
      offered_cleaner_ids = CASE WHEN v_keep THEN offered_cleaner_ids ELSE '{}'::uuid[] END,
      reminder_24h_sent_at = NULL, reminder_2h_sent_at = NULL
  WHERE id = p_booking_id;

  PERFORM public.log_admin_action('cleaning_rescheduled', 'cleaning_booking', p_booking_id::text,
    jsonb_build_object('old', v_b.scheduled_at, 'new', p_new_scheduled_at, 'kept_cleaner', v_keep));

  PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_rescheduled',
    'Limpeza reagendada',
    'A tua limpeza foi reagendada para ' ||
    to_char(p_new_scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') || '.',
    p_booking_id::text);

  IF NOT v_keep THEN
    PERFORM public._cleaning_next_offer(p_booking_id);
    IF v_b.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user(
        (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
        'cleaning_rescheduled', 'Limpeza reagendada',
        'Uma limpeza foi reagendada para um horário fora da tua disponibilidade e reatribuída.',
        p_booking_id::text);
    END IF;
  ELSIF v_b.cleaner_id IS NOT NULL THEN
    PERFORM public._cleaning_notify_user(
      (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
      'cleaning_rescheduled', 'Limpeza reagendada',
      'Uma limpeza da tua agenda mudou para ' ||
      to_char(p_new_scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') || '.',
      p_booking_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_reschedule_cleaning(uuid, timestamptz) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reschedule_cleaning(uuid, timestamptz) TO authenticated;

-- ---------- ADMIN: resumo de dinheiro em caixa (leitura, acerto manual) ----------
CREATE OR REPLACE FUNCTION public.admin_cleaning_cash_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'cleaner_id', c.id, 'cleaner_name', c.name,
      'cash_bookings', t.cnt, 'cash_bora_due_cents', t.due))
    FROM (
      SELECT cleaner_id, count(*) AS cnt, sum(bora_fee_cents) AS due
      FROM cleaning_bookings
      WHERE payment_method = 'cash' AND payment_status = 'cash_pending'
      GROUP BY cleaner_id
    ) t
    JOIN cleaners c ON c.id = t.cleaner_id
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_cleaning_cash_summary() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cleaning_cash_summary() TO authenticated;

-- ---------- ADMIN: marcar caixa entregue (acerto manual da semana) ----------
CREATE OR REPLACE FUNCTION public.admin_cleaning_mark_cash_settled(p_cleaner_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int;
BEGIN
  PERFORM public._admin_op_guard();
  UPDATE cleaning_bookings
  SET payment_status = 'cash_settled'
  WHERE cleaner_id = p_cleaner_id
    AND payment_method = 'cash' AND payment_status = 'cash_pending';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM public.log_admin_action('cleaning_cash_settled', 'cleaner', p_cleaner_id::text,
    jsonb_build_object('bookings', v_count));
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public.admin_cleaning_mark_cash_settled(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cleaning_mark_cash_settled(uuid) TO authenticated;

-- ============================================================================
-- CRONS (service_role/postgres — nunca expostos a authenticated)
-- ============================================================================

-- ofertas expiradas → próxima profissional (rotation 30 min)
CREATE OR REPLACE FUNCTION public._cleaning_cron_offer_timeout()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int := 0; v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id FROM cleaning_bookings
    WHERE status = 'scheduled' AND offer_cleaner_id IS NOT NULL
      AND offer_expires_at < now()
  LOOP
    UPDATE cleaning_bookings SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = v_rec.id;
    PERFORM public._cleaning_next_offer(v_rec.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_cron_offer_timeout() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_cron_offer_timeout() TO service_role;

-- auto-confirmação 24h após "done" (liberta pagamento)
CREATE OR REPLACE FUNCTION public._cleaning_cron_auto_confirm()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_hours int := public._cleaning_setting_int('cleaning_auto_confirm_hours', 24);
  v_count int := 0; v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id FROM cleaning_bookings
    WHERE status = 'done' AND done_at < now() - make_interval(hours => v_hours)
  LOOP
    PERFORM public._cleaning_complete(v_rec.id, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_cron_auto_confirm() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_cron_auto_confirm() TO service_role;

-- lembretes 24h (cliente + profissional)
CREATE OR REPLACE FUNCTION public._cleaning_cron_reminders_24h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int := 0; v_rec record;
BEGIN
  IF NOT public._cleaning_setting_bool('cleaning_reminder_24h_enabled', true) THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT b.*, c.user_id AS cleaner_user_id
    FROM cleaning_bookings b LEFT JOIN cleaners c ON c.id = b.cleaner_id
    WHERE b.status = 'accepted' AND b.reminder_24h_sent_at IS NULL
      AND b.scheduled_at BETWEEN now() + interval '23 hours' AND now() + interval '25 hours'
  LOOP
    PERFORM public._cleaning_notify_user(v_rec.client_user_id, 'cleaning_reminder',
      'Limpeza amanhã 🧹',
      'A tua limpeza é amanhã às ' ||
      to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || '.',
      v_rec.id::text);
    PERFORM public._cleaning_notify_user(v_rec.cleaner_user_id, 'cleaning_reminder',
      'Limpeza amanhã 🧹',
      'Tens uma limpeza amanhã às ' ||
      to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || ' em ' ||
      v_rec.address_city || '.',
      v_rec.id::text);
    UPDATE cleaning_bookings SET reminder_24h_sent_at = now() WHERE id = v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_cron_reminders_24h() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_cron_reminders_24h() TO service_role;

-- lembretes 2h
CREATE OR REPLACE FUNCTION public._cleaning_cron_reminders_2h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int := 0; v_rec record;
BEGIN
  IF NOT public._cleaning_setting_bool('cleaning_reminder_2h_enabled', true) THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT b.*, c.user_id AS cleaner_user_id
    FROM cleaning_bookings b LEFT JOIN cleaners c ON c.id = b.cleaner_id
    WHERE b.status = 'accepted' AND b.reminder_2h_sent_at IS NULL
      AND b.scheduled_at BETWEEN now() + interval '90 minutes' AND now() + interval '150 minutes'
  LOOP
    PERFORM public._cleaning_notify_user(v_rec.client_user_id, 'cleaning_reminder',
      'Limpeza daqui a 2 horas',
      'A tua limpeza começa às ' ||
      to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || '.',
      v_rec.id::text);
    PERFORM public._cleaning_notify_user(v_rec.cleaner_user_id, 'cleaning_reminder',
      'Limpeza daqui a 2 horas',
      'Começa às ' || to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') ||
      ' — ' || v_rec.address_street || ', ' || v_rec.address_city || '.',
      v_rec.id::text);
    UPDATE cleaning_bookings SET reminder_2h_sent_at = now() WHERE id = v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_cron_reminders_2h() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_cron_reminders_2h() TO service_role;

-- geração de recorrências: 7 dias antes da próxima ocorrência.
-- Série tenta SEMPRE a mesma profissional primeiro (requested_cleaner_id).
-- Série PÁRA se: cliente parou (cleaning_recurrence_stops) OU última ocorrência
-- foi cancelada pelo cliente.
CREATE OR REPLACE FUNCTION public.generate_recurring_bookings()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_count int := 0; v_rec record; v_last cleaning_bookings;
  v_next timestamptz; v_quote jsonb; v_id uuid; v_interval interval;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT recurrence_group_id AS gid FROM cleaning_bookings
    WHERE recurrence_group_id IS NOT NULL
      AND recurrence IN ('weekly','biweekly')
      AND NOT EXISTS (SELECT 1 FROM cleaning_recurrence_stops s
                      WHERE s.group_id = cleaning_bookings.recurrence_group_id)
  LOOP
    SELECT * INTO v_last FROM cleaning_bookings
    WHERE recurrence_group_id = v_rec.gid
    ORDER BY scheduled_at DESC LIMIT 1;

    -- cliente cancelou a última ocorrência → série pára (escolha documentada)
    CONTINUE WHEN v_last.status = 'cancelled_client' AND v_last.cancelled_by IN ('client','admin');

    v_interval := CASE v_last.recurrence WHEN 'weekly' THEN interval '7 days'
                                         ELSE interval '14 days' END;
    v_next := v_last.scheduled_at + v_interval;

    -- gera só quando faltam <= 7 dias para a próxima ocorrência
    CONTINUE WHEN v_next - now() > interval '7 days';
    CONTINUE WHEN v_next < now();  -- série morta há muito tempo

    -- preço recalculado com settings atuais (mantém desconto de recorrência)
    v_quote := public.cleaning_quote(v_last.cleaning_type, v_last.pricing_mode,
                                     v_last.home_size, v_last.hours,
                                     v_last.recurrence, v_last.products_by);

    INSERT INTO cleaning_bookings (
      client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
      cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
      address_street, address_city, address_postal, lat, lng, notes, products_by,
      payment_method, payment_status,
      base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
      total_cents, cleaner_earnings_cents, bora_fee_cents
    ) VALUES (
      v_last.client_user_id,
      COALESCE(v_last.cleaner_id, v_last.requested_cleaner_id),  -- favorita primeiro
      v_rec.gid, v_last.recurrence,
      v_last.cleaning_type, v_last.pricing_mode, v_last.home_size, v_last.hours,
      v_next, (v_quote ->> 'duration_min')::int,
      v_last.address_street, v_last.address_city, v_last.address_postal,
      v_last.lat, v_last.lng, v_last.notes, v_last.products_by,
      v_last.payment_method, 'unpaid',
      (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
      (v_quote ->> 'recurring_discount_cents')::int, (v_quote ->> 'products_fee_cents')::int,
      (v_quote ->> 'total_cents')::int, (v_quote ->> 'cleaner_earnings_cents')::int,
      (v_quote ->> 'bora_fee_cents')::int
    ) RETURNING id INTO v_id;

    PERFORM public._cleaning_next_offer(v_id);
    PERFORM public._cleaning_notify_user(v_last.client_user_id, 'cleaning_recurring',
      'Próxima limpeza agendada 🔁',
      'A tua limpeza recorrente de ' ||
      to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
      ' foi criada. Podes cancelar na app.',
      v_id::text);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public.generate_recurring_bookings() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_recurring_bookings() TO service_role;
