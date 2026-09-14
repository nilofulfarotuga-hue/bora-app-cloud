-- ============================================================================
-- 2026-09-14 (missao painel-admin-limpo) — A FALTA NAS MARCACOES DEIXA DE SER
-- AUTOMATICA. Ninguem fica com o dinheiro sozinho.
--
-- Cicatriz (07/09): a marcacao d6772a72 (Barbearia Ouro e Prata, Cristiano
-- Aquino, 12 EUR pagos por cartao) foi marcada como falta pelo robo
-- (_appointment_cron_auto_no_show, job 42, a cada 15 min) so porque o barbeiro
-- se esqueceu do botao. O deposito — que e o PRECO INTEIRO do servico, nao um
-- sinal — passou a "retido" e o barbeiro ficou sem os 11,50 EUR. A Claude.ai
-- corrigiu a mao a 14/09 as 00:15.
--
-- Desenho novo:
--   1. Ao fim do servico (hora + duracao + X min), a marcacao passa a
--      'awaiting_confirmation' ("por confirmar") e o parceiro recebe aviso com
--      dois botoes: "Feito" / "Faltou". O Danilo ve na caixa do painel.
--   2. Sem resposta, fica "por confirmar". NUNCA passa a falta sozinha e o
--      dinheiro NUNCA e retido pelo robo. O aviso repete-se ate 3 vezes (24 h).
--   3. A falta so fica definitiva com resposta do parceiro
--      (partner_mark_no_show) ou decisao do Danilo no painel
--      (admin_appointment_mark_no_show) — e em ambos os casos sai um Telegram
--      para o Danilo no momento, antes de o fecho semanal mover dinheiro.
--   4. Painel: listas "por confirmar" e "retido por falta", com reverter a
--      1 toque (admin_appointment_revert_no_show / admin_appointment_confirm_done).
--
-- O recalculo do payout do parceiro depois de reverter e feito pelo painel
-- (chama o RPC de calculo semanal ja existente); esta migration nao o nomeia.
-- ============================================================================

-- 0) Colunas de apoio ---------------------------------------------------------
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS awaiting_since timestamptz,
  ADD COLUMN IF NOT EXISTS confirm_asked_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS confirm_last_asked_at timestamptz,
  ADD COLUMN IF NOT EXISTS no_show_decided_by text,
  ADD COLUMN IF NOT EXISTS no_show_decided_at timestamptz;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('appointment_confirm_ask_minutes_after_end', '15'::jsonb,
   'Marcacoes: quantos minutos depois do fim previsto do servico se pergunta ao parceiro "feito ou faltou?". A falta nunca e automatica.',
   'appointments'),
  ('appointment_confirm_reask_hours', '24'::jsonb,
   'Marcacoes: de quantas em quantas horas se repete a pergunta ao parceiro (maximo 3 vezes).',
   'appointments')
ON CONFLICT (key) DO NOTHING;

UPDATE public.platform_settings
   SET description = 'LEGADO desde 14/09/2026: ja nao ha falta automatica. Mantido so por compatibilidade; o cron usa appointment_confirm_ask_minutes_after_end.'
 WHERE key = 'appointment_no_show_grace_minutes';

