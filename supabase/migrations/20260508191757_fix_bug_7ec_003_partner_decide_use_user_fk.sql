-- Fix BUG-7E-C-003 (LOW): partner_decide_reservation
-- usar restaurants.user_ FK
-- Data: 2026-05-08 / Sessao 7-alpha-7E-C-TESTS
-- Aplicada via MCP em prod antes do ficheiro local.

CREATE OR REPLACE FUNCTION public.partner_decide_reservation(
  p_reservation_id uuid,
  p_accept boolean,
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
  v_partner_owns boolean;
  v_new_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.status != 'pending' THEN
    RAISE EXCEPTION 'reservation_not_pending: %', v_rsv.status;
  END IF;

  -- FIX BUG-7E-C-003: usar restaurants.user_ FK (era email JOIN fragil)
  SELECT EXISTS (
    SELECT 1 FROM restaurants r
    WHERE r.id = v_rsv.restaurant_id
      AND r.user_ = v_uid
  ) INTO v_partner_owns;
  IF NOT v_partner_owns THEN RAISE EXCEPTION 'not_your_restaurant'; END IF;

  v_new_status := CASE WHEN p_accept THEN 'approved' ELSE 'rejected_refunded' END;

  UPDATE reservations
  SET status = v_new_status, decided_at = NOW(),
      cancel_reason = CASE WHEN p_accept THEN cancel_reason ELSE p_reason END
  WHERE id = p_reservation_id;

  PERFORM _push_in_app_notification(
    v_rsv.client_user_id, 'reservation',
    CASE WHEN p_accept THEN 'Reserva aprovada' ELSE 'Reserva rejeitada -- reembolso' END,
    CASE WHEN p_accept THEN 'Vemo-nos a ' || to_char(v_rsv.reserved_for, 'DD/MM HH24:MI') || '.'
         ELSE 'O parceiro nao pode aceitar. Reembolso em curso.' END,
    p_reservation_id::text
  );

  RETURN jsonb_build_object(
    'success', true, 'status', v_new_status,
    'will_refund', NOT p_accept,
    'prepayment_pi', v_rsv.prepayment_pi
  );
END;
$function$;
