-- Completes the driver-side half of the Goola lifecycle correction.

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

-- Reassert least-privilege grants for the driver RPCs added above.
REVOKE ALL ON FUNCTION public.driver_finish_cash_order(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_accept_offer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_finish_cash_order(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_accept_offer(text) TO authenticated;
