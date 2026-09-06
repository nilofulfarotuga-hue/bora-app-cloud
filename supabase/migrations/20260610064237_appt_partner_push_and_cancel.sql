-- M8 — Parceiro-serviços: push FCM de nova marcação + cancelamento pelo parceiro.
-- Par no Edge: notify-service-provider v1 (FCM multi-device via partner_push_tokens
-- keyed pelo user do owner do service_provider; auth por service-role bearer match).

-- 1) _appt_notify_partner v2: in-app (inalterado) + FCM best-effort via Edge
--    notify-service-provider (tokens em partner_push_tokens por user do owner).
CREATE OR REPLACE FUNCTION public._appt_notify_partner(
  p_provider_id text, p_kind text, p_title text, p_body text, p_appointment_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_owner        uuid;
  v_supabase_url text;
  v_service_key  text;
BEGIN
  SELECT user_id INTO v_owner FROM public.service_providers WHERE id = p_provider_id;
  IF v_owner IS NULL THEN RETURN; END IF;

  BEGIN
    PERFORM public._push_in_app_notification(v_owner, p_kind, p_title, p_body, p_appointment_id);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- FCM push (M8) — nunca quebra a transação principal.
  BEGIN
    SELECT decrypted_secret INTO v_supabase_url
      FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_service_key
      FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
    IF v_supabase_url IS NOT NULL AND v_service_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_supabase_url || '/functions/v1/notify-service-provider',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key),
        body := jsonb_build_object(
          'providerId',    p_provider_id,
          'title',         p_title,
          'body',          p_body,
          'kind',          p_kind,
          'appointmentId', p_appointment_id));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[_appt_notify_partner] fcm push failed: %', SQLERRM;
  END;
END $function$;

-- 2) Cancelamento de marcação pelo PARCEIRO (gap M8 — só existia complete/no_show).
--    Sinal pago → cliente é avisado do reembolso + alerta admin para processar
--    o refund (padrão atual: refunds Stripe são executados pelo admin).
CREATE OR REPLACE FUNCTION public.partner_cancel_appointment(
  p_appointment_id uuid, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_appt record;
  v_when text;
  v_refund_due boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT a.*, sp.user_id AS owner_user_id, sp.name AS provider_name
    INTO v_appt
    FROM appointments a
    JOIN service_providers sp ON sp.id = a.provider_id
   WHERE a.id = p_appointment_id;

  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_appt.owner_user_id <> v_uid THEN RAISE EXCEPTION 'not_your_provider'; END IF;
  IF v_appt.status NOT IN ('pending_payment', 'confirmed') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;

  v_refund_due := (v_appt.deposit_status = 'paid');

  UPDATE appointments
     SET status        = 'cancelled',
         cancelled_at  = now(),
         cancelled_by  = 'partner',
         cancel_reason = COALESCE(NULLIF(trim(p_reason), ''), 'cancelado_pelo_parceiro')
   WHERE id = p_appointment_id;

  v_when := to_char(v_appt.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI');

  -- Cliente (in-app + FCM best-effort via helper das marcações)
  IF v_appt.client_user_id IS NOT NULL THEN
    BEGIN
      PERFORM public._appt_notify_client(
        v_appt.client_user_id, 'appointment_cancelled',
        'Marcação cancelada',
        'A tua marcação de ' || v_when || ' foi cancelada por ' ||
        COALESCE(v_appt.provider_name, 'a barbearia') ||
        CASE WHEN v_refund_due THEN '. O sinal será reembolsado.' ELSE '.' END,
        p_appointment_id::text);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Sinal pago → alerta admin para processar o reembolso
  IF v_refund_due THEN
    BEGIN
      PERFORM public.notify_admin_event(
        'appointment_partner_cancel_refund_due', 'high',
        format('Parceiro cancelou marcação #%s — sinal de €%s a reembolsar',
               substring(p_appointment_id::text, 1, 8),
               to_char(COALESCE(v_appt.deposit_cents, 300) / 100.0, 'FM990.00')),
        'appointment', p_appointment_id::text,
        jsonb_build_object(
          'provider_id', v_appt.provider_id,
          'deposit_pi', v_appt.deposit_pi,
          'deposit_cents', v_appt.deposit_cents,
          'reason', p_reason),
        NULL);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object('success', true, 'refund_due', v_refund_due);
END $function$;

-- Grants pós-hardening (novas funções nascem com EXECUTE para PUBLIC — fechar):
REVOKE EXECUTE ON FUNCTION public.partner_cancel_appointment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_cancel_appointment(uuid, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._appt_notify_partner(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._appt_notify_partner(text, text, text, text, text) TO service_role;
