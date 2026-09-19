-- 2026-05-15 — BUG 1+2 Opção A-modificada
-- RPC chamada pelo stripe-webhook v24 quando metadata.purpose='reservation_prepayment'
-- e o PaymentIntent transita para succeeded. Idempotente, com lock e validação de PI.
-- NÃO notifica parceiro — client_confirm_reservation_payment (fallback Flutter) trata
-- a notificação. Webhook é apenas defesa para garantir status change se Flutter falhar.

CREATE OR REPLACE FUNCTION public.confirm_reservation_payment_webhook(
  p_reservation_id uuid,
  p_payment_intent_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_reservation record;
BEGIN
  SELECT id, status, prepayment_pi INTO v_reservation
  FROM public.reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF v_reservation IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  END IF;

  -- Idempotência: já confirmada (race com client_confirm_reservation_payment)
  IF v_reservation.status <> 'pending_payment' THEN
    RETURN jsonb_build_object('ok', true, 'already_confirmed', true,
                              'status', v_reservation.status);
  END IF;

  -- Validar PI (defesa contra spoofing de metadata)
  IF v_reservation.prepayment_pi IS DISTINCT FROM p_payment_intent_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pi_mismatch');
  END IF;

  UPDATE public.reservations
  SET status = 'pending'
  WHERE id = p_reservation_id;

  RETURN jsonb_build_object('ok', true, 'reservation_id', p_reservation_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_reservation_payment_webhook(uuid, text)
  TO service_role;
