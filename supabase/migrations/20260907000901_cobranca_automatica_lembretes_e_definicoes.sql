-- BLOCO 4 — 2026-09-07 — quem deve a Bora e lembrado sozinho.
-- O Danilo nao volta a andar atras de ninguem: quarta e sexta de manha, quem
-- ficou a dever recebe email e aviso no telemovel, e ele recebe UMA mensagem
-- com a lista de quem falta.
--
-- Tudo o que se liga e desliga fica em platform_settings, nunca cravado no
-- corpo da funcao (PADRAO_BORA 1.15).

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('settlement_reminders_enabled', 'true'::jsonb,
   'Liga os lembretes automaticos a quem ficou a dever a Bora no fecho semanal', 'fecho_semanal'),
  ('settlement_reminder_weekdays', '[3,5]'::jsonb,
   'Dias da semana dos lembretes (1=segunda ... 7=domingo). Por defeito quarta e sexta', 'fecho_semanal'),
  ('settlement_reminder_hour', '10'::jsonb,
   'Hora (Europe/Lisbon) a que os lembretes saem', 'fecho_semanal'),
  ('settlement_reminder_max_weeks', '8'::jsonb,
   'Ate quantas semanas para tras se continua a lembrar uma divida por acertar', 'fecho_semanal'),
  ('driver_cash_debt_block_cents', '0'::jsonb,
   'Tecto de divida acumulada do estafeta a partir do qual deixa de receber pedidos. 0 = desligado', 'fecho_semanal'),
  ('settlement_carry_over_enabled', 'false'::jsonb,
   'Transporta a divida por acertar para o fecho seguinte. DESLIGADO por defeito: mexe em valores', 'fecho_semanal')
ON CONFLICT (key) DO NOTHING;

