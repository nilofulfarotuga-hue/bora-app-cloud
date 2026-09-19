-- Admin notification cron functions + pg_cron jobs
-- Applied via MCP on 2026-05-18, local file created on same date
-- pg_cron confirmed active on this project

CREATE OR REPLACE FUNCTION public._cron_check_orphan_orders()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT o.id, o.created_at, o.status, o.price
    FROM public.orders o
    WHERE o.status IN ('callingDriver', 'created', 'preparing')
      AND o.driver_id IS NULL
      AND o.created_at < now() - interval '10 minutes'
      AND o.created_at > now() - interval '2 hours'
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_notifications n
        WHERE n.event_type = 'order_orphan'
          AND n.entity_id = o.id::text
          AND n.created_at > now() - interval '1 hour'
      )
  LOOP
    PERFORM public.notify_admin_event(
      'order_orphan',
      'high',
      format('Pedido órfão há %s min: #%s (status=%s)',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60,
        substring(r.id::text, 1, 8),
        r.status),
      'order',
      r.id::text,
      jsonb_build_object('status', r.status, 'price', r.price, 'age_minutes',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60),
      '/admin/orders/' || r.id::text
    );
  END LOOP;
END;
$function$;

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._cron_check_stripe_failures()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT
      o.user_id,
      COUNT(*) as fail_count,
      MAX(o.created_at) as last_fail
    FROM public.orders o
    WHERE o.payment_status = 'failed'
      AND o.payment_method IN ('card', 'mbway', 'stripe')
      AND o.created_at > now() - interval '24 hours'
    GROUP BY o.user_id
    HAVING COUNT(*) >= 3
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.admin_notifications n
      WHERE n.event_type = 'stripe_repeated_fails'
        AND n.entity_id = r.user_id::text
        AND n.created_at > now() - interval '6 hours'
    ) THEN
      PERFORM public.notify_admin_event(
        'stripe_repeated_fails',
        'high',
        format('%s falhas Stripe nas últimas 24h (cliente %s)',
          r.fail_count, substring(r.user_id::text, 1, 8)),
        'client',
        r.user_id::text,
        jsonb_build_object('fail_count', r.fail_count, 'last_fail', r.last_fail),
        '/admin/clients'
      );
    END IF;
  END LOOP;
END;
$function$;

-- ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._cron_check_ghost_drivers()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT d.user_id, d.last_heartbeat_at
    FROM public.drivers d
    WHERE d.is_online = true
      AND (d.last_heartbeat_at IS NULL
           OR d.last_heartbeat_at < now() - interval '5 minutes')
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_notifications n
        WHERE n.event_type = 'driver_ghost'
          AND n.entity_id = d.user_id::text
          AND n.created_at > now() - interval '30 minutes'
      )
  LOOP
    PERFORM public.notify_admin_event(
      'driver_ghost',
      'medium',
      format('Driver online sem heartbeat há %s min',
        CASE
          WHEN r.last_heartbeat_at IS NULL THEN 'inicio'
          ELSE EXTRACT(EPOCH FROM (now() - r.last_heartbeat_at))::int / 60 || ''
        END),
      'driver',
      r.user_id::text,
      jsonb_build_object(
        'last_heartbeat_at', r.last_heartbeat_at,
        'age_minutes', CASE
          WHEN r.last_heartbeat_at IS NULL THEN NULL
          ELSE EXTRACT(EPOCH FROM (now() - r.last_heartbeat_at))::int / 60
        END
      ),
      '/admin/drivers'
    );
  END LOOP;
END;
$function$;

-- ── pg_cron jobs (idempotente) ───────────────
SELECT cron.schedule('admin-check-orphan-orders',  '*/5 * * * *', $$ SELECT public._cron_check_orphan_orders();  $$);
SELECT cron.schedule('admin-check-stripe-failures','*/5 * * * *', $$ SELECT public._cron_check_stripe_failures(); $$);
SELECT cron.schedule('admin-check-ghost-drivers',  '*/5 * * * *', $$ SELECT public._cron_check_ghost_drivers();  $$);
