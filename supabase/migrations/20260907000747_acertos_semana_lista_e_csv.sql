-- BLOCO 2.1 / 2.4 / 2.6 — 2026-09-07
-- A lista do painel passa a trazer tudo o que o Danilo precisa de ver sem
-- abrir mais nada: a lavagem (que faltava), os tres totais em cima, a
-- referencia do pagamento, e o estado do comprovativo linha a linha.

CREATE OR REPLACE FUNCTION public.admin_weekly_closeout_list(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ws date; v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_ws := COALESCE(p_week_start, (SELECT max(week_start_at::date) FROM weekly_digest_log));

  SELECT jsonb_build_object(
    'ok', true,
    'week_start', v_ws,
    'week_end', (SELECT max(week_end_at)::date FROM weekly_digest_log WHERE week_start_at::date = v_ws),
    'bora_mbway', COALESCE(public.get_setting('bora_mbway_phone') #>> '{}', ''),
    'emails_enabled', COALESCE((public.get_setting('weekly_digest_emails_enabled') #>> '{}')::boolean, false),
    'weeks', COALESCE((SELECT jsonb_agg(DISTINCT week_start_at::date ORDER BY week_start_at::date DESC) FROM weekly_digest_log), '[]'::jsonb),
    'totais', jsonb_build_object(
       'pagar_cents',   COALESCE(sum(CASE WHEN w.direction='bora_pays' THEN abs(w.net_cents) END), 0),
       'receber_cents', COALESCE(sum(CASE WHEN w.direction='owes_bora' THEN abs(w.net_cents) END), 0),
       'saldo_cents',   COALESCE(sum(CASE WHEN w.direction='owes_bora' THEN abs(w.net_cents)
                                          WHEN w.direction='bora_pays' THEN -abs(w.net_cents) ELSE 0 END), 0),
       'n_pagar',   count(*) FILTER (WHERE w.direction='bora_pays'),
       'n_receber', count(*) FILTER (WHERE w.direction='owes_bora'),
       'n_zero',    count(*) FILTER (WHERE w.direction='zero'),
       'n_por_tratar', count(*) FILTER (WHERE w.direction <> 'zero' AND COALESCE(st.status,'pending') = 'pending')
    ),
    'items', COALESCE(jsonb_agg(jsonb_build_object(
       'id', w.id, 'type', w.subject_type, 'subject_id', w.subject_id,
       'name', w.subject_name, 'net_cents', w.net_cents, 'direction', w.direction,
       'mbway', w.subject_phone, 'email', w.subject_email,
       'email_status', w.email_status, 'email_error', w.email_error,
       'paid_status', COALESCE(st.status, 'pending'), 'paid_at', st.paid_at,
       'payment_reference', st.payment_reference,
       'receipt_status', rc.status, 'receipt_error', rc.last_error, 'receipt_sent_at', rc.sent_at,
       'breakdown', w.breakdown
     ) ORDER BY abs(w.net_cents) DESC) FILTER (WHERE w.id IS NOT NULL), '[]'::jsonb)
  ) INTO v_out
  FROM weekly_digest_log w
  LEFT JOIN LATERAL (
    SELECT status, paid_at, payment_reference FROM (
      SELECT status, paid_at, payment_reference, 'driver' t, driver_id::text sid, week_start_at FROM driver_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'cleaner', cleaner_id::text, week_start_at FROM cleaner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'provider', provider_id::text, week_start_at FROM appointment_payouts
      UNION ALL SELECT status, paid_at, payment_reference, 'partner', partner_id::text, week_start_at FROM partner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'washer', washer_id::text, week_start_at FROM washer_weekly_settlements
    ) s WHERE s.t = w.subject_type AND s.sid = w.subject_id AND s.week_start_at::date = w.week_start_at::date
    LIMIT 1
  ) st ON true
  LEFT JOIN LATERAL (
    SELECT r.status, r.last_error, r.sent_at FROM settlement_receipts r
     WHERE r.subject_type = w.subject_type AND r.subject_id = w.subject_id
       AND r.week_start_at::date = w.week_start_at::date
     ORDER BY r.created_at DESC LIMIT 1
  ) rc ON true
  WHERE w.week_start_at::date = v_ws;

  RETURN v_out;
END $function$;

-- BLOCO 2.6 — um ficheiro para a contabilista.
CREATE OR REPLACE FUNCTION public.admin_weekly_closeout_csv(p_week_start date DEFAULT NULL::date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ws date; v_csv text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_ws := COALESCE(p_week_start, (SELECT max(week_start_at::date) FROM weekly_digest_log));

  SELECT 'semana_inicio;semana_fim;tipo;nome;email;mbway;valor_eur;sentido;estado;pago_em;referencia' ||
         COALESCE(string_agg(E'\n' ||
           w.week_start_at::date || ';' || w.week_end_at::date || ';' ||
           w.subject_type || ';' || replace(COALESCE(w.subject_name,''), ';', ',') || ';' ||
           COALESCE(w.subject_email,'') || ';' || COALESCE(w.subject_phone,'') || ';' ||
           to_char(abs(w.net_cents)/100.0, 'FM999990.00') || ';' ||
           CASE w.direction WHEN 'bora_pays' THEN 'a Bora paga'
                            WHEN 'owes_bora' THEN 'deve a Bora' ELSE 'zero' END || ';' ||
           COALESCE(st.status,'pending') || ';' ||
           COALESCE(to_char(st.paid_at, 'YYYY-MM-DD HH24:MI'),'') || ';' ||
           COALESCE(st.payment_reference,'')
         , '' ORDER BY abs(w.net_cents) DESC), '')
    INTO v_csv
  FROM weekly_digest_log w
  LEFT JOIN LATERAL (
    SELECT status, paid_at, payment_reference FROM (
      SELECT status, paid_at, payment_reference, 'driver' t, driver_id::text sid, week_start_at FROM driver_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'cleaner', cleaner_id::text, week_start_at FROM cleaner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'provider', provider_id::text, week_start_at FROM appointment_payouts
      UNION ALL SELECT status, paid_at, payment_reference, 'partner', partner_id::text, week_start_at FROM partner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'washer', washer_id::text, week_start_at FROM washer_weekly_settlements
    ) s WHERE s.t = w.subject_type AND s.sid = w.subject_id AND s.week_start_at::date = w.week_start_at::date
    LIMIT 1
  ) st ON true
  WHERE w.week_start_at::date = v_ws;

  PERFORM public.log_admin_action('export_weekly_closeout_csv', 'weekly_digest', v_ws::text,
    jsonb_build_object('week_start', v_ws));
  RETURN v_csv;
END $function$;

REVOKE ALL ON FUNCTION public.admin_weekly_closeout_csv(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_weekly_closeout_csv(date) TO authenticated;;
