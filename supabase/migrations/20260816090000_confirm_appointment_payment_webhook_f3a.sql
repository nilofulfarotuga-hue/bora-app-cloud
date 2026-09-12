-- F3a (MISSAO TOTAL 2026-08-15): o stripe-webhook passa a ser a GARANTIA do
-- pagamento das marcacoes; o poll do cliente vira acelerador.
-- Molde: confirm_reservation_payment_webhook (idempotente, FOR UPDATE,
-- valida PI contra deposit_pi) + efeitos de client_confirm_appointment_payment
-- (confirmed + deposit_status='paid' + notificacoes parceiro/cliente).
-- Os helpers _appt_notify_* ja engolem falhas internamente (nunca quebram a
-- transacao principal).
-- APLICADA em producao a 2026-08-16 via MCP apply_migration
-- (confirm_appointment_payment_webhook_f3a_2026_08_16).

CREATE OR REPLACE FUNCTION public.confirm_appointment_payment_webhook(
  p_appointment_id uuid,
  p_payment_intent_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_appt record;
  v_when text;
BEGIN
  SELECT * INTO v_appt FROM public.appointments
  WHERE id = p_appointment_id
  FOR UPDATE;

  IF v_appt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'appointment_not_found');
  END IF;

  -- Idempotencia: race com o poll (client_confirm_appointment_payment)
  IF v_appt.status <> 'pending_payment' THEN
    RETURN jsonb_build_object('ok', true, 'already_confirmed', true,
                              'status', v_appt.status);
  END IF;

  -- Defesa contra spoofing de metadata: o PI do evento tem de ser o da marcacao
  IF v_appt.deposit_pi IS DISTINCT FROM p_payment_intent_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pi_mismatch');
  END IF;

  UPDATE public.appointments
  SET status = 'confirmed', deposit_status = 'paid', confirmed_at = now()
  WHERE id = p_appointment_id;

  v_when := to_char(v_appt.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI');
  PERFORM public._appt_notify_partner(v_appt.provider_id, 'appointment_new', 'Nova marcacao',
          'Nova marcacao confirmada para '||v_when, p_appointment_id::text);
  PERFORM public._appt_notify_client(v_appt.client_user_id, 'appointment_confirmed', 'Marcacao confirmada',
          'A tua marcacao para '||v_when||' esta confirmada.', p_appointment_id::text);

  RETURN jsonb_build_object('ok', true, 'appointment_id', p_appointment_id);
END;
$function$;

-- Grants fechados: so o webhook (service_role) chama isto.
REVOKE ALL ON FUNCTION public.confirm_appointment_payment_webhook(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_appointment_payment_webhook(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.confirm_appointment_payment_webhook(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_appointment_payment_webhook(uuid, text) TO service_role;
