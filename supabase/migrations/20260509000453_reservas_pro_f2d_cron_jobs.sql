-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F2.D — CRON Jobs (4)
-- Data: 2026-05-08 / Sessao reservas-pro-F2-BACKEND-CORE
--
-- 4 CRON jobs via pg_cron:
-- 1. Reminders 24h antes (a cada 30min)
-- 2. Reminders 2h antes (a cada 15min)
-- 3. Pending too long (>5min sem resposta) — push parceiro lembrete
-- 4. Morning summary 8h da manha — sumario reservas hoje ao parceiro
--
-- Tambem:
-- - Expirar waitlist + notify_list antigos
-- - Mark no_show automatico (passou reservation_no_show_grace_minutes)
-- ═══════════════════════════════════════════════════════════

-- ─── FUNÇÃO: send reminder 24h ──────────────────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_cron_send_reminders_24h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_enabled boolean;
  v_count integer := 0;
BEGIN
  -- Setting toggle
  SELECT (value::text)::boolean INTO v_enabled FROM platform_settings WHERE key = 'reservation_reminder_24h_enabled';
  IF NOT COALESCE(v_enabled, true) THEN RETURN 0; END IF;

  FOR v_record IN
    SELECT id, client_user_id, client_name, reserved_for, restaurant_id, people
    FROM reservations
    WHERE status IN ('approved','confirmed')
      AND reminder_24h_sent_at IS NULL
      AND reserved_for BETWEEN NOW() + interval '23 hours' AND NOW() + interval '25 hours'
      AND client_user_id IS NOT NULL
  LOOP
    PERFORM _push_in_app_notification(
      v_record.client_user_id,
      'reservation_reminder_24h',
      'Reserva amanha!',
      'Lembramos a tua reserva amanha as ' || to_char(v_record.reserved_for, 'HH24:MI') || ' • ' || v_record.people || ' pessoas',
      v_record.id::text
    );
    UPDATE reservations SET reminder_24h_sent_at = NOW() WHERE id = v_record.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── FUNÇÃO: send reminder 2h ───────────────────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_cron_send_reminders_2h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_enabled boolean;
  v_count integer := 0;
BEGIN
  SELECT (value::text)::boolean INTO v_enabled FROM platform_settings WHERE key = 'reservation_reminder_2h_enabled';
  IF NOT COALESCE(v_enabled, true) THEN RETURN 0; END IF;

  FOR v_record IN
    SELECT id, client_user_id, reserved_for, restaurant_id, people
    FROM reservations
    WHERE status IN ('approved','confirmed')
      AND reminder_2h_sent_at IS NULL
      AND reserved_for BETWEEN NOW() + interval '105 minutes' AND NOW() + interval '135 minutes'
      AND client_user_id IS NOT NULL
  LOOP
    PERFORM _push_in_app_notification(
      v_record.client_user_id,
      'reservation_reminder_2h',
      'Reserva em 2 horas',
      'A tua reserva e as ' || to_char(v_record.reserved_for, 'HH24:MI') || ' • ' || v_record.people || ' pessoas',
      v_record.id::text
    );
    UPDATE reservations SET reminder_2h_sent_at = NOW() WHERE id = v_record.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── FUNÇÃO: pending too long (>5min) ───────────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_cron_pending_too_long()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_partner_user_id uuid;
  v_count integer := 0;
  v_already_alerted text := 'reservation_pending_alert';  -- kind do alerta
