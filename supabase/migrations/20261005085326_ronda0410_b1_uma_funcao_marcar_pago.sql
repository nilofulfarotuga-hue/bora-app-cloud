-- Ronda 04/10 Bloco B item 1: uma so funcao de marcar pago/recebido.
-- admin_set_settlement_state passa a ser a UNICA que escreve o estado pago/recebido
-- nos acertos semanais; as outras mantem a assinatura e chamam-na.
-- Mudanca na propria funcao: nao reescreve linhas ja pagas/recebidas/canceladas
-- (antes voltava a carimbar paid_at/paid_by numa linha ja paga).
--
-- Achado: log_admin_action(text,text,TEXT,jsonb) escrevia numa tabela admin_logs que
-- NAO EXISTE e engolia o erro -> todas as marcacoes de pago feitas pela funcao unica
-- (e mais ~38 funcoes admin_*) nunca deixaram rasto. Passa a escrever em admin_audit_log
-- (entity_id_text + entity_id quando o texto e um uuid). Nunca falha a operacao, mas
-- avisa (RAISE WARNING) em vez de calar.
CREATE OR REPLACE FUNCTION public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uuid uuid;
BEGIN
  IF p_entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_uuid := p_entity_id::uuid;
  END IF;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, entity_id_text, details)
  VALUES (auth.uid(),
          COALESCE(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
          COALESCE(NULLIF(trim(p_action_type), ''), 'acao_admin'),
          p_entity_type, v_uuid, p_entity_id, COALESCE(p_details, '{}'::jsonb));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'log_admin_action(text): auditoria falhou: %', SQLERRM;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_settlement_state(p_subject_type text, p_subject_id text, p_week_start date, p_status text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dir text;
  v_alvo text;
  v_n int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT w.direction INTO v_dir
    FROM public.weekly_digest_log w
   WHERE w.subject_type = p_subject_type
     AND w.subject_id   = p_subject_id
     AND public._semana_bate(w.week_start_at, p_week_start)
   LIMIT 1;

  IF v_dir IS NULL THEN
    v_dir := CASE p_subject_type
      WHEN 'driver' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                      WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM driver_weekly_settlements
                           WHERE driver_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'partner' THEN (SELECT CASE WHEN net_balance < 0 THEN 'owes_bora'
                                       WHEN net_balance > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM partner_weekly_settlements
                           WHERE partner_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'cleaner' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM cleaner_weekly_settlements
                           WHERE cleaner_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'washer'  THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                       WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM washer_weekly_settlements
                           WHERE washer_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      WHEN 'provider' THEN (SELECT CASE WHEN net_payout_cents < 0 THEN 'owes_bora'
                                        WHEN net_payout_cents > 0 THEN 'bora_pays' ELSE 'zero' END
                            FROM appointment_payouts
                           WHERE provider_id::text = p_subject_id AND public._semana_bate(week_start_at, p_week_start) LIMIT 1)
      ELSE NULL END;
  END IF;

  IF v_dir IS NULL THEN
    RAISE EXCEPTION 'acerto nao encontrado para % % na semana %', p_subject_type, p_subject_id, p_week_start;
  END IF;

  v_alvo := COALESCE(NULLIF(p_status,''),
                     CASE v_dir WHEN 'bora_pays' THEN 'paid'
                                WHEN 'owes_bora' THEN 'received'
                                ELSE NULL END);

  IF v_dir = 'zero' THEN
    RETURN jsonb_build_object('ok', true, 'rows', 0, 'nota', 'acerto a zero — nada a marcar');
  END IF;
  IF v_alvo NOT IN ('paid','received') THEN
    RAISE EXCEPTION 'estado invalido: %', v_alvo;
  END IF;
  IF v_dir = 'bora_pays' AND v_alvo <> 'paid' THEN
    RAISE EXCEPTION 'a Bora e que paga este acerto — o estado tem de ser pago';
  END IF;
  IF v_dir = 'owes_bora' AND v_alvo <> 'received' THEN
    RAISE EXCEPTION 'esta pessoa e que paga a Bora — o estado tem de ser recebido';
  END IF;

  IF p_subject_type = 'driver' THEN
    UPDATE driver_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE driver_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start)
       AND status NOT IN ('paid','received','cancelled');
  ELSIF p_subject_type = 'partner' THEN
    UPDATE partner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE partner_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start)
       AND status NOT IN ('paid','received','cancelled');
  ELSIF p_subject_type = 'cleaner' THEN
    UPDATE cleaner_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE cleaner_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start)
       AND status NOT IN ('paid','received','cancelled');
  ELSIF p_subject_type = 'washer' THEN
    UPDATE washer_weekly_settlements
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE washer_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start)
       AND status NOT IN ('paid','received','cancelled');
  ELSIF p_subject_type = 'provider' THEN
    UPDATE appointment_payouts
       SET status=v_alvo, paid_at=now(), paid_by=v_uid,
           payment_reference=COALESCE(p_payment_reference, payment_reference)
     WHERE provider_id::text=p_subject_id AND public._semana_bate(week_start_at, p_week_start)
       AND status NOT IN ('paid','received','cancelled');
  ELSE
    RAISE EXCEPTION 'tipo desconhecido: %', p_subject_type;
  END IF;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  PERFORM public.log_admin_action('mark_settlement_' || v_alvo, p_subject_type, p_subject_id,
    jsonb_build_object('week_start', p_week_start, 'rows', v_n,
                       'direction', v_dir, 'reference', p_payment_reference));

  RETURN jsonb_build_object('ok', true, 'rows', v_n, 'status', v_alvo, 'direction', v_dir);
