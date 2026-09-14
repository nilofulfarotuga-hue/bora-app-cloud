-- 2026-09-14 — correcao: log_admin_action(text,text,TEXT,jsonb) escreve em
-- admin_logs (tabela que nao existe) e engole o erro; a sobrecarga com
-- entity_id UUID e a que escreve em admin_audit_log, o Historico de Acoes do
-- painel. Passa-se o uuid sem cast para cair na sobrecarga certa.
-- Prova em rollback antes desta correcao: audit=0. Depois: audit=1.

CREATE OR REPLACE FUNCTION public.admin_appointment_confirm_done(p_appointment_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record; v_a record;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_a FROM public.appointments WHERE id = p_appointment_id;
  IF v_a IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_a.status NOT IN ('confirmed', 'awaiting_confirmation') THEN RAISE EXCEPTION 'invalid_status: %', v_a.status; END IF;
  UPDATE public.appointments
     SET status = 'completed', completed_at = COALESCE(completed_at, scheduled_at + make_interval(mins => COALESCE(duration_minutes, 30))),
         updated_at = now(),
         full_payment_method = COALESCE(full_payment_method, 'app'),
         full_payment_status = CASE WHEN deposit_status = 'paid' THEN 'paid' ELSE full_payment_status END,
         partner_notes = COALESCE(partner_notes || E'\n', '') || 'Confirmada como feita pelo admin a ' ||
                         to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI') || COALESCE(': ' || p_note, '')
   WHERE id = p_appointment_id;
  PERFORM public.log_admin_action('appointment_confirmed_done_by_admin', 'appointment', p_appointment_id,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note));
  RETURN jsonb_build_object('success', true, 'status', 'completed', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

CREATE OR REPLACE FUNCTION public.admin_appointment_mark_no_show(p_appointment_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record; v_a record;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_a FROM public.appointments WHERE id = p_appointment_id;
  IF v_a IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_a.status NOT IN ('confirmed', 'awaiting_confirmation') THEN RAISE EXCEPTION 'invalid_status: %', v_a.status; END IF;
  UPDATE public.appointments
     SET status = 'no_show', no_show_at = now(), updated_at = now(),
         no_show_decided_by = 'admin', no_show_decided_at = now(),
         deposit_status = CASE WHEN deposit_status = 'paid' THEN 'retained' ELSE deposit_status END,
         partner_notes = COALESCE(partner_notes || E'\n', '') || 'Falta decidida pelo admin a ' ||
                         to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI') || COALESCE(': ' || p_note, '')
   WHERE id = p_appointment_id;
  PERFORM public.log_admin_action('appointment_no_show_by_admin', 'appointment', p_appointment_id,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note));
  PERFORM public._telegram_admin('Bora · marcações: marcaste FALTA a ' || COALESCE(v_a.client_name, 'cliente') ||
    ' (' || to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '). ' ||
    (COALESCE(v_a.deposit_cents, 0) / 100.0)::numeric(10,2) || ' € ficam retidos até o fecho da semana.');
  RETURN jsonb_build_object('success', true, 'status', 'no_show', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

CREATE OR REPLACE FUNCTION public.admin_appointment_revert_no_show(p_appointment_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record; v_a record; v_prov text;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_a FROM public.appointments WHERE id = p_appointment_id;
  IF v_a IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  IF v_a.status <> 'no_show' THEN RAISE EXCEPTION 'invalid_status: %', v_a.status; END IF;
  UPDATE public.appointments
     SET status = 'completed', no_show_at = NULL, updated_at = now(),
         completed_at = COALESCE(completed_at, scheduled_at + make_interval(mins => COALESCE(duration_minutes, 30))),
         deposit_status = CASE WHEN deposit_status = 'retained' THEN 'paid' ELSE deposit_status END,
         full_payment_method = COALESCE(full_payment_method, 'app'),
         full_payment_status = CASE WHEN deposit_status IN ('retained', 'paid') THEN 'paid' ELSE full_payment_status END,
         partner_notes = COALESCE(partner_notes || E'\n', '') || 'Falta revertida pelo admin a ' ||
                         to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI') || COALESCE(': ' || p_note, '')
   WHERE id = p_appointment_id;
  PERFORM public.log_admin_action('appointment_no_show_reverted_by_admin', 'appointment', p_appointment_id,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note,
                       'decidida_por', v_a.no_show_decided_by));
  SELECT name INTO v_prov FROM public.service_providers WHERE id = v_a.provider_id;
  PERFORM public._appt_notify_partner(v_a.provider_id, 'appointment_no_show_reverted',
    'Marcação de ' || to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || ' dada como feita',
    'A falta foi revertida pela Bora. O valor entra no teu acerto da semana.', p_appointment_id::text);
  RETURN jsonb_build_object('success', true, 'status', 'completed', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

CREATE OR REPLACE FUNCTION public.admin_appointment_ask_partner_again(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  PERFORM public._appt_ask_partner_confirmation(p_appointment_id);
  PERFORM public.log_admin_action('appointment_partner_asked_again', 'appointment', p_appointment_id, '{}'::jsonb);
  RETURN jsonb_build_object('success', true);
END $$;
