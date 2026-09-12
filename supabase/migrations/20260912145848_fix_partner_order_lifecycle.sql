-- Goola incident: make partner/driver lifecycle transitions authoritative,
-- observable and idempotent. No financial amount is changed here.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS status_updated_at timestamptz;

UPDATE public.orders
SET status_updated_at = COALESCE(dispatch_calling_since, delivered_at, created_at, now())
WHERE status_updated_at IS NULL;

ALTER TABLE public.orders
  ALTER COLUMN status_updated_at SET DEFAULT now(),
  ALTER COLUMN status_updated_at SET NOT NULL;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_canonical_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_canonical_check CHECK (
    status IS NOT NULL AND status IN (
      'created', 'preparing', 'readyForPickup', 'callingDriver',
      'driverAccepted', 'pickedUp', 'onTheWay', 'delivered',
      'rejected', 'cancelled'
    )
  ) NOT VALID;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_canonical_check;

CREATE OR REPLACE FUNCTION public._set_order_status_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.status_updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_order_status_updated_at ON public.orders;
CREATE TRIGGER trg_set_order_status_updated_at
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public._set_order_status_updated_at();

CREATE TABLE IF NOT EXISTS public.order_status_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id text NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_uid uuid,
  source text NOT NULL DEFAULT 'database_update',
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_order_status_events_order_time
  ON public.order_status_events(order_id, occurred_at DESC);

ALTER TABLE public.order_status_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.order_status_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.order_status_events TO authenticated;

DROP POLICY IF EXISTS order_status_events_participants_select
  ON public.order_status_events;
CREATE POLICY order_status_events_participants_select
ON public.order_status_events
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = order_status_events.order_id
      AND (
        o.user_id = (SELECT auth.uid())
        OR o.assigned_driver_id = (SELECT auth.uid())::text
        OR o.driver_id = (SELECT auth.uid())
        OR EXISTS (
          SELECT 1 FROM public.drivers d
          WHERE d.user_id = (SELECT auth.uid())
            AND d.id::text = o.assigned_driver_id
        )
        OR EXISTS (
          SELECT 1 FROM public.restaurants r
          WHERE r.user_id = (SELECT auth.uid())
            AND (r.id = o.restaurant_id OR
                 (o.restaurant_id IS NULL AND r.name = o.vendor_name))
        )
        OR public.is_admin()
      )
  )
);