END $function$;

-- Por pessoa (Acerto por pessoa / Extrato do dono): passa pela funcao unica,
-- linha a linha. Antes marcava sempre 'paid', mesmo quando era a pessoa a dever.
CREATE OR REPLACE FUNCTION public.admin_marcar_acerto_pago(p_user_id uuid, p_semana date, p_metodo text DEFAULT NULL::text, p_referencia text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid uuid := auth.uid(); n_d int := 0; n_c int := 0; n_w int := 0;
  r record; v_res jsonb; v_n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF p_user_id IS NULL OR p_semana IS NULL THEN RAISE EXCEPTION 'faltam_argumentos'; END IF;

  FOR r IN
    SELECT 'driver'::text AS t, s.driver_id::text AS sid, s.id,
           (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date AS semana
      FROM driver_weekly_settlements s
     WHERE s.driver_id = p_user_id
       AND date_trunc('week', s.week_start_at)::date = p_semana
       AND s.status NOT IN ('paid', 'received')
    UNION ALL
    SELECT 'cleaner', s.cleaner_id::text, s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date
      FROM cleaner_weekly_settlements s
     WHERE s.cleaner_id IN (SELECT c.id FROM cleaners c WHERE c.user_id = p_user_id)
       AND date_trunc('week', s.week_start_at)::date = p_semana
       AND s.status NOT IN ('paid', 'received')
    UNION ALL
    SELECT 'washer', s.washer_id::text, s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date
      FROM washer_weekly_settlements s
     WHERE s.washer_id IN (SELECT w.id FROM washers w WHERE w.user_id = p_user_id)
       AND date_trunc('week', s.week_start_at)::date = p_semana
       AND s.status NOT IN ('paid', 'received')
  LOOP
    v_res := public.admin_set_settlement_state(r.t, r.sid, r.semana, NULL, p_referencia);
    v_n := COALESCE((v_res->>'rows')::int, 0);
    IF v_n > 0 AND p_metodo IS NOT NULL THEN
      IF r.t = 'driver' THEN
        UPDATE driver_weekly_settlements SET payment_method = p_metodo WHERE id = r.id;
      ELSIF r.t = 'cleaner' THEN
        UPDATE cleaner_weekly_settlements SET payment_method = p_metodo WHERE id = r.id;
      ELSE
        UPDATE washer_weekly_settlements SET payment_method = p_metodo WHERE id = r.id;
      END IF;
    END IF;
    IF r.t = 'driver' THEN n_d := n_d + v_n;
    ELSIF r.t = 'cleaner' THEN n_c := n_c + v_n;
    ELSE n_w := n_w + v_n; END IF;
  END LOOP;

  PERFORM public.log_admin_action('marcar_acerto_pago', 'pessoa', p_user_id::text,
    jsonb_build_object('semana', p_semana, 'driver', n_d, 'cleaner', n_c,
                       'washer', n_w, 'metodo', p_metodo,
                       'referencia', p_referencia, 'via', 'admin_set_settlement_state'));

  RETURN jsonb_build_object('ok', true, 'linhas', n_d + n_c + n_w,
    'driver', n_d, 'cleaner', n_c, 'washer', n_w);
END $function$;

-- Por id (estafeta): pago/recebido passa pela funcao unica; pendente/disputa fica como estava.
CREATE OR REPLACE FUNCTION public.admin_set_settlement_status(p_settlement_id uuid, p_new_status text, p_payment_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_uid UUID := auth.uid();
  v_settlement RECORD;
  v_res jsonb;
BEGIN
  IF NOT public._is_admin(v_admin_uid) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  IF p_new_status NOT IN ('paid', 'received', 'disputed', 'pending') THEN
    RAISE EXCEPTION 'invalid_status: %', p_new_status USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_settlement FROM public.driver_weekly_settlements
   WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_new_status IN ('paid','received') THEN
    v_res := public.admin_set_settlement_state('driver', v_settlement.driver_id::text,
               (v_settlement.week_start_at AT TIME ZONE 'Europe/Lisbon')::date,
               p_new_status, p_payment_reference);
    IF p_notes IS NOT NULL THEN
      UPDATE public.driver_weekly_settlements SET notes = p_notes WHERE id = p_settlement_id;
    END IF;
    RETURN jsonb_build_object('success', true, 'settlement_id', p_settlement_id,
                              'status', p_new_status, 'rows', v_res->'rows');
  END IF;

  UPDATE public.driver_weekly_settlements SET
    status            = p_new_status,
    payment_reference = COALESCE(p_payment_reference, payment_reference),
    notes             = COALESCE(p_notes, notes)
  WHERE id = p_settlement_id;

  PERFORM public.log_admin_action('settlement_set_status', 'settlement', p_settlement_id::text,
    jsonb_build_object(
      'previous_status', v_settlement.status,
      'new_status', p_new_status,
      'payment_reference', p_payment_reference,
      'notes', p_notes,
      'driver_id', v_settlement.driver_id,
      'net_balance', v_settlement.net_balance));

  RETURN jsonb_build_object(
    'success', true,
    'settlement_id', p_settlement_id,
    'status', p_new_status
  );
END;
$function$;

-- Por id (parceiro): idem.
CREATE OR REPLACE FUNCTION public.admin_set_partner_settlement_status(p_settlement_id uuid, p_new_status text, p_payment_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_uid UUID := auth.uid();
  v_settlement RECORD;
  v_res jsonb;
BEGIN
  IF NOT public._is_admin(v_admin_uid) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  IF p_new_status NOT IN ('pending', 'closed', 'paid', 'received', 'disputed') THEN
    RAISE EXCEPTION 'invalid_status: %', p_new_status USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_settlement FROM public.partner_weekly_settlements
   WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_new_status IN ('paid','received') THEN
    v_res := public.admin_set_settlement_state('partner', v_settlement.partner_id::text,
               (v_settlement.week_start_at AT TIME ZONE 'Europe/Lisbon')::date,
               p_new_status, p_payment_reference);
    IF p_notes IS NOT NULL THEN
      UPDATE public.partner_weekly_settlements SET notes = p_notes WHERE id = p_settlement_id;
    END IF;
    RETURN jsonb_build_object('ok', true, 'settlement_id', p_settlement_id,
                              'new_status', p_new_status, 'rows', v_res->'rows');
  END IF;

  UPDATE public.partner_weekly_settlements SET
    status            = p_new_status,
    payment_reference = COALESCE(p_payment_reference, payment_reference),
    notes             = COALESCE(p_notes, notes)
  WHERE id = p_settlement_id;

  PERFORM public.log_admin_action(
    'partner_settlement_status'::text,
    'partner_weekly_settlement'::text,
    p_settlement_id::text,
    jsonb_build_object(
      'partner_id', v_settlement.partner_id,
      'week_start', v_settlement.week_start_at,
      'old_status', v_settlement.status,
      'new_status', p_new_status,
      'net_balance', v_settlement.net_balance,
      'payment_reference', p_payment_reference
    )
  );

  RETURN jsonb_build_object('ok', true, 'settlement_id', p_settlement_id,
                            'new_status', p_new_status);
END;
$function$;

-- Lavagem (por id): passa pela funcao unica.
CREATE OR REPLACE FUNCTION public.admin_mark_carwash_settlement_paid(p_id uuid, p_method text DEFAULT 'mbway'::text, p_reference text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record; v_res jsonb;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT s.washer_id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date AS semana
    INTO r FROM washer_weekly_settlements s WHERE s.id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'acerto nao encontrado'; END IF;
  v_res := public.admin_set_settlement_state('washer', r.washer_id::text, r.semana,
             NULL, NULLIF(p_reference, ''));
  IF COALESCE((v_res->>'rows')::int, 0) > 0 THEN
    UPDATE washer_weekly_settlements SET payment_method = p_method WHERE id = p_id;
  END IF;
  PERFORM public._carwash_audit('carwash_settlement_paid', p_id,
    jsonb_build_object('metodo', p_method, 'referencia', p_reference, 'resultado', v_res));
  RETURN (SELECT to_jsonb(s) FROM washer_weekly_settlements s WHERE s.id = p_id);
END $function$;

-- Limpeza (todas as semanas pendentes da pessoa): passa pela funcao unica, semana a semana.
CREATE OR REPLACE FUNCTION public.admin_mark_cleaner_settlements_paid(p_cleaner_id uuid, p_payout_external_id uuid DEFAULT gen_random_uuid(), p_payment_method text DEFAULT 'mbway'::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int := 0; v_total int := 0; r record; v_res jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  FOR r IN
    SELECT s.id, s.net_payout_cents, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date AS semana
      FROM public.cleaner_weekly_settlements s
     WHERE s.cleaner_id = p_cleaner_id AND s.status = 'pending'
  LOOP
    v_res := public.admin_set_settlement_state('cleaner', p_cleaner_id::text, r.semana, NULL,
               COALESCE(p_payment_reference, p_payout_external_id::text));
    IF COALESCE((v_res->>'rows')::int, 0) > 0 THEN
      UPDATE public.cleaner_weekly_settlements
         SET payment_method = COALESCE(p_payment_method, payment_method, 'mbway')
       WHERE id = r.id;
      v_count := v_count + 1;
      v_total := v_total + COALESCE(r.net_payout_cents, 0);
    END IF;
  END LOOP;
  PERFORM public.log_admin_action(
    'cleaner_settlements_marked_paid', 'cleaner', p_cleaner_id::text,
    jsonb_build_object('count', v_count, 'total_cents', v_total,
                       'external_id', p_payout_external_id, 'method', p_payment_method));
  RETURN jsonb_build_object('success', true, 'count', v_count, 'total_cents', v_total,
                            'payout_external_id', p_payout_external_id);
END;
$function$;

-- Barbearias (todas as semanas pendentes do prestador): passa pela funcao unica.
CREATE OR REPLACE FUNCTION public.admin_mark_appointment_payouts_paid(p_provider_id text, p_payout_external_id uuid DEFAULT gen_random_uuid())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int := 0; v_total int := 0; r record; v_res jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  FOR r IN
    SELECT s.id, s.net_payout_cents, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date AS semana
      FROM appointment_payouts s
     WHERE s.provider_id = p_provider_id AND s.status = 'pending'
  LOOP
    v_res := public.admin_set_settlement_state('provider', p_provider_id, r.semana, NULL,
               p_payout_external_id::text);
    IF COALESCE((v_res->>'rows')::int, 0) > 0 THEN
      v_count := v_count + 1;
      v_total := v_total + COALESCE(r.net_payout_cents, 0);
    END IF;
  END LOOP;
  PERFORM public.log_admin_action('appointment_payouts_marked_paid','service_provider',p_provider_id,
    jsonb_build_object('count',v_count,'total_cents',v_total,'external_id',p_payout_external_id));
  RETURN jsonb_build_object('success',true,'count',v_count,'total_cents',v_total,'payout_external_id',p_payout_external_id);
END $function$;