BEGIN
  -- Reservas pending criadas ha 5-10min sem resposta -> push parceiro urgente
  -- (>10min nao alerta novamente; admin escalation seria outra logica)
  FOR v_record IN
    SELECT r.id, r.restaurant_id, r.client_name, r.people, r.reserved_for, r.created_at
    FROM reservations r
    WHERE r.status = 'pending'
      AND r.created_at BETWEEN NOW() - interval '10 minutes' AND NOW() - interval '5 minutes'
      AND NOT EXISTS (
        -- Nao re-alertar (in_app_notifications ja tem este alerta)
        SELECT 1 FROM in_app_notifications n
        WHERE n.related_id = r.id::text
          AND n.kind = v_already_alerted
      )
  LOOP
    v_partner_user_id := _reservas_pro_get_partner_user_id(v_record.restaurant_id);
    PERFORM _reservas_pro_notify_partner_push(
      v_partner_user_id,
      v_already_alerted,
      'Reserva pendente >5min!',
      'Urgente: ' || v_record.client_name || ' aguarda resposta • ' || v_record.people || ' pessoas',
      v_record.id::text
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── FUNÇÃO: morning summary 8h ─────────────────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_cron_morning_summary()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_partner_user_id uuid;
  v_count integer := 0;
BEGIN
  -- Para cada restaurante com reservas hoje, push summary ao parceiro
  FOR v_record IN
    SELECT r.restaurant_id, COUNT(*) as total, SUM(r.people) as total_pessoas,
           SUM(CASE WHEN cp.is_vip THEN 1 ELSE 0 END) as vips
    FROM reservations r
    LEFT JOIN client_restaurant_profiles cp
      ON cp.client_user_id = r.client_user_id AND cp.restaurant_id = r.restaurant_id
    WHERE r.status IN ('approved','confirmed')
      AND r.reserved_for::date = CURRENT_DATE
    GROUP BY r.restaurant_id
  LOOP
    v_partner_user_id := _reservas_pro_get_partner_user_id(v_record.restaurant_id);
    PERFORM _reservas_pro_notify_partner_push(
      v_partner_user_id,
      'morning_summary',
      'Reservas hoje: ' || v_record.total,
      v_record.total_pessoas || ' pessoas no total' ||
        CASE WHEN v_record.vips > 0 THEN ' • ' || v_record.vips || ' VIPs' ELSE '' END,
      CURRENT_DATE::text
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── FUNÇÃO: expire waitlist + notify_list ──────────────────
CREATE OR REPLACE FUNCTION public._reservas_pro_cron_expire_lists()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_waitlist_expired integer;
  v_notify_expired integer;
  v_waitlist_expiry_hours integer;
BEGIN
  SELECT (value::text)::integer INTO v_waitlist_expiry_hours
  FROM platform_settings WHERE key = 'reservation_waitlist_expiry_hours';
  v_waitlist_expiry_hours := COALESCE(v_waitlist_expiry_hours, 4);

  -- Waitlist: expira X horas apos created_at (ou se data passou)
  WITH expired AS (
    UPDATE reservation_waitlist
    SET status = 'expired', expired_at = NOW()
    WHERE status = 'waiting'
      AND (
        target_date < CURRENT_DATE OR
        created_at < NOW() - (v_waitlist_expiry_hours || ' hours')::interval
      )
    RETURNING 1
  )
  SELECT count(*) INTO v_waitlist_expired FROM expired;

  -- Notify list: expira em expires_at OU se data passou
  WITH expired AS (
    UPDATE reservation_notify_list
    SET status = 'expired'
    WHERE status IN ('active','notified')
      AND (
        expires_at < NOW() OR
        target_date < CURRENT_DATE
      )
    RETURNING 1
  )
  SELECT count(*) INTO v_notify_expired FROM expired;

  RETURN jsonb_build_object(
    'waitlist_expired', v_waitlist_expired,
    'notify_expired', v_notify_expired
  );
END;
$$;

-- ─── REGISTAR pg_cron jobs ──────────────────────────────────
-- Reminders 24h: a cada 30min
SELECT cron.schedule(
  'reservas_pro_reminders_24h',
  '*/30 * * * *',
  $cron$SELECT public._reservas_pro_cron_send_reminders_24h();$cron$
);

-- Reminders 2h: a cada 15min
SELECT cron.schedule(
  'reservas_pro_reminders_2h',
  '*/15 * * * *',
  $cron$SELECT public._reservas_pro_cron_send_reminders_2h();$cron$
);

-- Pending too long: a cada 1min
SELECT cron.schedule(
  'reservas_pro_pending_alert',
  '* * * * *',
  $cron$SELECT public._reservas_pro_cron_pending_too_long();$cron$
);

-- Morning summary: 8h da manha (Lisboa = UTC+0/+1, vou usar 8 UTC = 8h/9h Portugal)
SELECT cron.schedule(
  'reservas_pro_morning_summary',
  '0 8 * * *',
  $cron$SELECT public._reservas_pro_cron_morning_summary();$cron$
);

-- Expire lists: a cada hora
SELECT cron.schedule(
  'reservas_pro_expire_lists',
  '0 * * * *',
  $cron$SELECT public._reservas_pro_cron_expire_lists();$cron$
);