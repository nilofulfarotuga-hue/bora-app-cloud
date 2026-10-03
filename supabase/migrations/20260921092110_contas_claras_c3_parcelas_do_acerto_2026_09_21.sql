-- 2026-09-21 — CONTAS CLARAS · Bloco C3 · o extrato da app mostra as MESMAS parcelas do recibo.
--
-- O QUE MEXE (e porquê):
--   1. NOVA driver_settlement_parcelas(entregas, ganhos, corridas, ganhos_corridas, reembolsos, tokens, em_mão):
--      a lista de parcelas do acerto do estafeta — Entregas · Corridas · Compras que adiantou do bolso ·
--      Tokens convertidos · Dinheiro que recebeu em mão (devolve à Bora) — copiada LETRA A LETRA da
--      expressão que estava dentro de weekly_closeout_compile (regra dos gémeos: uma verdade só).
--   2. weekly_closeout_compile passa a chamar essa função em vez de ter a expressão dentro. Saída igual
--      (provado em rollback contra o breakdown já gravado da semana 14–20/09, nos 3 estafetas).
--   3. extrato_prestador (o extrato do estafeta na app) devolve 'parcelas' em cada acerto e na semana em
--      curso, vindas da mesma função. O Flutter só formata; não soma nada.
--
-- O QUE NÃO MEXE: nenhum valor, nenhuma fórmula do acerto, nenhuma linha paga.