-- Quem esta a dever e ainda nao acertou, por ordem de valor.
CREATE OR REPLACE FUNCTION public.settlement_debtors(p_max_weeks int DEFAULT NULL)
 RETURNS TABLE (
   subject_type text, subject_id text, subject_name text, subject_email text,
   subject_phone text, week_start_at timestamptz, cents int, dias int)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT w.subject_type, w.subject_id, w.subject_name, w.subject_email,
         w.subject_phone, w.week_start_at, abs(w.net_cents)::int,
         GREATEST(0, (now()::date - w.week_end_at::date))::int
  FROM weekly_digest_log w
  LEFT JOIN LATERAL (
    SELECT status FROM (
      SELECT status, 'driver' t, driver_id::text sid, week_start_at FROM driver_weekly_settlements
      UNION ALL SELECT status, 'cleaner', cleaner_id::text, week_start_at FROM cleaner_weekly_settlements
      UNION ALL SELECT status, 'provider', provider_id::text, week_start_at FROM appointment_payouts
      UNION ALL SELECT status, 'partner', partner_id::text, week_start_at FROM partner_weekly_settlements
      UNION ALL SELECT status, 'washer', washer_id::text, week_start_at FROM washer_weekly_settlements
    ) s WHERE s.t = w.subject_type AND s.sid = w.subject_id
        AND s.week_start_at::date = w.week_start_at::date
    LIMIT 1
  ) st ON true
  WHERE w.direction = 'owes_bora'
    AND COALESCE(st.status, 'pending') NOT IN ('received','paid','rolled_over','disputed','cancelled')
    AND w.week_start_at >= (now() - make_interval(weeks =>
          COALESCE(p_max_weeks, (public.get_setting('settlement_reminder_max_weeks') #>> '{}')::int, 8)))
  ORDER BY abs(w.net_cents) DESC;
$function$;

-- A tarefa agendada corre de hora a hora e so age no dia e hora configurados.
-- Assim o Danilo muda o dia no painel sem ninguem mexer no agendamento.
CREATE OR REPLACE FUNCTION public._settlement_debt_reminders()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_agora timestamptz := now() AT TIME ZONE 'Europe/Lisbon';
  v_dia int := EXTRACT(ISODOW FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int;
  v_hora int := EXTRACT(HOUR FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int;
  v_dias jsonb;
  v_hora_alvo int;
  v_n int := 0;
BEGIN
  IF COALESCE((public.get_setting('settlement_reminders_enabled') #>> '{}')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'lembretes desligados');
  END IF;

  v_dias := COALESCE(public.get_setting('settlement_reminder_weekdays'), '[3,5]'::jsonb);
  v_hora_alvo := COALESCE((public.get_setting('settlement_reminder_hour') #>> '{}')::int, 10);

  IF v_hora <> v_hora_alvo THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'fora da hora', 'hora', v_hora);
  END IF;
  IF NOT (v_dias @> to_jsonb(v_dia)) THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'hoje nao e dia de lembrete', 'dia', v_dia);
  END IF;

  SELECT count(*)::int INTO v_n FROM public.settlement_debtors();
  IF v_n = 0 THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'ninguem em divida');
  END IF;

  PERFORM net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')
           || '/functions/v1/settlement-receipt',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
      'Content-Type', 'application/json'),
    body := jsonb_build_object('mode', 'reminders')
  );

  RETURN jsonb_build_object('ok', true, 'devedores', v_n, 'dia', v_dia, 'hora', v_hora);
END $function$;

REVOKE ALL ON FUNCTION public.settlement_debtors(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._settlement_debt_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.settlement_debtors(int) TO service_role;
GRANT EXECUTE ON FUNCTION public._settlement_debt_reminders() TO service_role;

-- Definicoes novas do fecho, todas a partir do painel.
CREATE OR REPLACE FUNCTION public.admin_update_weekly_closeout_settings(
  p_bora_mbway text DEFAULT NULL::text,
  p_emails_enabled boolean DEFAULT NULL::boolean,
  p_reminders_enabled boolean DEFAULT NULL::boolean,
  p_reminder_weekdays jsonb DEFAULT NULL::jsonb,
  p_reminder_hour int DEFAULT NULL::int,
  p_debt_block_cents int DEFAULT NULL::int,
  p_carry_over_enabled boolean DEFAULT NULL::boolean
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  IF p_bora_mbway IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_bora_mbway), updated_at=now(), updated_by=auth.uid() WHERE key='bora_mbway_phone';
  END IF;
  IF p_emails_enabled IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_emails_enabled), updated_at=now(), updated_by=auth.uid() WHERE key='weekly_digest_emails_enabled';
  END IF;
  IF p_reminders_enabled IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_reminders_enabled), updated_at=now(), updated_by=auth.uid() WHERE key='settlement_reminders_enabled';
  END IF;
  IF p_reminder_weekdays IS NOT NULL THEN
    UPDATE platform_settings SET value=p_reminder_weekdays, updated_at=now(), updated_by=auth.uid() WHERE key='settlement_reminder_weekdays';
  END IF;
  IF p_reminder_hour IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_reminder_hour), updated_at=now(), updated_by=auth.uid() WHERE key='settlement_reminder_hour';
  END IF;
  IF p_debt_block_cents IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_debt_block_cents), updated_at=now(), updated_by=auth.uid() WHERE key='driver_cash_debt_block_cents';
  END IF;
  IF p_carry_over_enabled IS NOT NULL THEN
    UPDATE platform_settings SET value=to_jsonb(p_carry_over_enabled), updated_at=now(), updated_by=auth.uid() WHERE key='settlement_carry_over_enabled';
  END IF;

  PERFORM public.log_admin_action('update_weekly_closeout_settings', 'platform_settings', 'weekly_closeout',
    jsonb_build_object('mbway_set', p_bora_mbway IS NOT NULL, 'emails_enabled', p_emails_enabled,
                       'reminders_enabled', p_reminders_enabled, 'reminder_weekdays', p_reminder_weekdays,
                       'reminder_hour', p_reminder_hour, 'debt_block_cents', p_debt_block_cents,
                       'carry_over_enabled', p_carry_over_enabled));

  RETURN jsonb_build_object('ok', true,
    'bora_mbway', (public.get_setting('bora_mbway_phone') #>> '{}'),
    'emails_enabled', (public.get_setting('weekly_digest_emails_enabled') #>> '{}'),
    'reminders_enabled', (public.get_setting('settlement_reminders_enabled') #>> '{}'),
    'reminder_weekdays', public.get_setting('settlement_reminder_weekdays'),
    'reminder_hour', (public.get_setting('settlement_reminder_hour') #>> '{}'),
    'debt_block_cents', (public.get_setting('driver_cash_debt_block_cents') #>> '{}'),
    'carry_over_enabled', (public.get_setting('settlement_carry_over_enabled') #>> '{}'));
END $function$;;
