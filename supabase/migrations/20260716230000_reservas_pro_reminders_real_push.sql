-- ═══════════════════════════════════════════════════════════════════════════
-- RESERVAS PRO — lembretes 24h/2h passam a enviar push real (FCM) + reativa os crons
-- ═══════════════════════════════════════════════════════════════════════════
-- Aprovação (robot_suggestions id 20248533-a225-4e7a-b25c-85ad74656cbd, categoria
-- "marcacoes", nível 3, revisto 2026-07-16 06:37 UTC):
--   "APROVAÇÃO PARCIAL (Danilo via Claude.ai 16/07): SÓ lembretes push antes da
--    marcação. NÃO mexer em depósito/pré-pagamento €3 — pouco dado (1 no-show em 6)."
--
-- Esta migration NÃO toca reservations.deposit_cents / reservation_prepayment_cents /
-- nenhum valor cobrado — só a via de notificação e o agendamento do cron.
--
-- Estado encontrado (investigação 2026-07-16, live via MCP):
--   • As funções _reservas_pro_cron_send_reminders_24h/2h já existiam (migration
--     20260509000453_reservas_pro_f2d_cron_jobs.sql) e já tinham sido criadas
--     ATIVAS, mas em algum momento os jobs 'reservas_pro_reminders_24h' e
--     'reservas_pro_reminders_2h' ficaram active=false em cron.job — ninguém disparava.
--   • Mesmo se ativos, as funções só chamavam _push_in_app_notification (grava em
--     in_app_notifications) — NUNCA enviavam push FCM real. Comparar com o equivalente
--     de appointments (_appt_notify_client), que já está ativo E já envia FCM real via
--     POST a supabase/functions/notify-client (esse continua intocado — só serve de
--     referência do padrão a replicar aqui).
--
-- Mudança: as duas funções passam a chamar também net.http_post para
-- /functions/v1/notify-client (mesmo padrão de _appt_notify_client — clientId/title/body,
-- sem orderId, best-effort dentro de BEGIN/EXCEPTION para nunca abortar o cron). Os dois
-- jobs de reminder são reativados. reservas_pro_expire_lists / morning_summary /
-- pending_alert permanecem como estavam (fora de escopo — motivo do disable desconhecido,
-- não mexido).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._reservas_pro_cron_send_reminders_24h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_enabled boolean;
  v_count integer := 0;
  v_url text;
  v_key text;
  v_title text;
  v_body text;
BEGIN
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
    v_title := 'Reserva amanhã!';
    v_body := 'Lembramos a tua reserva amanhã às ' || to_char(v_record.reserved_for, 'HH24:MI') || ' • ' || v_record.people || ' pessoas';

    PERFORM _push_in_app_notification(v_record.client_user_id, 'reservation_reminder_24h', v_title, v_body, v_record.id::text);

    BEGIN
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
      IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
          body := jsonb_build_object('clientId', v_record.client_user_id::text, 'title', v_title, 'body', v_body)
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    UPDATE reservations SET reminder_24h_sent_at = NOW() WHERE id = v_record.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public._reservas_pro_cron_send_reminders_2h()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_record record;
  v_enabled boolean;
  v_count integer := 0;
  v_url text;
  v_key text;
  v_title text;
  v_body text;
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
    v_title := 'Reserva em 2 horas';
    v_body := 'A tua reserva é às ' || to_char(v_record.reserved_for, 'HH24:MI') || ' • ' || v_record.people || ' pessoas';

    PERFORM _push_in_app_notification(v_record.client_user_id, 'reservation_reminder_2h', v_title, v_body, v_record.id::text);

    BEGIN
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
      IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
          body := jsonb_build_object('clientId', v_record.client_user_id::text, 'title', v_title, 'body', v_body)
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    UPDATE reservations SET reminder_2h_sent_at = NOW() WHERE id = v_record.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Reativa só os dois jobs de lembrete (os outros 3 da família reservas_pro ficam como
-- estavam — fora de escopo desta pendência).
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'reservas_pro_reminders_24h'), active := true);
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'reservas_pro_reminders_2h'), active := true);
