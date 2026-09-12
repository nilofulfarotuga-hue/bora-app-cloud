-- F3b (MISSAO TOTAL 2026-08-15): o stripe-webhook passa a GARANTIR o 'held'
-- da limpeza; o mark_held do cliente (cleaning-checkout) vira acelerador.
-- APLICADA em producao a 2026-08-16 via MCP apply_migration
-- (confirm_cleaning_payment_webhook_f3b_2026_08_16).

CREATE OR REPLACE FUNCTION public.confirm_cleaning_payment_webhook(
  p_booking_id uuid,
  p_payment_intent_id text,
  p_amount_cents integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_booking record;
BEGIN
  SELECT * INTO v_booking FROM public.cleaning_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;

  IF v_booking.payment_status <> 'unpaid' THEN
    RETURN jsonb_build_object('ok', true, 'already_marked', true,
                              'payment_status', v_booking.payment_status);
  END IF;

  IF COALESCE(v_booking.total_cents, 0) <> COALESCE(p_amount_cents, -1) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_mismatch',
                              'expected', v_booking.total_cents,
                              'received', p_amount_cents);
  END IF;

  UPDATE public.cleaning_bookings
  SET payment_status = 'held', stripe_payment_intent_id = p_payment_intent_id
  WHERE id = p_booking_id AND payment_status = 'unpaid';

  RETURN jsonb_build_object('ok', true, 'booking_id', p_booking_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.confirm_cleaning_payment_webhook(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_cleaning_payment_webhook(uuid, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.confirm_cleaning_payment_webhook(uuid, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_cleaning_payment_webhook(uuid, text, integer) TO service_role;
