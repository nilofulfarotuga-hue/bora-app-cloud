-- Alinha repo↔produção (cloud migration 20260531064411, aplicada 2026-05-31).
-- Corrige bora_dispatch_maintenance: usa net.http_post (NÃO extensions.net.http_post,
-- que causava 'cross-database references are not implemented' e ~97.8% de falha do cron).
-- Reflete o ESTADO VIVO em produção (verificado por pg_get_functiondef 2026-05-31).
-- ZONA DISPATCH: este ficheiro é só REGISTO do que já está vivo — NÃO re-aplicar nem
-- alterar a lógica sem aprovação explícita do Danilo.

CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order             record;
  v_rejected_count    int := 0;
  v_cancelled_count   int := 0;
  v_drivers_online    int;
  v_jwt               text := public._dispatch_jwt();
  v_max_total_s       int;
  v_safety_s          int;
BEGIN
  SELECT (value::text)::int INTO v_max_total_s
    FROM public.platform_settings WHERE key = 'dispatch_max_total_seconds_with_drivers_online';
  v_max_total_s := COALESCE(v_max_total_s, 1200);

  SELECT (value::text)::int INTO v_safety_s
    FROM public.platform_settings WHERE key = 'dispatch_auto_cancel_safety_seconds';
  v_safety_s := COALESCE(v_safety_s, 1800);

  SELECT count(*) INTO v_drivers_online
    FROM public.drivers
    WHERE is_online = true
      AND last_heartbeat_at > NOW() - INTERVAL '90 seconds';

  WITH abandoned AS (
    UPDATE public.orders
       SET status         = 'cancelled',
           payment_status = 'failed',
           cancel_reason  = 'payment_abandoned'
     WHERE status = 'created' AND payment_status = 'pending'
       AND payment_method IN ('card', 'mbway')
       AND created_at < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;
  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] auto-cancelled % abandoned payment(s)', v_cancelled_count;
  END IF;

  IF v_drivers_online > 0 THEN
    UPDATE public.orders
       SET dispatch_online_attempt_seconds =
             COALESCE(dispatch_online_attempt_seconds, 0)
             + LEAST(
                 EXTRACT(EPOCH FROM (NOW() - COALESCE(dispatch_last_tick_at, NOW())))::int,
                 180
               ),
           dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  ELSE
    UPDATE public.orders
       SET dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  END IF;

  UPDATE public.orders
     SET dispatch_partner_decision_at = NULL,
         dispatch_extended_until      = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND dispatch_extended_until IS NOT NULL
     AND dispatch_extended_until < NOW();

  IF v_drivers_online > 0 THEN
    WITH expired AS (
      UPDATE public.orders
         SET status                  = 'cancelled',
             cancelled_at            = NOW(),
             cancellation_initiator  = 'system',
             cancel_reason           = 'dispatch_safety_timeout_with_drivers',
             current_driver_offer_id = NULL,
             driver_offer_expires_at = NULL
       WHERE status = 'callingDriver'
         AND assigned_driver_id IS NULL
         AND dispatch_online_attempt_seconds >= v_safety_s
       RETURNING id
    )
    SELECT count(*) INTO v_rejected_count FROM expired;
    IF v_rejected_count > 0 THEN
      RAISE NOTICE '[dispatch_maintenance] safety auto-cancel % order(s) (>%s s com drivers)',
        v_rejected_count, v_safety_s;
    END IF;
  END IF;

  UPDATE public.orders
     SET tried_driver_ids        = array_append(
                                     COALESCE(tried_driver_ids, '{}'::text[]),
                                     current_driver_offer_id
                                   ),
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id IS NOT NULL
     AND driver_offer_expires_at IS NOT NULL
     AND driver_offer_expires_at < NOW();

  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND current_driver_offer_id IS NULL
       AND (dispatch_extended_until IS NULL OR dispatch_extended_until > NOW())
  LOOP
    PERFORM net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$function$;
