-- FESTAS (2026-08-25) - RPCs verdes do lancamento (APLICADA via MCP 2026-08-25).
-- festas_accept: aceite com tempo (espelho partner_takeaway_accept; dual-owner; 5..480 min).
-- festas_set_schedule: o proprio cliente grava a data (minimo dia seguinte, Europe/Lisbon),
--   so enquanto 'created', so uma vez, so em loja categoria 'festas'.

CREATE OR REPLACE FUNCTION public.festas_accept(p_order_id text, p_prep_minutes integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_order  record;
  v_owns   boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_prep_minutes IS NULL OR p_prep_minutes < 5 OR p_prep_minutes > 480 THEN
    RAISE EXCEPTION 'invalid_prep_minutes';
  END IF;
  SELECT id, status, service_type, restaurant_id
    INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.status NOT IN ('created') THEN
    RAISE EXCEPTION 'order_already_processed: %', v_order.status;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = v_order.restaurant_id
      AND (r.user_ = v_uid OR r.user_id = v_uid)
      AND r.category = 'festas'
  ) INTO v_owns;
  IF NOT v_owns THEN RAISE EXCEPTION 'not_your_order'; END IF;

  UPDATE public.orders SET
    status            = 'preparing',
    prep_time_minutes = p_prep_minutes,
    takeaway_prep_minutes = CASE WHEN service_type = 'takeaway'
                                 THEN p_prep_minutes ELSE takeaway_prep_minutes END
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'prep_minutes', p_prep_minutes,
    'estimated_ready_at', NOW() + (p_prep_minutes || ' minutes')::interval
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.festas_accept(text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.festas_set_schedule(p_order_id text, p_scheduled_for timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_order record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_scheduled_for IS NULL THEN RAISE EXCEPTION 'schedule_required'; END IF;
  -- Antecedencia minima de 1 dia = a partir do dia seguinte (hora de Lisboa).
  IF (p_scheduled_for AT TIME ZONE 'Europe/Lisbon')::date
     < (now() AT TIME ZONE 'Europe/Lisbon')::date + 1 THEN
    RAISE EXCEPTION 'schedule_too_soon';
  END IF;
  SELECT id, status, user_id, restaurant_id, scheduled_for
    INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.user_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'not_your_order'; END IF;
  IF v_order.status <> 'created' THEN
    RAISE EXCEPTION 'order_already_processed: %', v_order.status;
  END IF;
  IF v_order.scheduled_for IS NOT NULL THEN RAISE EXCEPTION 'schedule_already_set'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = v_order.restaurant_id AND r.category = 'festas'
  ) THEN
    RAISE EXCEPTION 'not_festas_store';
  END IF;

  UPDATE public.orders SET scheduled_for = p_scheduled_for WHERE id = p_order_id;

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                            'scheduled_for', p_scheduled_for);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.festas_set_schedule(text, timestamptz) TO authenticated;
