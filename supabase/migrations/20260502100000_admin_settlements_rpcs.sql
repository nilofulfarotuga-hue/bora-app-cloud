-- ============================================================================
-- BORA — FASE 5: RPCs admin para gestão de settlements semanais
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._is_admin(p_uid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF p_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM auth.users
     WHERE id = p_uid
       AND raw_app_meta_data->>'role' = 'admin'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_settlements_for_week(
  p_week_start TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_bounds RECORD;
  v_drivers JSONB;
  v_drv RECORD;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  FOR v_drv IN
    SELECT DISTINCT assigned_driver_id::uuid AS id
      FROM public.orders
     WHERE status = 'delivered'
       AND delivered_at >= v_bounds.week_start
       AND delivered_at <= v_bounds.week_end
       AND assigned_driver_id ~ '^[0-9a-f]{8}-'
  LOOP
    INSERT INTO public.driver_weekly_settlements (
      driver_id, week_start_at, week_end_at, direction, status
    ) VALUES (
      v_drv.id, v_bounds.week_start, v_bounds.week_end, 'zero', 'pending'
    )
    ON CONFLICT (driver_id, week_start_at) DO NOTHING;

    PERFORM public.compute_driver_settlement(v_drv.id, v_bounds.week_start, true);
  END LOOP;

  SELECT jsonb_agg(jsonb_build_object(
    'settlement_id',         s.id,
    'driver_id',             s.driver_id,
    'driver_name',           d.name,
    'mbway_phone',           d.mbway_phone,
    'total_deliveries',      s.total_deliveries,
    'total_earnings',        s.total_earnings,
    'total_cash_received',   s.total_cash_received,
    'cash_adjustments_due',  s.cash_adjustments_due,
    'net_balance',           s.net_balance,
    'direction',             s.direction,
    'status',                s.status,
    'paid_at',               s.paid_at,
    'payment_reference',     s.payment_reference,
    'notes',                 s.notes
  ) ORDER BY ABS(s.net_balance) DESC)
  INTO v_drivers
  FROM public.driver_weekly_settlements s
  JOIN public.drivers d ON d.id = s.driver_id
  WHERE s.week_start_at = v_bounds.week_start;

  RETURN jsonb_build_object(
    'week_start', v_bounds.week_start,
    'week_end',   v_bounds.week_end,
    'settlements', COALESCE(v_drivers, '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_settlements_for_week(TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_settlements_for_week(TIMESTAMPTZ) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_settlement_status(
  p_settlement_id UUID,
  p_new_status TEXT,
  p_payment_reference TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_admin_uid UUID := auth.uid();
  v_settlement RECORD;
BEGIN
  IF NOT public._is_admin(v_admin_uid) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  IF p_new_status NOT IN ('paid', 'received', 'disputed', 'pending') THEN
    RAISE EXCEPTION 'invalid_status: %', p_new_status USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_settlement FROM public.driver_weekly_settlements
   WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.driver_weekly_settlements SET
    status            = p_new_status,
    payment_reference = COALESCE(p_payment_reference, payment_reference),
    notes             = COALESCE(p_notes, notes),
    paid_at           = CASE WHEN p_new_status IN ('paid','received')
                             THEN now() ELSE paid_at END,
    paid_by           = CASE WHEN p_new_status IN ('paid','received')
                             THEN v_admin_uid ELSE paid_by END
  WHERE id = p_settlement_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id, details
    ) VALUES (
      v_admin_uid,
      (SELECT email FROM auth.users WHERE id = v_admin_uid),
      'settlement_set_status',
      'settlement',
      p_settlement_id,
      jsonb_build_object(
        'previous_status', v_settlement.status,
        'new_status', p_new_status,
        'payment_reference', p_payment_reference,
        'notes', p_notes,
        'driver_id', v_settlement.driver_id,
        'net_balance', v_settlement.net_balance
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_set_settlement_status: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'settlement_id', p_settlement_id,
    'status', p_new_status
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_settlement_status(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_settlement_status(UUID, TEXT, TEXT, TEXT) TO authenticated;

COMMIT;
