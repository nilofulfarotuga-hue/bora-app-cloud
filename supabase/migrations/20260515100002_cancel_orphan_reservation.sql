-- 2026-05-15 — BUG 1+2 Opção A-modificada
-- RPC chamada pelo stripe-webhook v24 quando metadata.purpose='reservation_prepayment'
-- e o PaymentIntent falha ou é cancelado pelo utilizador. Apaga a reserva órfã.
-- Idempotente, com lock e validação de PI. Só apaga se status='pending_payment'.

CREATE OR REPLACE FUNCTION public.cancel_orphan_reservation(
  p_reservation_id uuid,
  p_payment_intent_id text,
  p_reason text DEFAULT 'payment_failed'
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
    -- Já apagada (idempotência — chamadas duplicadas ou cleanup manual)
    RETURN jsonb_build_object('ok', true, 'already_gone', true);
  END IF;

  -- Só apagar se ainda está pending_payment (não tocar em pending/approved)
  IF v_reservation.status <> 'pending_payment' THEN
    RETURN jsonb_build_object('ok', true, 'not_orphan', true,
                              'status', v_reservation.status);
  END IF;

  -- Validar PI (defesa contra spoofing)
  IF v_reservation.prepayment_pi IS DISTINCT FROM p_payment_intent_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pi_mismatch');
  END IF;

  DELETE FROM public.reservations WHERE id = p_reservation_id;

  RETURN jsonb_build_object('ok', true, 'deleted', true, 'reason', p_reason);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_orphan_reservation(uuid, text, text)
  TO service_role;