-- ---------------------------------------------------------------------------
-- 1. a função única das parcelas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_settlement_parcelas(
  p_total_deliveries integer, p_total_earnings numeric, p_tvde_rides_count integer, p_tvde_earnings numeric,
  p_total_reimbursements numeric, p_tokens_converted_value numeric, p_total_cash_received numeric)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT
         -- As parcelas, pela ordem por que se leem: o que ganhou, o que
         -- adiantou e lhe volta, e por fim o que tem em mao e devolve.
         (CASE WHEN COALESCE(p_total_deliveries,0) <> 0
                 OR round((COALESCE(p_total_earnings,0) - COALESCE(p_tvde_earnings,0)) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Entregas',
                      'qty', COALESCE(p_total_deliveries,0),
                      'value_cents', round((COALESCE(p_total_earnings,0) - COALESCE(p_tvde_earnings,0)) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN COALESCE(p_tvde_rides_count,0) <> 0
                 OR round(COALESCE(p_tvde_earnings,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Corridas',
                      'qty', COALESCE(p_tvde_rides_count,0),
                      'value_cents', round(COALESCE(p_tvde_earnings,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(p_total_reimbursements,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Compras que adiantou do bolso',
                      'value_cents', round(COALESCE(p_total_reimbursements,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(p_tokens_converted_value,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Tokens convertidos',
                      'value_cents', round(COALESCE(p_tokens_converted_value,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(p_total_cash_received,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Dinheiro que recebeu em mão (devolve à Bora)',
                      'value_cents', -round(COALESCE(p_total_cash_received,0) * 100)::int))
               ELSE '[]'::jsonb END)
$function$;

-- ---------------------------------------------------------------------------
-- 2. o recibo semanal usa a função
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.weekly_closeout_compile(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ws date;
  v_total int := 0;
  v_summary jsonb;
BEGIN
  v_ws := COALESCE(p_week_start, (
    SELECT max(w) FROM (
      SELECT week_start_at::date w FROM driver_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM cleaner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM appointment_payouts
      UNION ALL SELECT week_start_at::date FROM partner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM washer_weekly_settlements
    ) x WHERE w < (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date));
  IF v_ws IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'week_start', null, 'total', 0,
      'to_pay', '[]'::jsonb, 'to_receive', '[]'::jsonb, 'zero_count', 0,
      'note', 'sem settlements para compilar');
  END IF;

  -- DRIVERS (euros; net_balance ja vem SIGNED, negativo = deve a Bora)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'driver', s.driver_id::text,
         COALESCE(d.name, 'Estafeta'),
         COALESCE(NULLIF(d.email,''), u.email),
         COALESCE(NULLIF(d.mbway_phone,''), d.phone),
         round(s.net_balance * 100)::int,
         CASE WHEN s.net_balance < 0 THEN 'owes_bora'
              WHEN s.net_balance > 0 THEN 'bora_pays' ELSE 'zero' END,
         -- As parcelas (uma verdade só: driver_settlement_parcelas — o extrato da app lê a mesma)
         public.driver_settlement_parcelas(s.total_deliveries, s.total_earnings, s.tvde_rides_count, s.tvde_earnings,
                                          s.total_reimbursements, s.tokens_converted_value, s.total_cash_received),
         'pending'
  FROM driver_weekly_settlements s
  LEFT JOIN drivers d ON d.id::text = s.driver_id::text OR d.user_id::text = s.driver_id::text
  LEFT JOIN auth.users u ON u.id = d.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- CLEANERS (cents; net_payout_cents, direcao pelo texto ou sinal)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'cleaner', s.cleaner_id::text,
         COALESCE(c.name,'Profissional de limpeza'),
         COALESCE(NULLIF(c.email,''), u.email),
         COALESCE(NULLIF(c.mbway_phone,''), c.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Limpezas','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM cleaner_weekly_settlements s
  LEFT JOIN cleaners c ON c.id::text = s.cleaner_id::text OR c.user_id::text = s.cleaner_id::text
  LEFT JOIN auth.users u ON u.id = c.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PROVIDERS / servicos (cents; net_payout_cents)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'provider', s.provider_id::text,
         COALESCE(sp.name,'Parceiro de servicos'),
         u.email,
         COALESCE(NULLIF(sp.mbway_phone,''), sp.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Marcacoes','qty',COALESCE(s.total_appointments,0),'value_cents',COALESCE(s.total_service_revenue_cents,0)),
           jsonb_build_object('label','Sinais retidos','value_cents',COALESCE(s.total_deposits_retained_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.bora_booking_fees_cents,0))
         ),
         'pending'
  FROM appointment_payouts s
  LEFT JOIN service_providers sp ON sp.id::text = s.provider_id::text OR sp.user_id::text = s.provider_id::text
  LEFT JOIN auth.users u ON u.id = sp.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PARTNERS / restaurantes (euros; net_balance SIGNED)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'partner', s.partner_id::text,
         COALESCE(r.name,'Parceiro'),
         COALESCE(NULLIF(r.email,''), u.email),
         COALESCE(NULLIF(r.mbway_phone,''), r.phone),
         round(COALESCE(s.net_balance,0) * 100)::int,
         CASE WHEN COALESCE(s.net_balance,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_balance,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Pedidos','qty',COALESCE(s.total_orders,0),'value_cents',round(COALESCE(s.gross_sales,0)*100)::int),
           jsonb_build_object('label','Comissao Bora','value_cents',-round(COALESCE(s.commission_total,0)*100)::int),
           jsonb_build_object('label','Cash retido pelo parceiro','value_cents',round(COALESCE(s.cash_kept_by_partner,0)*100)::int)
         ),
         'pending'
  FROM partner_weekly_settlements s
  LEFT JOIN restaurants r ON r.id::text = s.partner_id::text OR r.user_id::text = s.partner_id::text
  LEFT JOIN auth.users u ON u.id = r.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- WASHERS / lavagem auto (cents; net_payout_cents) — ACRESCENTADO 2026-09-07.
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'washer', s.washer_id::text,
         COALESCE(wa.name,'Profissional de lavagem'),
         COALESCE(NULLIF(wa.email,''), u.email),
         COALESCE(NULLIF(wa.mbway_phone,''), wa.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Lavagens','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM washer_weekly_settlements s
  LEFT JOIN washers wa ON wa.id::text = s.washer_id::text OR wa.user_id::text = s.washer_id::text
  LEFT JOIN auth.users u ON u.id = wa.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  SELECT count(*)::int INTO v_total FROM weekly_digest_log WHERE week_start_at::date = v_ws;

  SELECT jsonb_build_object(
    'ok', true, 'week_start', v_ws,
    'week_end', (SELECT max(week_end_at)::date FROM weekly_digest_log WHERE week_start_at::date = v_ws),
    'total', v_total,
    'to_pay', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='bora_pays'), '[]'::jsonb),
    'to_receive', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='owes_bora'), '[]'::jsonb),
    'zero_count', (SELECT count(*)::int FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='zero')
  ) INTO v_summary;

  RETURN v_summary;
END $function$;

-- ---------------------------------------------------------------------------
-- 3. o extrato da app devolve as mesmas parcelas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.extrato_prestador(p_semanas integer DEFAULT 4, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller     uuid := auth.uid();
  v_uid        uuid;
  v_nome       text;
  v_dia_ini    timestamptz;
  v_sem_ini    timestamptz;
  v_semp_ini   timestamptz;
  v_de         timestamptz;
  v_trabalhos  jsonb;
  v_resumo     jsonb;
  v_entregas   jsonb;
  v_corridas   jsonb;
  v_carteira   jsonb;
  v_cash       jsonb;
  v_acertos    jsonb;
  v_semana     jsonb;
  v_taloes     jsonb;
  v_deve_lhe   jsonb;
  v_deve       jsonb;
  v_linhas_lhe jsonb := '[]'::jsonb;
  v_linhas_dev jsonb := '[]'::jsonb;
  v_db         numeric;   -- driver_balances (euros)
  v_tvde       numeric;   -- tvde_driver_balances (euros; positivo = deve à Bora)
  v_tvde_fora  integer := 0;  -- corridas de semanas passadas que nenhum acerto contou (cêntimos; positivo = a Bora deve)
  v_wallet     integer;
  v_r          record;
  v_semana_ja_tem_linha boolean := false;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  v_uid := COALESCE(p_user_id, v_caller);
  IF v_uid <> v_caller AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  p_semanas := LEAST(GREATEST(COALESCE(p_semanas, 4), 1), 26);

  SELECT d.name INTO v_nome FROM public.drivers d WHERE d.user_id = v_uid LIMIT 1;

  v_dia_ini  := date_trunc('day',  now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_sem_ini  := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_semp_ini := v_sem_ini - interval '7 days';
  v_de       := v_sem_ini - make_interval(weeks => p_semanas - 1);

  -- trabalhos do período (mais recentes primeiro)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'tipo', t.tipo, 'ref_id', t.ref_id, 'quando', t.quando,
           'quando_txt', to_char(t.quando AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
           'dia', to_char(t.quando AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD'),
           'descricao', t.descricao, 'de', t.de, 'para', t.para, 'pagamento', t.pagamento,
           'cliente_pagou_cents', t.cliente_pagou_cents, 'ganhou_cents', t.ganhou_cents,
           'parte_bora_cents', t.parte_bora_cents, 'pagou_na_loja_cents', t.pagou_na_loja_cents,
           'recebeu_em_mao_cents', t.recebeu_em_mao_cents, 'fica_para_a_bora_cents', t.fica_para_a_bora_cents,
           'acerto_cents', t.acerto_cents, 'distancia_km', t.distancia_km, 'tokens', t.tokens,
           'parcelas', COALESCE(t.parcelas, '[]'::jsonb), 'entra_no_acerto', t.entra_no_acerto, 'nota', t.nota
         ) ORDER BY t.quando DESC), '[]'::jsonb),
         jsonb_build_object(
           'hoje', jsonb_build_object(
              'ganho_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_dia_ini), 0),
              'trabalhos',   COUNT(*) FILTER (WHERE t.quando >= v_dia_ini),
              'tokens',      COALESCE(SUM(t.tokens) FILTER (WHERE t.quando >= v_dia_ini), 0)),
           'semana', jsonb_build_object(
              'ganho_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_sem_ini), 0),
              'trabalhos',   COUNT(*) FILTER (WHERE t.quando >= v_sem_ini),
              'tokens',      COALESCE(SUM(t.tokens) FILTER (WHERE t.quando >= v_sem_ini), 0),
              'entregas_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_sem_ini AND t.tipo = 'entrega'), 0),
              'corridas_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_sem_ini AND t.tipo = 'corrida'), 0),
              'compensacoes_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_sem_ini AND t.tipo = 'compensacao'), 0)),
           'semana_passada', jsonb_build_object(
              'ganho_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.quando >= v_semp_ini AND t.quando < v_sem_ini), 0),
              'trabalhos',   COUNT(*) FILTER (WHERE t.quando >= v_semp_ini AND t.quando < v_sem_ini),
              'tokens',      COALESCE(SUM(t.tokens) FILTER (WHERE t.quando >= v_semp_ini AND t.quando < v_sem_ini), 0)))
    INTO v_trabalhos, v_resumo
    FROM public._prestador_trabalhos(v_uid, v_de) t;

  -- conta-corrente das ENTREGAS: histórico (driver_transactions) × saldo (driver_balances)
  SELECT b.balance INTO v_db FROM public.driver_balances b WHERE b.driver_id = v_uid;
  SELECT jsonb_build_object(
           'ganhos_total_cents',        COALESCE(ROUND(SUM(dt.amount) FILTER (WHERE dt.type = 'delivery_earning') * 100), 0)::int,
           'tokens_convertidos_cents',  COALESCE(ROUND(SUM(dt.amount) FILTER (WHERE dt.type = 'token_conversion') * 100), 0)::int,
           'ficou_para_a_bora_cents',   COALESCE(ROUND(SUM(dt.amount) FILTER (WHERE dt.type = 'cash_adjustment') * 100), 0)::int,
           'saldo_historico_cents',     COALESCE(ROUND((SUM(dt.amount) FILTER (WHERE dt.type IN ('delivery_earning','token_conversion'))
                                                       - COALESCE(SUM(dt.amount) FILTER (WHERE dt.type = 'cash_adjustment'), 0)) * 100), 0)::int,
           'saldo_arca_cents',          CASE WHEN v_db IS NULL THEN NULL ELSE ROUND(v_db * 100)::int END,
           'linhas',                    COUNT(*))
    INTO v_entregas
    FROM public.driver_transactions dt
   WHERE dt.driver_id = v_uid AND dt.status = 'completed';
  v_entregas := v_entregas || jsonb_build_object(
    'bate', (v_entregas->>'saldo_arca_cents') IS NOT DISTINCT FROM (v_entregas->>'saldo_historico_cents'),
    'nota', 'Saldo vitalício das entregas: ganhos + tokens convertidos − o que ficou em mão e é da Bora. Não desce quando um acerto é pago — o acerto semanal é que diz o que falta receber.');

  -- conta-corrente das CORRIDAS (TVDE): eventos × tvde_driver_balances (positivo = deve à Bora)
  SELECT b.balance INTO v_tvde FROM public.tvde_driver_balances b
   WHERE b.driver_id = v_uid OR b.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = v_uid) LIMIT 1;
  SELECT jsonb_build_object(
           'bora_deve_cents',        COALESCE(-SUM((e.meta->>'settle_cents')::int) FILTER (WHERE (e.meta->>'settle_cents')::int < 0), 0),
           'deve_a_bora_cents',      COALESCE( SUM((e.meta->>'settle_cents')::int) FILTER (WHERE (e.meta->>'settle_cents')::int > 0), 0),
           'saldo_historico_cents',  COALESCE(-SUM((e.meta->>'settle_cents')::int), 0),
           'saldo_arca_cents',       CASE WHEN v_tvde IS NULL THEN NULL ELSE -ROUND(v_tvde * 100)::int END,
           'corridas',               COUNT(*))
    INTO v_corridas
    FROM public.tvde_ride_events e
    JOIN public.tvde_rides r ON r.id = e.ride_id
   WHERE e.status = 'finalizada'
     AND (r.driver_id = v_uid OR r.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = v_uid));
  v_corridas := v_corridas || jsonb_build_object(
    'bate', (v_corridas->>'saldo_arca_cents') IS NOT DISTINCT FROM (v_corridas->>'saldo_historico_cents'),
    'nota', 'Positivo = a Bora deve-lhe (corridas pagas na app); negativo = deve à Bora (parte da Bora nas corridas a dinheiro). Desde 20/09/2026 o TVDE entra no acerto semanal; as corridas de semanas anteriores que nenhum acerto contou ficam aqui como "fora do acerto".');

  -- Corridas de semanas PASSADAS que nenhum acerto contou (acertos fechados antes de 20/09/2026
  -- não tinham TVDE): positivo = a Bora deve. A semana em curso vem pela previsão oficial.
  SELECT COALESCE(-SUM((e.meta->>'settle_cents')::int), 0)
    INTO v_tvde_fora
    FROM public.tvde_ride_events e
    JOIN public.tvde_rides r ON r.id = e.ride_id
   WHERE e.status = 'finalizada'
     AND (r.driver_id = v_uid OR r.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = v_uid))
     AND r.created_at < v_sem_ini
     AND NOT EXISTS (
       SELECT 1 FROM public.driver_weekly_settlements s
        WHERE s.driver_id = v_uid
          AND COALESCE(s.tvde_rides_count, 0) > 0
          AND r.created_at >= s.week_start_at AND r.created_at <= s.week_end_at);

  -- carteira (reembolsos de talão creditados, saldo livre)
  SELECT w.free_balance_cents INTO v_wallet FROM public.client_wallets w WHERE w.user_id = v_uid;
  SELECT jsonb_build_object(
           'saldo_cents', v_wallet,
           'linhas', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'quando', wt.created_at, 'quando_txt', to_char(wt.created_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
                        'kind', wt.kind, 'valor_cents', wt.amount_cents, 'motivo', wt.reason,
                        'pedido', wt.related_order_id, 'saldo_depois_cents', wt.balance_after_cents,
                        'conta_no_saldo', NOT (wt.kind = ANY (public.wallet_kinds_fora_do_saldo()))) ORDER BY wt.created_at DESC)
                      FROM (SELECT * FROM public.wallet_transactions WHERE user_id = v_uid ORDER BY created_at DESC LIMIT 30) wt), '[]'::jsonb))
    INTO v_carteira;

  -- dinheiro em mão (período): pedidos e corridas a dinheiro
  SELECT jsonb_build_object(
           'total_recebido_cents',   COALESCE(SUM(t.recebeu_em_mao_cents), 0),
           'total_pagou_na_loja_cents', COALESCE(SUM(t.pagou_na_loja_cents) FILTER (WHERE t.pagamento = 'cash'), 0),
           'total_fica_para_ela_cents', COALESCE(SUM(t.ganhou_cents) FILTER (WHERE t.pagamento = 'cash'), 0),
           'total_fica_para_a_bora_cents', COALESCE(SUM(t.fica_para_a_bora_cents), 0),
           'linhas', COALESCE(jsonb_agg(jsonb_build_object(
                        'tipo', t.tipo, 'ref_id', t.ref_id, 'quando', t.quando,
                        'quando_txt', to_char(t.quando AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
                        'descricao', t.descricao,
                        'recebeu_do_cliente_cents', t.recebeu_em_mao_cents,
                        'pagou_na_loja_cents', t.pagou_na_loja_cents,
                        'fica_para_ela_cents', t.ganhou_cents,
                        'fica_para_a_bora_cents', t.fica_para_a_bora_cents) ORDER BY t.quando DESC), '[]'::jsonb))
    INTO v_cash
    FROM public._prestador_trabalhos(v_uid, v_de) t
   WHERE t.recebeu_em_mao_cents > 0;

  -- acertos semanais (os últimos 8) + comprovativo
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', s.id, 'semana', to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '–' || to_char(s.week_end_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM'),
           'week_start', s.week_start_at, 'entregas', s.total_deliveries,
           'ganhos_cents', ROUND(s.total_earnings * 100)::int,
           'cash_recebido_cents', ROUND(COALESCE(s.total_cash_received, 0) * 100)::int,
           'tokens_cents', ROUND(COALESCE(s.tokens_converted_value, 0) * 100)::int,
           'liquido_cents', ROUND(s.net_balance * 100)::int,
           -- as MESMAS parcelas do recibo semanal (driver_settlement_parcelas), pela mesma ordem
           'parcelas', public.driver_settlement_parcelas(s.total_deliveries, s.total_earnings, s.tvde_rides_count, s.tvde_earnings,
                                                         s.total_reimbursements, s.tokens_converted_value, s.total_cash_received),
           'sentido', s.direction, 'estado', s.status,
           'pago_em', s.paid_at, 'pago_em_txt', CASE WHEN s.paid_at IS NULL THEN NULL ELSE to_char(s.paid_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY') END,
           'metodo', s.payment_method, 'referencia', s.payment_reference,
           'comprovativo', (SELECT jsonb_build_object('estado', sr.status, 'enviado_em', sr.sent_at, 'para', sr.to_email)
                              FROM public.settlement_receipts sr
                             WHERE sr.subject_type = 'driver' AND sr.subject_id = v_uid::text
                               AND sr.week_start_at = s.week_start_at
                             ORDER BY sr.created_at DESC LIMIT 1)
         ) ORDER BY s.week_start_at DESC), '[]'::jsonb)
    INTO v_acertos
    FROM (SELECT * FROM public.driver_weekly_settlements WHERE driver_id = v_uid ORDER BY week_start_at DESC LIMIT 8) s;

  -- semana em curso pela fórmula oficial do acerto (sem persistir). O invólucro
  -- _prestador_semana_em_curso chama a função do acerto; se ainda não existir, a app
  -- mostra "—" com a razão — nunca um número inventado.
  BEGIN
    v_semana := public._prestador_semana_em_curso(v_uid);
  EXCEPTION WHEN OTHERS THEN
    v_semana := jsonb_build_object('erro', 'previsao_indisponivel', 'detalhe', SQLERRM);
  END;
  -- A previsão leva as MESMAS parcelas do recibo (mesma função, mesma ordem), para o
  -- ecrã da app e o email dizerem a mesma coisa ao cêntimo.
  IF v_semana ? 'net_balance' THEN
    v_semana := v_semana || jsonb_build_object('parcelas', public.driver_settlement_parcelas(
      (v_semana->>'total_deliveries')::int, (v_semana->>'total_earnings')::numeric,
      (v_semana->>'tvde_rides_count')::int, (v_semana->>'tvde_earnings')::numeric,
      (v_semana->>'total_reimbursements')::numeric, (v_semana->>'tokens_converted_value')::numeric,
      (v_semana->>'total_cash_received')::numeric));
  END IF;

  -- talões por reembolsar / reembolsados (pedidos desta pessoa)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'receipt_id', rc.id, 'pedido', rc.order_id, 'quando', rc.created_at,
           'valor_cents', COALESCE(rc.reimbursement_amount_cents, rc.driver_typed_total_cents),
           'estado', rc.reimbursement_status, 'forma', rc.reimbursement_method,
           'pago_em', COALESCE(rc.reimbursement_external_paid_at, rc.reimbursement_processed_at),
           'texto', CASE rc.reimbursement_status
                      WHEN 'pending_admin' THEN 'Reembolso do talão por pagar'
                      WHEN 'admin_paid' THEN 'Reembolso ' || CASE rc.reimbursement_method
                          WHEN 'wallet' THEN 'creditado na carteira'
                          WHEN 'mbway' THEN 'pago por MB Way'
                          WHEN 'cash' THEN 'pago em dinheiro'
                          WHEN 'transfer' THEN 'pago por transferência'
                          ELSE 'pago (forma não registada)' END
                          || COALESCE(' a ' || to_char(COALESCE(rc.reimbursement_external_paid_at, rc.reimbursement_processed_at) AT TIME ZONE 'Europe/Lisbon', 'DD/MM'), '')
                      WHEN 'cash_settled' THEN 'Talão liquidado com o dinheiro do cliente'
                      WHEN 'rejected' THEN 'Reembolso recusado'
                      ELSE rc.reimbursement_status END
         ) ORDER BY rc.created_at DESC), '[]'::jsonb)
    INTO v_taloes
    FROM public.order_receipts_v2 rc
    JOIN public.orders o ON o.id = rc.order_id
   WHERE o.assigned_driver_id = v_uid::text
     AND rc.created_at >= v_de;

  -- "A Bora deve-lhe" e "Deve à Bora": linhas com nome, nunca um número solto
  FOR v_r IN SELECT s.* FROM public.driver_weekly_settlements s
            WHERE s.driver_id = v_uid AND s.status NOT IN ('paid','received') AND s.net_balance <> 0
            ORDER BY s.week_start_at LOOP
    -- a linha pendente da semana em curso é provisória: se a previsão viva existir, é ela que conta
    IF v_r.week_start_at >= v_sem_ini AND (v_semana ? 'net_balance') THEN CONTINUE; END IF;
    IF v_r.week_start_at >= v_sem_ini THEN v_semana_ja_tem_linha := true; END IF;
    IF v_r.net_balance > 0 THEN
      v_linhas_lhe := v_linhas_lhe || jsonb_build_object('nome',
                        CASE WHEN v_r.week_start_at >= v_sem_ini THEN 'Esta semana (fecha na segunda-feira)'
                             ELSE 'Acerto da semana ' || to_char(v_r.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' por pagar' END,
                        'valor_cents', ROUND(v_r.net_balance * 100)::int, 'origem', 'acerto_semanal', 'ref_id', v_r.id);
    ELSE
      v_linhas_dev := v_linhas_dev || jsonb_build_object('nome',
                        CASE WHEN v_r.week_start_at >= v_sem_ini THEN 'Esta semana (fecha na segunda-feira)'
                             ELSE 'Acerto da semana ' || to_char(v_r.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' por entregar à Bora' END,
                        'valor_cents', -ROUND(v_r.net_balance * 100)::int, 'origem', 'acerto_semanal', 'ref_id', v_r.id);
    END IF;
  END LOOP;
  -- a previsão da semana em curso só entra se ainda não houver linha de acerto para esta semana
  IF (v_semana ? 'net_balance') AND NOT v_semana_ja_tem_linha THEN
    IF (v_semana->>'net_balance')::numeric > 0 THEN
      v_linhas_lhe := v_linhas_lhe || jsonb_build_object('nome', 'Esta semana (ainda por fechar)', 'valor_cents', ROUND((v_semana->>'net_balance')::numeric * 100)::int, 'origem', 'semana_em_curso');
    ELSIF (v_semana->>'net_balance')::numeric < 0 THEN
      v_linhas_dev := v_linhas_dev || jsonb_build_object('nome', 'Esta semana (ainda por fechar)', 'valor_cents', -ROUND((v_semana->>'net_balance')::numeric * 100)::int, 'origem', 'semana_em_curso');
    END IF;
  END IF;
  IF v_tvde_fora <> 0 THEN
    IF v_tvde_fora > 0 THEN
      v_linhas_lhe := v_linhas_lhe || jsonb_build_object('nome', 'Corridas TVDE de semanas anteriores a 20/09 (nenhum acerto as contou)', 'valor_cents', v_tvde_fora, 'origem', 'tvde_fora_do_acerto');
    ELSE
      v_linhas_dev := v_linhas_dev || jsonb_build_object('nome', 'Parte da Bora nas corridas a dinheiro anteriores a 20/09 (nenhum acerto as contou)', 'valor_cents', -v_tvde_fora, 'origem', 'tvde_fora_do_acerto');
    END IF;
  END IF;
  FOR v_r IN SELECT rc.id, rc.driver_typed_total_cents, rc.order_id FROM public.order_receipts_v2 rc JOIN public.orders o ON o.id = rc.order_id
            WHERE o.assigned_driver_id = v_uid::text AND rc.reimbursement_status = 'pending_admin' LOOP
    v_linhas_lhe := v_linhas_lhe || jsonb_build_object('nome', 'Talão por reembolsar (pedido ' || left(v_r.order_id, 8) || ')', 'valor_cents', v_r.driver_typed_total_cents, 'origem', 'talao', 'ref_id', v_r.id);
  END LOOP;
  IF COALESCE(v_wallet, 0) < 0 THEN
    v_linhas_dev := v_linhas_dev || jsonb_build_object('nome', 'Carteira Bora em negativo', 'valor_cents', -v_wallet, 'origem', 'carteira');
  END IF;
  SELECT jsonb_build_object('total_cents', COALESCE(SUM((x->>'valor_cents')::int), 0), 'linhas', v_linhas_lhe)
    INTO v_deve_lhe FROM jsonb_array_elements(v_linhas_lhe) x;
  SELECT jsonb_build_object('total_cents', COALESCE(SUM((x->>'valor_cents')::int), 0), 'linhas', v_linhas_dev)
    INTO v_deve FROM jsonb_array_elements(v_linhas_dev) x;

  RETURN jsonb_build_object(
    'ok', true,
    'gerado_em', now(),
    'pessoa', jsonb_build_object('user_id', v_uid, 'nome', v_nome),
    'periodo', jsonb_build_object('de', v_de, 'ate', now(), 'semanas', p_semanas),
    'resumo', v_resumo,
    'trabalhos', v_trabalhos,
    'entregas', v_entregas,
    'corridas', v_corridas,
    'carteira', v_carteira,
    'dinheiro_em_mao', v_cash,
    'acertos', v_acertos,
    'semana_em_curso', v_semana,
    'taloes', v_taloes,
    'deve_lhe_a_bora', v_deve_lhe,
    'deve_a_bora', v_deve,
    'saldo_cents', (v_deve_lhe->>'total_cents')::int - (v_deve->>'total_cents')::int
  );
END;
$$;
