-- F5 (MISSAO TOTAL 2026-08-15): GUARDA contra limpeza presa em curso.
-- Caso real: 59bdcbcd ficou 'in_progress' 9 dias sem ninguem saber.
-- A guarda NAO fecha sozinha (fechar = dinheiro; decisao humana no painel).
-- Deteta e avisa o admin 1x por booking (stuck_alerted_at), cron horario.
-- APLICADA em producao a 2026-08-16 (cleaning_guarda_presa_in_progress_f5_2026_08_16).

ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS stuck_alerted_at timestamptz;

CREATE OR REPLACE FUNCTION public._cleaning_cron_stuck_in_progress()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hours int := public._cleaning_setting_int('cleaning_stuck_alert_hours', 6);
  v_count int := 0;
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id, status, scheduled_at, total_cents, payment_method
    FROM cleaning_bookings
    WHERE status IN ('on_the_way', 'in_progress')
      AND scheduled_at < now() - make_interval(hours => v_hours)
      AND stuck_alerted_at IS NULL
  LOOP
    PERFORM public._cleaning_notify_admin(
      'Limpeza presa em ' || v_rec.status,
      'Booking ' || left(v_rec.id::text, 8) || ' agendada para ' ||
      to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' continua ' || v_rec.status || ' (' || v_rec.payment_method || ', EUR ' ||
      to_char(v_rec.total_cents / 100.0, 'FM999990.00') ||
      '). Fechar (concluir ou cancelar) no painel.');
    UPDATE cleaning_bookings SET stuck_alerted_at = now() WHERE id = v_rec.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$;

REVOKE ALL ON FUNCTION public._cleaning_cron_stuck_in_progress() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cleaning_cron_stuck_in_progress() FROM anon;
REVOKE ALL ON FUNCTION public._cleaning_cron_stuck_in_progress() FROM authenticated;

SELECT cron.schedule(
  'cleaning-stuck-in-progress-alert',
  '15 * * * *',
  'SELECT public._cleaning_cron_stuck_in_progress();'
);
