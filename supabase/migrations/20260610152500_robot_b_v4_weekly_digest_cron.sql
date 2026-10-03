-- ROBOT B v4 — cron do digest semanal (segunda 08:18 UTC ≈ 09:18 Lisboa).
-- Criado DESATIVADO (launch mode): restore_launch_mode.sql ativa no lançamento,
-- tal como o robot-b-hourly (jobid 35). Minuto :18 = escalonamento anti-colisão M3.
DO $$
DECLARE v_jobid bigint;
BEGIN
  SELECT cron.schedule(
    'robot-b-weekly-digest',
    '18 8 * * 1',
    $cron$
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
             || '/functions/v1/robot-b',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object('mode', 'digest')
    );
    $cron$
  ) INTO v_jobid;
  -- UPDATE direto em cron.job dá permission denied — usar sempre cron.alter_job.
  PERFORM cron.alter_job(v_jobid, active => false);
END $$;
