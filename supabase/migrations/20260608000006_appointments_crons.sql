-- ============================================================================
-- Serviços / Barbearias — pg_cron jobs (idempotente)
-- ============================================================================
-- remove versões antigas se existirem
SELECT cron.unschedule(jobid) FROM cron.job
WHERE jobname IN ('appt-reminders-24h','appt-reminders-2h','appt-auto-noshow','appt-weekly-payout');

-- Lembretes 24h — todos os dias às 10h
SELECT cron.schedule('appt-reminders-24h', '0 10 * * *',
  $$SELECT public._appointment_cron_send_reminders_24h();$$);

-- Lembretes 2h — de 30 em 30 min
SELECT cron.schedule('appt-reminders-2h', '*/30 * * * *',
  $$SELECT public._appointment_cron_send_reminders_2h();$$);

-- Auto no-show — de 15 em 15 min
SELECT cron.schedule('appt-auto-noshow', '*/15 * * * *',
  $$SELECT public._appointment_cron_auto_no_show();$$);

-- Liquidações semanais — segunda-feira às 8h
SELECT cron.schedule('appt-weekly-payout', '0 8 * * 1',
  $$SELECT public.compute_all_provider_weekly_payouts();$$);
