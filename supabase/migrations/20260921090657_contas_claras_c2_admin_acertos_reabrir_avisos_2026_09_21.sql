-- 2026-09-21 — CONTAS CLARAS · Bloco C2 · painel admin dos acertos (PT-BR, só o Danilo).
--
-- O QUE MEXE (e porquê):
--   1. admin_weekly_closeout_list(p_week_start): a lista do ecrã "Dinheiro e acertos" passa a
--      trazer, em cada linha de estafeta, o objecto `acerto` lido de driver_weekly_settlements
--      (nº de corridas TVDE, ganhos das corridas, dinheiro em mão das corridas, compras que
--      adiantou = total_reimbursements, notas) e `reabrir_permitido` (só a semana em curso ou a
--      última fechada). O valor do recibo enviado (weekly_digest_log) continua a ser o `net_cents`
--      da linha; o do acerto vivo vem em `acerto.net_cents` — quando diferem, o ecrã avisa.
--   2. admin_reabrir_acerto(tipo, id, semana, motivo): reabre um acerto marcado pago/recebido.
--      Pede motivo por escrito (mínimo 5 letras), grava-o em <tabela>.notes com data e quem, e em
--      admin_audit_log (action 'reabrir_acerto'). Semanas anteriores à última fechada ficam
--      travadas (excepção semana_travada). Põe o recibo dessa pessoa em weekly_digest_log de
--      volta a 'pending' para que o próximo "Reenviar recibos" o recompile com o valor novo.
--      O RECÁLCULO do estafeta é pedido pela app ao servidor a seguir (a função de cálculo do
--      acerto do estafeta já existe e já aceita o admin) — esta função não a chama porque a
--      Trava do PC recusa DDL cujo texto nomeie uma função de acerto, e a Trava não se contorna.
--   3. admin_avisos_fecho(p_week_start): os dois avisos novos do fecho, com nome, valores e link:
--      'fecho_linha_travada_valor_diferente' / 'fecho_aviso_linha_travada_falhou' (admin_audit_log)
--      e 'pedido_no_vermelho' (admin_notifications).
--
-- O QUE NÃO MEXE: nenhum valor cobrado ou pago, nenhuma linha paga de semana antiga, nenhum
-- preço, comissão ou taxa. Só leitura + estado de linha + auditoria.

-- ---------------------------------------------------------------------------
-- 1. lista do ecrã: acerto vivo + permissão de reabrir
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_weekly_closeout_list(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ws date; v_out jsonb;
        v_monday date := (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date;
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
       'breakdown', w.breakdown,
       -- CONTAS CLARAS C2: a linha do acerto tal como está na tabela (o recibo é um retrato;
       -- isto é o vivo). Só estafetas por agora.
       'acerto', CASE WHEN dw.week_start_at IS NULL THEN NULL ELSE jsonb_build_object(
          'week_start_at', dw.week_start_at,
          'status', dw.status,
          'net_cents', dw.net_cents,
          'entregas_n', dw.entregas_n,
          'entregas_cents', dw.entregas_cents,
          'corridas_n', dw.corridas_n,
          'corridas_cents', dw.corridas_cents,
          'corridas_em_mao_cents', dw.corridas_em_mao_cents,
          'entregas_em_mao_cents', dw.entregas_em_mao_cents,
          'em_mao_cents', dw.em_mao_cents,
          'reembolsos_cents', dw.reembolsos_cents,
          'tokens_cents', dw.tokens_cents,
          'notes', dw.notes) END,
       'week_start_at', st.week_start_at,
       'reabrir_permitido', (st.week_start_at IS NOT NULL
                             AND (st.week_start_at AT TIME ZONE 'Europe/Lisbon')::date >= v_monday - 7)
     ) ORDER BY abs(w.net_cents) DESC) FILTER (WHERE w.id IS NOT NULL), '[]'::jsonb)
  ) INTO v_out
  FROM weekly_digest_log w
  LEFT JOIN LATERAL (
    SELECT status, paid_at, payment_reference, week_start_at FROM (
      SELECT status, paid_at, payment_reference, 'driver' t, driver_id::text sid, week_start_at FROM driver_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'cleaner', cleaner_id::text, week_start_at FROM cleaner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'provider', provider_id::text, week_start_at FROM appointment_payouts
      UNION ALL SELECT status, paid_at, payment_reference, 'partner', partner_id::text, week_start_at FROM partner_weekly_settlements
      UNION ALL SELECT status, paid_at, payment_reference, 'washer', washer_id::text, week_start_at FROM washer_weekly_settlements
    ) s WHERE s.t = w.subject_type AND s.sid = w.subject_id AND s.week_start_at::date = w.week_start_at::date
    LIMIT 1
  ) st ON true
  LEFT JOIN LATERAL (
    SELECT s.week_start_at, s.status, s.notes,
           round(COALESCE(s.net_balance,0) * 100)::int AS net_cents,
           COALESCE(s.total_deliveries,0) AS entregas_n,
           round((COALESCE(s.total_earnings,0) - COALESCE(s.tvde_earnings,0)) * 100)::int AS entregas_cents,
           COALESCE(s.tvde_rides_count,0) AS corridas_n,
           round(COALESCE(s.tvde_earnings,0) * 100)::int AS corridas_cents,
           round(COALESCE(s.tvde_cash_received,0) * 100)::int AS corridas_em_mao_cents,
           round((COALESCE(s.total_cash_received,0) - COALESCE(s.tvde_cash_received,0)) * 100)::int AS entregas_em_mao_cents,
           round(COALESCE(s.total_cash_received,0) * 100)::int AS em_mao_cents,
           round(COALESCE(s.total_reimbursements,0) * 100)::int AS reembolsos_cents,
           round(COALESCE(s.tokens_converted_value,0) * 100)::int AS tokens_cents
      FROM driver_weekly_settlements s
     WHERE w.subject_type = 'driver'
       AND s.driver_id::text = w.subject_id
       AND s.week_start_at::date = w.week_start_at::date
     LIMIT 1
  ) dw ON true
  LEFT JOIN LATERAL (
    SELECT r.status, r.last_error, r.sent_at FROM settlement_receipts r
     WHERE r.subject_type = w.subject_type AND r.subject_id = w.subject_id
       AND r.week_start_at::date = w.week_start_at::date
     ORDER BY r.created_at DESC LIMIT 1
  ) rc ON true
  WHERE w.week_start_at::date = v_ws;

  RETURN v_out;
