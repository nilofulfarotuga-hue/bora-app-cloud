-- ============================================================================
-- BORA — FASE 4: drivers.mbway_phone + RPCs para tela Ganhos
-- ============================================================================

BEGIN;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS mbway_phone TEXT;

COMMENT ON COLUMN public.drivers.mbway_phone IS
  'Número MBWay E.164 (ex: +351912345678) para receber settlements semanais.';

CREATE OR REPLACE FUNCTION public.get_driver_current_week_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_summary JSONB;
  v_orders JSONB;
  v_history JSONB;
  v_mbway TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  v_summary := public.compute_driver_settlement(v_uid, now(), false);

  SELECT jsonb_agg(row_to_json(t.*))
    INTO v_orders
    FROM public.list_driver_orders_in_week(v_uid, now()) t;

  SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'week_start_at', s.week_start_at,
            'week_end_at', s.week_end_at,
            'total_deliveries', s.total_deliveries,
            'net_balance', s.net_balance,
            'direction', s.direction,
            'status', s.status,
            'paid_at', s.paid_at,
            'payment_reference', s.payment_reference
          ) ORDER BY s.week_start_at DESC)
    INTO v_history
    FROM public.driver_weekly_settlements s
   WHERE s.driver_id = v_uid
     AND s.week_start_at < (v_summary->>'week_start')::timestamptz
   LIMIT 12;

  SELECT mbway_phone INTO v_mbway FROM public.drivers WHERE id = v_uid;

  RETURN jsonb_build_object(
    'summary',     v_summary,
    'orders',      COALESCE(v_orders, '[]'::jsonb),
    'history',     COALESCE(v_history, '[]'::jsonb),
    'mbway_phone', v_mbway
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_driver_current_week_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_driver_current_week_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.update_driver_mbway_phone(p_phone TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_clean TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  v_clean := NULLIF(TRIM(p_phone), '');
  IF v_clean IS NOT NULL
     AND v_clean !~ '^\+?[0-9 ]{6,20}$'
  THEN
    RAISE EXCEPTION 'invalid_phone_format' USING ERRCODE = '23514';
  END IF;

  UPDATE public.drivers SET mbway_phone = v_clean WHERE id = v_uid;
  RETURN jsonb_build_object('success', true, 'mbway_phone', v_clean);
END;
$function$;

REVOKE ALL ON FUNCTION public.update_driver_mbway_phone(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_driver_mbway_phone(TEXT) TO authenticated;

COMMIT;
