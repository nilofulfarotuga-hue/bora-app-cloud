-- Persist failures from the partner dispatch safety net. Previously its
-- exception handler emitted only a transient NOTICE, while cron still showed
-- the run as succeeded.

CREATE TABLE IF NOT EXISTS public.order_lifecycle_errors (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id text REFERENCES public.orders(id) ON DELETE CASCADE,
  component text NOT NULL,
  error_message text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  context jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_order_lifecycle_errors_order_time
  ON public.order_lifecycle_errors(order_id, occurred_at DESC);

ALTER TABLE public.order_lifecycle_errors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.order_lifecycle_errors
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.order_lifecycle_errors TO authenticated;

DROP POLICY IF EXISTS order_lifecycle_errors_admin_select
  ON public.order_lifecycle_errors;
CREATE POLICY order_lifecycle_errors_admin_select
ON public.order_lifecycle_errors
FOR SELECT TO authenticated
USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.partner_auto_dispatch_ready_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_min integer;
  v_order record;
BEGIN
  SELECT (value::text)::integer INTO v_min
    FROM public.platform_settings
   WHERE key = 'partner_auto_dispatch_after_minutes';
  v_min := COALESCE(v_min, 5);
  IF v_min <= 0 THEN RETURN; END IF;

  FOR v_order IN
    SELECT id
      FROM public.orders
     WHERE status = 'preparing'
       AND COALESCE(is_partner_store, false)
       AND service_type = 'restaurant'
       AND assigned_driver_id IS NULL
       AND driver_id IS NULL
       AND status_updated_at < now() - make_interval(mins => v_min)
       AND (COALESCE(payment_method, 'cash') = 'cash' OR payment_status = 'paid')
     ORDER BY status_updated_at
     LIMIT 50
     FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM set_config('app.order_transition_source',
                         'partner_auto_dispatch_ready_orders', true);
      UPDATE public.orders SET status = 'callingDriver'
       WHERE id = v_order.id AND status = 'preparing';
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_lifecycle_errors(
        order_id, component, error_message
      ) VALUES (
        v_order.id, 'partner_auto_dispatch_ready_orders', SQLERRM
      );
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.partner_auto_dispatch_ready_orders()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.partner_auto_dispatch_ready_orders()
  TO service_role;
