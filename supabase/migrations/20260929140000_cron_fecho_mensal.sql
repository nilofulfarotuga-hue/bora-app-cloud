-- Agendamentos do fecho mensal (missão fecho-mensal-2026-09).
-- NÃO toca nos jobs 26/63 nem religa 43/58/69.
-- O pg_cron corre em UTC e o CRON_TZ não pega neste Debian: dispara-se às 08h e
-- às 09h UTC e quem é chamado só avança quando em Lisboa são 09h (inverno/verão).

-- B3: extrato mensal às lojas + resumo ao admin, dia 1 às 09:00 de Lisboa.
SELECT cron.schedule('monthly-partner-statement', '0 8,9 1 * *', $cron$
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
           || '/functions/v1/monthly-partner-statement',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := jsonb_build_object('cron', true),
    timeout_milliseconds := 60000);
$cron$);

-- B6A: dia 10 às 09:00 de Lisboa, avisa o admin de quem não passou o recibo verde.
SELECT cron.schedule('aviso-recibos-estafetas', '0 8,9 10 * *', $cron$
  SELECT public.aviso_recibos_estafetas_em_falta()
   WHERE extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon')) = 9;
$cron$);
