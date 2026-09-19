-- Production-schema E2E. All rows and side effects are rolled back.
BEGIN;

DO $$
DECLARE
  v_payload jsonb;
  v_columns text;
BEGIN
  SELECT to_jsonb(o) || jsonb_build_object(
      'id', '11111111-2222-4333-8444-555555555555',
      'status', 'created',
      'status_updated_at', now(),
      'payment_method', 'mbway',
      'payment_status', 'paid',
      'is_test_order', false,
      'created_at', now(),
      'driver_id', NULL,
      'assigned_driver_id', NULL,
      'current_driver_offer_id', NULL,
      'driver_offer_expires_at', NULL,
      'driver_offer_history', '[]'::jsonb,
      'tried_driver_ids', '[]'::jsonb,
      'dispatch_calling_since', NULL,
      'dispatch_last_tick_at', NULL,
      'delivered_at', NULL,
      'payment_intent_id', NULL
    )
  INTO v_payload
  FROM public.orders o
  WHERE o.id = 'ae711470-5a83-4fb9-9859-438ccd5efb84';

  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_columns
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'orders'
     AND is_generated = 'NEVER'
     AND is_identity = 'NO';

  EXECUTE format(
    'INSERT INTO public.orders (%1$s) SELECT %1$s
       FROM jsonb_populate_record(NULL::public.orders, $1)',
    v_columns
  ) USING v_payload;
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"4f61dd31-5e9e-4a7c-a557-7d53d2ceded7"}',
  true
);

DO $$
DECLARE
  v_rows integer;
  v_result jsonb;
BEGIN
  UPDATE public.orders SET status = 'preparing'
   WHERE id = '11111111-2222-4333-8444-555555555555';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'RLS allowed a non-partner to update the order';
  END IF;
  v_result := public.partner_accept_order(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'error' <> 'forbidden' THEN
    RAISE EXCEPTION 'partner authorization failed: %', v_result;
  END IF;
END;
$$;

RESET ROLE;
DO $$
BEGIN
  BEGIN
    UPDATE public.orders SET status = 'calling_driver'
     WHERE id = '11111111-2222-4333-8444-555555555555';
    RAISE EXCEPTION 'snake_case status was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  BEGIN
    UPDATE public.orders SET status = 'driverAccepted'
     WHERE id = '11111111-2222-4333-8444-555555555555';
    RAISE EXCEPTION 'driverAccepted without driver was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"c4859e42-0a7c-4d16-87fb-e7a9c48d61bc"}',
  true
);

DO $$
DECLARE v_result jsonb;
BEGIN
  v_result := public.partner_accept_order(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'status' <> 'preparing' THEN
    RAISE EXCEPTION 'partner_accept failed: %', v_result;
  END IF;
  v_result := public.partner_accept_order(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'idempotent' <> 'true' THEN
    RAISE EXCEPTION 'partner_accept idempotency failed: %', v_result;
  END IF;
  v_result := public.partner_mark_ready(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'status' <> 'callingDriver' THEN
    RAISE EXCEPTION 'partner_mark_ready failed: %', v_result;
  END IF;
  v_result := public.partner_mark_ready(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'idempotent' <> 'true' THEN
    RAISE EXCEPTION 'partner_mark_ready idempotency failed: %', v_result;
  END IF;
END;
$$;

RESET ROLE;
UPDATE public.orders
SET current_driver_offer_id = '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7',
    driver_offer_expires_at = now() + interval '40 seconds'
WHERE id = '11111111-2222-4333-8444-555555555555';

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"4f61dd31-5e9e-4a7c-a557-7d53d2ceded7"}',
  true
);

DO $$
DECLARE v_result jsonb;
BEGIN
  v_result := public.driver_accept_offer(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'driver_accept failed: %', v_result;
  END IF;
  v_result := public.driver_accept_offer(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'ok' <> 'true' OR v_result->>'idempotent' <> 'true' THEN
    RAISE EXCEPTION 'driver_accept idempotency failed: %', v_result;
  END IF;
  v_result := public.driver_advance_order(
    '11111111-2222-4333-8444-555555555555', 'pickedUp'
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'pickedUp failed: %', v_result;
  END IF;
  v_result := public.driver_advance_order(
    '11111111-2222-4333-8444-555555555555', 'onTheWay'
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'onTheWay failed: %', v_result;
  END IF;
  v_result := public.driver_finish_cash_order(
    '11111111-2222-4333-8444-555555555555'
  );
  IF v_result->>'error' <> 'pin_required' THEN
    RAISE EXCEPTION 'non-cash delivery bypassed PIN: %', v_result;
  END IF;
  v_result := public.driver_validate_delivery_pin(
    '11111111-2222-4333-8444-555555555555', '5369'
  );
  IF v_result->>'ok' <> 'true' THEN
    RAISE EXCEPTION 'PIN delivery failed: %', v_result;
  END IF;
END;
$$;

RESET ROLE;
DO $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_events integer;
BEGIN
  SELECT * INTO v_order FROM public.orders
   WHERE id = '11111111-2222-4333-8444-555555555555';
  IF v_order.status <> 'delivered'
     OR v_order.driver_id IS NULL
     OR v_order.assigned_driver_id IS NULL THEN
    RAISE EXCEPTION 'invalid final state: status %, driver %, assigned %',
      v_order.status, v_order.driver_id, v_order.assigned_driver_id;
  END IF;
  SELECT count(*) INTO v_events
  FROM public.order_status_events
  WHERE order_id = v_order.id;
  IF v_events <> 6 THEN
    RAISE EXCEPTION 'expected 6 status events, got %', v_events;
  END IF;
END;
$$;

ROLLBACK;
