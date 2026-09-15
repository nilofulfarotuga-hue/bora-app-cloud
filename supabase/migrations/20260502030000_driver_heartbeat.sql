-- ============================================================================
-- BORA — Driver heartbeat (FASE 1 launch blocker)
-- ============================================================================
-- Driver app envia heartbeat a cada 30s. Cron marca offline drivers cujo
-- último heartbeat tem >90s (3 missed pings). Cobre crash do app, perda de
-- rede, app fechado sem toggle Offline. Cliente nunca chama driver fantasma.
-- ============================================================================

BEGIN;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_drivers_heartbeat
  ON public.drivers(last_heartbeat_at)
  WHERE is_online = true;

-- ── RPC: driver_heartbeat — chamado pelo Flutter a cada 30s ────────────────
CREATE OR REPLACE FUNCTION public.driver_heartbeat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.drivers
     SET last_heartbeat_at = v_now,
         is_online = true
   WHERE id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'driver_id', v_uid,
    'heartbeat_at', v_now
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.driver_heartbeat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat() TO authenticated;

-- ── RPC: mark_stale_drivers_offline — chamado por cron a cada minuto ───────
CREATE OR REPLACE FUNCTION public.mark_stale_drivers_offline()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INT;
BEGIN
  WITH stale AS (
    UPDATE public.drivers
       SET is_online = false
     WHERE is_online = true
       AND (last_heartbeat_at IS NULL
            OR last_heartbeat_at < (now() - interval '90 seconds'))
     RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM stale;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_stale_drivers_offline() FROM PUBLIC;

-- ── pg_cron: agenda mark-stale a cada minuto ───────────────────────────────
DO $$
BEGIN
  PERFORM cron.unschedule('mark-stale-drivers-offline');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'mark-stale-drivers-offline',
  '* * * * *',
  $$SELECT public.mark_stale_drivers_offline();$$
);

COMMIT;