-- 1) Telegram para o Danilo, directo do servidor (best-effort) --------------
CREATE OR REPLACE FUNCTION public._telegram_admin(p_text text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_token text; v_chat text;
BEGIN
  SELECT bot_token, chat_id INTO v_token, v_chat FROM public.get_telegram_config();
  IF v_token IS NULL OR v_chat IS NULL THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (NULL, 'telegram_admin', '_telegram_admin', 'vault telegram_bot_token/telegram_admin_chat_id em falta');
    RETURN;
  END IF;
  PERFORM net.http_post(
    url := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('chat_id', v_chat, 'text', p_text, 'disable_web_page_preview', true));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public.notification_failures (user_id, kind, source, erro)
  VALUES (NULL, 'telegram_admin', '_telegram_admin', SQLERRM);
END;
$$;
REVOKE ALL ON FUNCTION public._telegram_admin(text) FROM PUBLIC, anon, authenticated;

-- 2) Pergunta ao parceiro (push + in-app), reutilizavel pelo cron e pelo painel
CREATE OR REPLACE FUNCTION public._appt_ask_partner_confirmation(p_appointment_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_a record; v_quando text;
BEGIN
  SELECT * INTO v_a FROM public.appointments WHERE id = p_appointment_id;
  IF v_a IS NULL THEN RETURN; END IF;
  v_quando := to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI');
  PERFORM public._appt_notify_partner(
    v_a.provider_id, 'appointment_confirm_needed',
    'A marcação de ' || v_quando || ' foi feita?',
    COALESCE(NULLIF(v_a.client_name, ''), 'O cliente') || ' — ' ||
      (COALESCE(v_a.service_price_cents, 0) / 100.0)::numeric(10,2) || ' €. Toca para responder: Feito ou Faltou.',
    p_appointment_id::text);
  UPDATE public.appointments
     SET confirm_asked_count = COALESCE(confirm_asked_count, 0) + 1,
         confirm_last_asked_at = now()
   WHERE id = p_appointment_id;
END;
$$;
REVOKE ALL ON FUNCTION public._appt_ask_partner_confirmation(uuid) FROM PUBLIC, anon, authenticated;

-- 3) O cron 42 passa a perguntar em vez de punir ------------------------------
CREATE OR REPLACE FUNCTION public._appointment_cron_auto_no_show()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ask_min int; v_reask_h int;
  v_novas int := 0; v_repetidas int := 0;
  v_a record;
BEGIN
  SELECT COALESCE((value::text)::int, 15) INTO v_ask_min FROM public.platform_settings WHERE key = 'appointment_confirm_ask_minutes_after_end';
  SELECT COALESCE((value::text)::int, 24) INTO v_reask_h FROM public.platform_settings WHERE key = 'appointment_confirm_reask_hours';
  v_ask_min := COALESCE(v_ask_min, 15); v_reask_h := COALESCE(v_reask_h, 24);

  -- 3a) Confirmadas cujo servico ja acabou: passam a "por confirmar" e pergunta-se.
  FOR v_a IN
    SELECT id, provider_id, client_name, scheduled_at, service_price_cents
      FROM public.appointments
     WHERE status = 'confirmed'
       AND scheduled_at + make_interval(mins => COALESCE(duration_minutes, 30) + v_ask_min) < now()
     ORDER BY scheduled_at
     LIMIT 50
  LOOP
    UPDATE public.appointments
       SET status = 'awaiting_confirmation', awaiting_since = now(), updated_at = now()
     WHERE id = v_a.id AND status = 'confirmed';
    PERFORM public._appt_ask_partner_confirmation(v_a.id);
    PERFORM public.notify_admin_event(
      'appointment_awaiting_confirmation', 'medium',
      'Marcação por confirmar: ' || COALESCE(v_a.client_name, 'cliente') || ' às ' ||
        to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
        ' (' || (COALESCE(v_a.service_price_cents, 0) / 100.0)::numeric(10,2) || ' €). O parceiro ainda não disse se foi feita.',
      'appointment', v_a.id::text,
      jsonb_build_object('provider_id', v_a.provider_id, 'scheduled_at', v_a.scheduled_at),
      '/admin/marcacoes-por-confirmar');
    v_novas := v_novas + 1;
  END LOOP;

  -- 3b) Ja "por confirmar" ha mais de X horas e sem resposta: repete a pergunta (max 3).
  FOR v_a IN
    SELECT id FROM public.appointments
     WHERE status = 'awaiting_confirmation'
       AND COALESCE(confirm_asked_count, 0) < 3
       AND COALESCE(confirm_last_asked_at, awaiting_since, now()) < now() - make_interval(hours => v_reask_h)
     LIMIT 50
  LOOP
    PERFORM public._appt_ask_partner_confirmation(v_a.id);
    v_repetidas := v_repetidas + 1;
  END LOOP;

  RETURN jsonb_build_object('por_confirmar_novas', v_novas, 'perguntas_repetidas', v_repetidas,
                            'marked_no_show', 0, 'ran_at', now());
END;
$$;

