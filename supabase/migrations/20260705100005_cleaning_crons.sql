-- ============================================================================
-- LIMPEZA — pg_cron jobs (idempotente)
-- ============================================================================
SELECT cron.unschedule(jobid) FROM cron.job
WHERE jobname IN ('cleaning-offer-timeout','cleaning-auto-confirm',
                  'cleaning-reminders-24h','cleaning-reminders-2h',
                  'cleaning-generate-recurring');

-- rotation de ofertas (timeout 30 min) — de 5 em 5 min
SELECT cron.schedule('cleaning-offer-timeout', '*/5 * * * *',
  $$SELECT public._cleaning_cron_offer_timeout();$$);

-- auto-confirmação 24h após concluída — de 30 em 30 min
SELECT cron.schedule('cleaning-auto-confirm', '*/30 * * * *',
  $$SELECT public._cleaning_cron_auto_confirm();$$);

-- lembretes 24h — de hora a hora (janela 23h–25h, sem duplicados)
SELECT cron.schedule('cleaning-reminders-24h', '5 * * * *',
  $$SELECT public._cleaning_cron_reminders_24h();$$);

-- lembretes 2h — de 30 em 30 min (janela 90–150 min)
SELECT cron.schedule('cleaning-reminders-2h', '*/30 * * * *',
  $$SELECT public._cleaning_cron_reminders_2h();$$);

-- recorrências — diário às 08h (gera 7 dias antes, favorita primeiro)
SELECT cron.schedule('cleaning-generate-recurring', '0 8 * * *',
  $$SELECT public.generate_recurring_bookings();$$);