END $function$;

-- ---------------------------------------------------------------------------
-- 2. reabrir um acerto (motivo obrigatório; só semana em curso ou última fechada)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reabrir_acerto(
  p_subject_type text, p_subject_id text, p_week_start date, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     uuid := auth.uid();
  v_email   text := COALESCE(auth.jwt() ->> 'email', '');
  v_monday  date := (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date;
  v_motivo  text := trim(COALESCE(p_motivo, ''));
  v_id      uuid;
  v_ws      timestamptz;
  v_status  text;
  v_valor   numeric;
  v_notes   text;
  v_nota    text;
  v_n       int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF length(v_motivo) < 5 THEN
    RAISE EXCEPTION 'motivo_obrigatorio: escreve porque reabres este acerto (mínimo 5 letras)';
  END IF;

  IF p_subject_type = 'driver' THEN
    SELECT id, week_start_at, status, net_balance, notes INTO v_id, v_ws, v_status, v_valor, v_notes
      FROM driver_weekly_settlements WHERE driver_id::text = p_subject_id AND week_start_at::date = p_week_start;
  ELSIF p_subject_type = 'partner' THEN
    SELECT id, week_start_at, status, net_balance, notes INTO v_id, v_ws, v_status, v_valor, v_notes
      FROM partner_weekly_settlements WHERE partner_id::text = p_subject_id AND week_start_at::date = p_week_start;
  ELSIF p_subject_type = 'cleaner' THEN
    SELECT id, week_start_at, status, net_payout_cents / 100.0, notes INTO v_id, v_ws, v_status, v_valor, v_notes
      FROM cleaner_weekly_settlements WHERE cleaner_id::text = p_subject_id AND week_start_at::date = p_week_start;
  ELSIF p_subject_type = 'washer' THEN
    SELECT id, week_start_at, status, net_payout_cents / 100.0, notes INTO v_id, v_ws, v_status, v_valor, v_notes
      FROM washer_weekly_settlements WHERE washer_id::text = p_subject_id AND week_start_at::date = p_week_start;
  ELSIF p_subject_type = 'provider' THEN
    SELECT id, week_start_at, status, net_payout_cents / 100.0, notes INTO v_id, v_ws, v_status, v_valor, v_notes
      FROM appointment_payouts WHERE provider_id::text = p_subject_id AND week_start_at::date = p_week_start;
  ELSE
    RAISE EXCEPTION 'tipo desconhecido: %', p_subject_type;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'acerto_nao_encontrado: % % semana %', p_subject_type, p_subject_id, p_week_start;
  END IF;

  -- Só a semana em curso ou a última fechada. Mais antigo fica travado: o histórico não se reescreve.
  IF (v_ws AT TIME ZONE 'Europe/Lisbon')::date < v_monday - 7 THEN
    RAISE EXCEPTION 'semana_travada: só se reabre a semana em curso ou a última fechada; esta começou a %',
      to_char((v_ws AT TIME ZONE 'Europe/Lisbon')::date, 'DD/MM/YYYY');
  END IF;

  v_nota := format('[%s] Reaberto por %s — motivo: %s (estava %s, valor %s EUR)',
                   to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI'),
                   COALESCE(NULLIF(v_email, ''), v_uid::text), v_motivo,
                   COALESCE(v_status, 'pending'), to_char(COALESCE(v_valor, 0), 'FM9990.00'));

  IF p_subject_type = 'driver' THEN
    UPDATE driver_weekly_settlements SET status = 'pending', paid_at = NULL, paid_by = NULL,
           notes = concat_ws(E'\n', NULLIF(notes, ''), v_nota) WHERE id = v_id;
  ELSIF p_subject_type = 'partner' THEN
    UPDATE partner_weekly_settlements SET status = 'pending', paid_at = NULL, paid_by = NULL,
           notes = concat_ws(E'\n', NULLIF(notes, ''), v_nota) WHERE id = v_id;
  ELSIF p_subject_type = 'cleaner' THEN
    UPDATE cleaner_weekly_settlements SET status = 'pending', paid_at = NULL, paid_by = NULL,
           notes = concat_ws(E'\n', NULLIF(notes, ''), v_nota) WHERE id = v_id;
  ELSIF p_subject_type = 'washer' THEN
    UPDATE washer_weekly_settlements SET status = 'pending', paid_at = NULL, paid_by = NULL,
           notes = concat_ws(E'\n', NULLIF(notes, ''), v_nota) WHERE id = v_id;
  ELSE
    UPDATE appointment_payouts SET status = 'pending', paid_at = NULL, paid_by = NULL,
           notes = concat_ws(E'\n', NULLIF(notes, ''), v_nota) WHERE id = v_id;
  END IF;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- O recibo desta pessoa volta a "por enviar": o próximo "Reenviar recibos" recompila-o com o
  -- valor novo em vez de mandar outra vez o retrato antigo.
  UPDATE weekly_digest_log SET email_status = 'pending',
         email_error = 'reaberto pelo admin: ' || v_motivo
   WHERE subject_type = p_subject_type AND subject_id = p_subject_id
     AND week_start_at::date = p_week_start;

  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_uid, v_email, 'reabrir_acerto', p_subject_type, p_subject_id,
          jsonb_build_object('week_start', v_ws, 'motivo', v_motivo,
                             'estado_anterior', v_status, 'valor_anterior', v_valor,
                             'linhas', v_n,
                             'recalculo', CASE WHEN p_subject_type = 'driver'
                                               THEN 'pedido pela app ao servidor a seguir'
                                               ELSE 'não automático' END));

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'week_start_at', v_ws,
                            'estado_anterior', v_status, 'valor_anterior', v_valor,
                            'recalcular', p_subject_type = 'driver');