-- 4) Resposta do parceiro: "Feito" (a partir de confirmada OU por confirmar)
CREATE OR REPLACE FUNCTION public.partner_complete_appointment(p_appointment_id uuid, p_payment_method text DEFAULT 'on_site'::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_appt record;
BEGIN
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_appt.provider_id);
  IF v_appt.status NOT IN ('confirmed', 'awaiting_confirmation') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  IF p_payment_method NOT IN ('on_site','app') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  UPDATE appointments SET status='completed', completed_at=now(), updated_at=now(),
         full_payment_method=p_payment_method,
         full_payment_status = CASE WHEN p_payment_method='app' THEN 'paid' ELSE 'pending' END
    WHERE id=p_appointment_id;
  IF v_appt.client_user_id IS NOT NULL THEN
    PERFORM public._appt_notify_client(v_appt.client_user_id, 'appointment_completed', 'Obrigado!',
            'A tua marcação foi concluída. Até à próxima!', p_appointment_id::text);
  END IF;
  RETURN jsonb_build_object('success', true, 'status','completed');
END $$;

-- 5) Resposta do parceiro: "Faltou" — definitiva, mas o Danilo e avisado no momento
CREATE OR REPLACE FUNCTION public.partner_mark_no_show(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_appt record; v_prov text; v_eur text;
BEGIN
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_appt.provider_id);
  IF v_appt.status NOT IN ('confirmed', 'awaiting_confirmation') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  UPDATE appointments SET status='no_show', no_show_at=now(), updated_at=now(),
         no_show_decided_by='partner', no_show_decided_at=now(),
         deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END
    WHERE id=p_appointment_id;

  SELECT name INTO v_prov FROM public.service_providers WHERE id = v_appt.provider_id;
  v_eur := (COALESCE(v_appt.deposit_cents, 0) / 100.0)::numeric(10,2)::text || ' €';
  PERFORM public.notify_admin_event(
    'appointment_no_show_by_partner', 'high',
    'Falta marcada por ' || COALESCE(v_prov, 'parceiro') || ': ' || COALESCE(v_appt.client_name, 'cliente') ||
      ' às ' || to_char(v_appt.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      '. ' || v_eur || ' ficam retidos. Reverter em "Dinheiro retido por falta".',
    'appointment', p_appointment_id::text,
    jsonb_build_object('provider_id', v_appt.provider_id, 'deposit_cents', v_appt.deposit_cents),
    '/admin/dinheiro-retido-falta');
  PERFORM public._telegram_admin(
    'Bora · marcações: ' || COALESCE(v_prov, 'o parceiro') || ' marcou FALTA a ' ||
    COALESCE(v_appt.client_name, 'cliente') || ' (' || to_char(v_appt.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
    '). ' || v_eur || ' ficam retidos até o fecho da semana. Se estiver errado, reverte no painel em "Dinheiro retido por falta".');
  RETURN jsonb_build_object('success', true, 'status','no_show');
END $$;

-- 6) Painel: listas ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_appointments_awaiting_confirmation()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record; v_items jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'provider_id', a.provider_id, 'provider_name', sp.name,
      'client_name', a.client_name, 'client_phone', a.client_phone,
      'scheduled_at', a.scheduled_at,
      'scheduled_label', to_char(a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
      'service_price_cents', a.service_price_cents, 'deposit_cents', a.deposit_cents,
      'deposit_status', a.deposit_status, 'status', a.status,
      'awaiting_since', a.awaiting_since, 'confirm_asked_count', a.confirm_asked_count,
      'confirm_last_asked_at', a.confirm_last_asked_at, 'is_demo', public.is_demo_user(a.client_user_id)
    ) ORDER BY a.scheduled_at), '[]'::jsonb)
  INTO v_items
  FROM public.appointments a
  LEFT JOIN public.service_providers sp ON sp.id = a.provider_id
  WHERE a.status = 'awaiting_confirmation'
     OR (a.status = 'confirmed' AND a.scheduled_at + make_interval(mins => COALESCE(a.duration_minutes, 30)) < now());
  RETURN jsonb_build_object('items', v_items, 'generated_at', now());
END $$;

