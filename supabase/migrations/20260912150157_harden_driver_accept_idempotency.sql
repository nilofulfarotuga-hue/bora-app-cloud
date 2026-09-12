-- Makes repeated acceptance by the winning driver idempotent.

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

REVOKE ALL ON FUNCTION public.driver_accept_offer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_accept_offer(text) TO authenticated;