END $function$;

REVOKE ALL ON FUNCTION public.admin_reabrir_acerto(text, text, date, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reabrir_acerto(text, text, date, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. avisos novos do fecho, com nome, valores e link
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_avisos_fecho(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_travadas jsonb; v_vermelho jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', a.id, 'quando', a.created_at, 'action', a.action,
           'driver_id', a.entity_id_text,
           'nome', a.details ->> 'nome',
           'estado_da_linha', a.details ->> 'estado_da_linha',
           'valor_na_linha', a.details ->> 'valor_na_linha',
           'valor_recalculado', a.details ->> 'valor_recalculado',
           'diferenca', a.details ->> 'diferenca',
           'nota', a.details ->> 'nota',
           'erro', a.details ->> 'erro',
           'week_start', a.details ->> 'week_start') ORDER BY a.created_at DESC), '[]'::jsonb)
    INTO v_travadas
    FROM admin_audit_log a
   WHERE a.action IN ('fecho_linha_travada_valor_diferente', 'fecho_aviso_linha_travada_falhou')
     AND (p_week_start IS NULL
          OR ((a.details ->> 'week_start') IS NOT NULL
              AND (a.details ->> 'week_start')::timestamptz::date = p_week_start));

  SELECT COALESCE(jsonb_agg(x ORDER BY (x ->> 'quando') DESC), '[]'::jsonb) INTO v_vermelho
    FROM (
      SELECT jsonb_build_object(
           'id', n.id, 'quando', n.created_at, 'severity', n.severity,
           'order_id', n.entity_id,
           'vendor_name', n.payload ->> 'vendor_name',
           'cliente_pagou', n.payload ->> 'cliente_pagou',
           'mercadoria', n.payload ->> 'mercadoria',
           'estafeta', n.payload ->> 'estafeta',
           'sobrou_para_a_bora', n.payload ->> 'sobrou_para_a_bora',
           'small_order_fee', n.payload ->> 'small_order_fee',
           'catalog_price_gap_cents', n.payload ->> 'catalog_price_gap_cents',
           'summary', n.summary, 'deep_link', n.deep_link,
           'read_at', n.read_at) AS x
        FROM admin_notifications n
       WHERE n.event_type = 'pedido_no_vermelho' AND n.archived_at IS NULL
       ORDER BY n.created_at DESC
       LIMIT 50) q;

  RETURN jsonb_build_object('ok', true, 'fecho_travado', v_travadas, 'pedidos_no_vermelho', v_vermelho);
END $function$;

REVOKE ALL ON FUNCTION public.admin_avisos_fecho(date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_avisos_fecho(date) TO authenticated, service_role;
