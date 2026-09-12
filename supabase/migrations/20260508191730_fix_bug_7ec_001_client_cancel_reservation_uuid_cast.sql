-- Fix BUG-7E-C-001 (HIGH): client_cancel_reservation
-- log_admin_action UUID overload
-- Data: 2026-05-08 / Sessao 7-alpha-7E-C-TESTS
-- Aplicada via MCP em prod antes do ficheiro local.

CREATE OR REPLACE FUNCTION public.client_cancel_reservation(
  p_reservation_id uuid,
  p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rsv record;
  v_uid uuid := auth.uid();
  v_window_h int;
  v_diff_h numeric;
  v_will_refund boolean;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'cannot_cancel_status: %', v_rsv.status;
  END IF;

  SELECT (value::text)::int INTO v_window_h FROM platform_settings
  WHERE key = 'reservation_cancel_window_hours';
  v_window_h := COALESCE(v_window_h, 2);

  v_diff_h := EXTRACT(EPOCH FROM (v_rsv.reserved_for - NOW())) / 3600.0;
  v_will_refund := v_diff_h >= v_window_h;
  v_new_status := CASE WHEN v_will_refund THEN 'cancelled_refunded' ELSE 'cancelled_no_refund' END;

  UPDATE reservations
  SET status = v_new_status, cancelled_at = NOW(), cancel_reason = p_reason
  WHERE id = p_reservation_id;

  PERFORM _push_in_app_notification(
    v_uid, 'cancellation',
    CASE WHEN v_will_refund THEN 'Reserva cancelada -- reembolso em curso'
         ELSE 'Reserva cancelada -- pre-pagamento nao devolvido' END,
    CASE WHEN v_will_refund THEN 'Reembolso de EUR ' ||
           ROUND(v_rsv.prepayment_cents / 100.0, 2)::text || ' em 5-10 dias uteis.'
         ELSE 'Cancelaste dentro de ' || v_window_h::text ||
              'h -- pre-pagamento de EUR ' || ROUND(v_rsv.prepayment_cents / 100.0, 2)::text ||
              ' nao e devolvido.' END,
    p_reservation_id::text
  );

  -- FIX BUG-7E-C-001: removido ::text do p_reservation_id
  PERFORM log_admin_action(
    'client_cancel_reservation', 'reservation', p_reservation_id,
    jsonb_build_object('hours_until', v_diff_h, 'window_h', v_window_h,
                       'refund', v_will_refund, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true, 'status', v_new_status,
    'will_refund', v_will_refund,
    'hours_until_reservation', v_diff_h,
    'prepayment_pi', v_rsv.prepayment_pi
  );
END;
$function$;
