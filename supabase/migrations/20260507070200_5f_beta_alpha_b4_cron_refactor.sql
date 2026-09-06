-- 5F-β-α B4: Refactor cron job analyze-conversations-weekly (5D)
-- jobid 28, schedule preservado: 0 4 * * 1
-- current_setting → vault.decrypted_secrets
-- Aplicado via apply_migration: 5f_beta_alpha_b4_cron_refactor (2026-05-07)

SELECT cron.alter_job(
  job_id  := 28,
  command := $cron$
  SELECT net.http_post(
    url     := (SELECT decrypted_secret FROM vault.decrypted_secrets
                WHERE name = 'project_url') ||
               '/functions/v1/analyze-conversations',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret
                                     FROM vault.decrypted_secrets
                                     WHERE name = 'service_role_key'),
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'scheduled', true,
      'days_back', 7,
      'dry_run',   false
    )
  );
  $cron$
);
