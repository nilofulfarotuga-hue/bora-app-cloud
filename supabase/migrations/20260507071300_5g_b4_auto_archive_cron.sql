-- 5G B4: Cron auto-archive >30 dias pending → auto_archived

CREATE OR REPLACE FUNCTION public._auto_archive_old_suggestions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_count int;
BEGIN
  UPDATE skill_suggestions
  SET status = 'auto_archived',
      reviewed_at = now()
  WHERE status = 'pending'
    AND suggested_at < now() - interval '30 days';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'Auto-archived % old pending suggestions', v_count;
  RETURN v_count;
END; $$;

REVOKE ALL ON FUNCTION public._auto_archive_old_suggestions() FROM public, anon;

-- Cron job: diária 03:00 UTC (idempotente — unschedule existente se houver)
DO $$
BEGIN
  PERFORM cron.unschedule('auto-archive-old-suggestions')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='auto-archive-old-suggestions');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'auto-archive-old-suggestions',
  '0 3 * * *',
  $cron$ SELECT public._auto_archive_old_suggestions(); $cron$
);