CREATE OR REPLACE FUNCTION public.admin_list_appointments_retained()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record; v_items jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', a.id, 'provider_id', a.provider_id, 'provider_name', sp.name,
      'client_name', a.client_name, 'client_phone', a.client_phone,
      'scheduled_at', a.scheduled_at,
      'scheduled_label', to_char(a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
      'service_price_cents', a.service_price_cents, 'deposit_cents', a.deposit_cents,
      'deposit_status', a.deposit_status, 'status', a.status,
      'no_show_at', a.no_show_at, 'no_show_decided_by', a.no_show_decided_by,
      'week_param', to_char((SELECT b.week_start FROM public.driver_settlement_week_bounds(a.scheduled_at) b) AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD'),
      'is_demo', public.is_demo_user(a.client_user_id)
    ) ORDER BY a.no_show_at DESC NULLS LAST), '[]'::jsonb)
  INTO v_items
  FROM public.appointments a
  LEFT JOIN public.service_providers sp ON sp.id = a.provider_id
  WHERE a.status IN ('no_show', 'cancelled') AND a.deposit_status = 'retained';
  RETURN jsonb_build_object('items', v_items, 'generated_at', now(),
    'total_cents', (SELECT COALESCE(sum(deposit_cents), 0) FROM public.appointments WHERE status IN ('no_show','cancelled') AND deposit_status = 'retained'));
END $$;

-- 7) Painel: decisoes a 1 toque ---------------------------------------------------
-- "Foi feita": passa a concluida, o valor pago fica 'paid' e entra no acerto do parceiro.
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
  PERFORM public.log_admin_action('appointment_confirmed_done_by_admin', 'appointment', p_appointment_id::text,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note));
  RETURN jsonb_build_object('success', true, 'status', 'completed', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

-- "Faltou" decidido pelo Danilo: unica outra forma de a falta ficar definitiva.
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
  PERFORM public.log_admin_action('appointment_no_show_by_admin', 'appointment', p_appointment_id::text,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note));
  PERFORM public._telegram_admin('Bora · marcações: marcaste FALTA a ' || COALESCE(v_a.client_name, 'cliente') ||
    ' (' || to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || '). ' ||
    (COALESCE(v_a.deposit_cents, 0) / 100.0)::numeric(10,2) || ' € ficam retidos até o fecho da semana.');
  RETURN jsonb_build_object('success', true, 'status', 'no_show', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

-- Reverter uma falta: passa a feita e o valor volta ao acerto do parceiro.
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
  PERFORM public.log_admin_action('appointment_no_show_reverted_by_admin', 'appointment', p_appointment_id::text,
    jsonb_build_object('provider_id', v_a.provider_id, 'deposit_cents', v_a.deposit_cents, 'note', p_note,
                       'decidida_por', v_a.no_show_decided_by));
  SELECT name INTO v_prov FROM public.service_providers WHERE id = v_a.provider_id;
  PERFORM public._appt_notify_partner(v_a.provider_id, 'appointment_no_show_reverted',
    'Marcação de ' || to_char(v_a.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') || ' dada como feita',
    'A falta foi revertida pela Bora. O valor entra no teu acerto da semana.', p_appointment_id::text);
  RETURN jsonb_build_object('success', true, 'status', 'completed', 'provider_id', v_a.provider_id,
    'week_start', (SELECT b.week_start FROM public.driver_settlement_week_bounds(v_a.scheduled_at) b));
END $$;

-- Perguntar outra vez ao parceiro, a pedido do Danilo.
CREATE OR REPLACE FUNCTION public.admin_appointment_ask_partner_again(p_appointment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin record;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  PERFORM public._appt_ask_partner_confirmation(p_appointment_id);
  PERFORM public.log_admin_action('appointment_partner_asked_again', 'appointment', p_appointment_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('success', true);
END $$;

REVOKE ALL ON FUNCTION public.admin_list_appointments_awaiting_confirmation() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_appointments_retained() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_appointment_confirm_done(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_appointment_mark_no_show(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_appointment_revert_no_show(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_appointment_ask_partner_again(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_appointments_awaiting_confirmation() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_appointments_retained() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_appointment_confirm_done(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_appointment_mark_no_show(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_appointment_revert_no_show(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_appointment_ask_partner_again(uuid) TO authenticated, service_role;