CREATE OR REPLACE FUNCTION public._record_order_status_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  v_source := COALESCE(
    NULLIF(current_setting('app.order_transition_source', true), ''),
    'database_update'
  );
  INSERT INTO public.order_status_events(
    order_id, from_status, to_status, actor_uid, source
  ) VALUES (
    NEW.id, OLD.status, NEW.status, auth.uid(), v_source
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_order_status_event ON public.orders;
CREATE TRIGGER trg_record_order_status_event
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public._record_order_status_event();

CREATE OR REPLACE FUNCTION public._partner_owns_order(
  p_order_id text,
  p_uid uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.restaurants r
      ON r.id = o.restaurant_id
      OR (o.restaurant_id IS NULL AND r.name = o.vendor_name)
    WHERE o.id = p_order_id
      AND r.user_id = p_uid
      AND COALESCE(r.is_partner, false)
      AND COALESCE(r.is_active_admin, true)
      AND r.approval_status = 'approved'
  );
$$;

REVOKE ALL ON FUNCTION public._partner_owns_order(text, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.partner_accept_order(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF NOT public._partner_owns_order(p_order_id, v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT COALESCE(v_order.is_partner_store, false)
     OR v_order.service_type <> 'restaurant' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'wrong_order_type');
  END IF;
  IF v_order.status = 'preparing' THEN
    RETURN jsonb_build_object('ok', true, 'status', 'preparing', 'idempotent', true);
  END IF;
  IF v_order.status <> 'created' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_status',
                              'status', v_order.status);
  END IF;
  PERFORM set_config('app.order_transition_source', 'partner_accept_order', true);
  UPDATE public.orders SET status = 'preparing'
   WHERE id = p_order_id AND status = 'created';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', 'preparing');
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_reject_order(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF NOT public._partner_owns_order(p_order_id, v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF v_order.status = 'rejected' THEN
    RETURN jsonb_build_object('ok', true, 'status', 'rejected', 'idempotent', true);
  END IF;
  IF v_order.status <> 'created' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_status',
                              'status', v_order.status);
  END IF;
  PERFORM set_config('app.order_transition_source', 'partner_reject_order', true);
  UPDATE public.orders SET status = 'rejected'
   WHERE id = p_order_id AND status = 'created';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', 'rejected');
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_mark_ready(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF NOT public._partner_owns_order(p_order_id, v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT COALESCE(v_order.is_partner_store, false)
     OR v_order.service_type <> 'restaurant' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'wrong_order_type');
  END IF;
  IF v_order.status IN ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay', 'delivered') THEN
    RETURN jsonb_build_object('ok', true, 'status', v_order.status,
                              'idempotent', true);
  END IF;
  IF v_order.status <> 'preparing' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_status',
                              'status', v_order.status);
  END IF;
  IF COALESCE(v_order.payment_method, '') <> 'cash'
     AND v_order.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payment_not_confirmed');
  END IF;
  PERFORM set_config('app.order_transition_source', 'partner_mark_ready', true);
  UPDATE public.orders SET status = 'callingDriver'
   WHERE id = p_order_id AND status = 'preparing';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', 'callingDriver');
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_advance_order(
  p_order_id text,
  p_target_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_is_mine boolean;
  v_expected text;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_target_status NOT IN ('pickedUp', 'onTheWay') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'target_not_allowed');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  v_is_mine := v_order.assigned_driver_id = v_uid::text
    OR EXISTS (
      SELECT 1 FROM public.drivers d
      WHERE d.user_id = v_uid AND d.id::text = v_order.assigned_driver_id
    );
  IF NOT v_is_mine THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_your_order');
  END IF;
  IF (p_target_status = 'pickedUp' AND v_order.status IN ('pickedUp','onTheWay','delivered'))
     OR (p_target_status = 'onTheWay' AND v_order.status IN ('onTheWay','delivered')) THEN
    RETURN jsonb_build_object('ok', true, 'status', v_order.status,
                              'idempotent', true);
  END IF;
  v_expected := CASE p_target_status
    WHEN 'pickedUp' THEN 'driverAccepted'
    WHEN 'onTheWay' THEN 'pickedUp'
  END;
  IF v_order.status <> v_expected THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_status',
                              'status', v_order.status);
  END IF;
  PERFORM set_config('app.order_transition_source', 'driver_advance_order', true);
  UPDATE public.orders
     SET status = p_target_status,
         driver_id = COALESCE(driver_id, v_uid)
   WHERE id = p_order_id AND status = v_expected;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', p_target_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_finish_cash_order(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_is_mine boolean;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  v_is_mine := v_order.assigned_driver_id = v_uid::text
    OR EXISTS (
      SELECT 1 FROM public.drivers d
      WHERE d.user_id = v_uid AND d.id::text = v_order.assigned_driver_id
    );
  IF NOT v_is_mine THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_your_order');
  END IF;
  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('ok', true, 'status', 'delivered',
                              'idempotent', true);
  END IF;
  IF v_order.status <> 'onTheWay' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_status',
                              'status', v_order.status);
  END IF;
  IF v_order.payment_method <> 'cash' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pin_required');
  END IF;
  PERFORM set_config('app.order_transition_source',
                     'driver_finish_cash_order', true);
  UPDATE public.orders
     SET status = 'delivered',
         delivered_at = now(),
         driver_id = COALESCE(driver_id, v_uid)
   WHERE id = p_order_id AND status = 'onTheWay';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', 'delivered');
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_accept_offer(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;
  PERFORM set_config('app.order_transition_source', 'driver_accept_offer', true);
  UPDATE public.orders
     SET assigned_driver_id = v_uid::text,
         driver_id = v_uid,
         status = 'driverAccepted',
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL,
         driver_phone = COALESCE(
           driver_phone,
           (SELECT d.phone FROM public.drivers d
             WHERE d.user_id = v_uid LIMIT 1)
         )
   WHERE id = p_order_id
     AND status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id = v_uid::text;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE id = p_order_id
        AND assigned_driver_id = v_uid::text
        AND status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')
    ) THEN
      RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                                'status', 'driverAccepted',
                                'idempotent', true);
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'offer_expired_or_taken');
  END IF;
  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                            'status', 'driverAccepted');
END;
$$;

CREATE OR REPLACE FUNCTION public._guard_order_driver_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')
     AND COALESCE(NEW.service_type, '') <> 'takeaway'
     AND (NEW.driver_id IS NULL OR NEW.assigned_driver_id IS NULL) THEN
    RAISE EXCEPTION
      'order_driver_required: status % requires driver_id and assigned_driver_id',
      NEW.status
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_order_driver_state ON public.orders;
CREATE TRIGGER trg_guard_order_driver_state
BEFORE INSERT OR UPDATE OF status, driver_id, assigned_driver_id
ON public.orders
FOR EACH ROW EXECUTE FUNCTION public._guard_order_driver_state();

-- Existing public/anonymous grants were unsafe for partner mutations.
REVOKE ALL ON FUNCTION public.partner_accept_order(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.partner_reject_order(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.partner_mark_ready(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_advance_order(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_finish_cash_order(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_accept_offer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_accept_order(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_reject_order(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_mark_ready(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_advance_order(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_finish_cash_order(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_accept_offer(text) TO authenticated;

-- Keep the safety net, but measure the timeout from the current preparing
-- phase and do not abandon orders merely because they became older than 3h.
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
      RAISE WARNING '[partner_auto_dispatch] order % failed: %',
                    v_order.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.partner_auto_dispatch_ready_orders()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.partner_auto_dispatch_ready_orders()
  TO service_role;
