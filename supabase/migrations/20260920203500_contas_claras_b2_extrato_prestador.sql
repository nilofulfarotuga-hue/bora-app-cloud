-- 2026-09-20 — CONTAS CLARAS · Bloco 2 — EXTRATO DO ESTAFETA E DO MOTORISTA (uma RPC só).
--
-- Regra dura: o Flutter não faz contas de dinheiro. Tudo o que o ecrã "Ganhos / Extrato"
-- mostra vem de `extrato_prestador()`. `driver_earnings_summary()` (o que o ecrã antigo e o
-- cartão "ganho de hoje" já liam) passa a ler dos MESMOS trabalhos — uma verdade só.
--
-- Peças:
--   1) _prestador_trabalhos(uid, desde)  — a lista de trabalhos da pessoa: entregas (orders
--      entregues), compensações (ledger, pedidos cancelados depois de aceites) e corridas
--      TVDE (tvde_rides finalizadas + o evento `finalizada` com o acerto aplicado).
--      Cada trabalho leva: quando, de → para, pagamento, o que o cliente pagou, o que a
--      pessoa ganhou, a parte da Bora, o que pagou na loja, o que recebeu em mão, o que
--      fica para a Bora, km, tokens, e as parcelas com nome.
--   2) extrato_prestador(p_semanas, p_user_id) — resumo hoje/semana/semana passada; trabalhos;
--      conta-corrente das entregas (bate com driver_balances) e das corridas (bate com
--      tvde_driver_balances); carteira; dinheiro em mão; acertos semanais (com comprovativo);
--      semana em curso pela fórmula oficial do acerto (via _prestador_semana_em_curso, que a
--      Trava obriga a aplicar por outra mão — até lá a app mostra "—" com a razão);
--      "a Bora deve-lhe" e "deve à Bora", cada um com as linhas que o compõem.
--   3) driver_earnings_summary() — mesmo contrato de saída, mesma fonte.
--
-- Números que o servidor não souber vêm a NULL (a app mostra "—" com a razão), nunca 0.
-- Referência de clareza: docs/REFERENCIA-EXTRATOS.md (Uber / Glovo).

-- 1) trabalhos ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._prestador_trabalhos(p_uid uuid, p_de timestamptz)
RETURNS TABLE (
  tipo text, ref_id text, quando timestamptz, descricao text, de text, para text,
  pagamento text, cliente_pagou_cents integer, ganhou_cents integer, parte_bora_cents integer,
  pagou_na_loja_cents integer, recebeu_em_mao_cents integer, fica_para_a_bora_cents integer,
  acerto_cents integer, distancia_km numeric, tokens integer, parcelas jsonb,
  entra_no_acerto boolean, nota text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  -- ENTREGAS E FAVORES (pedidos entregues por esta pessoa; assigned_driver_id = user_id)
  SELECT 'entrega'::text,
         o.id::text,
         COALESCE(o.delivered_at, o.status_updated_at, o.created_at),
         (CASE WHEN o.service_type IN ('storeShopping','carryGroceries','sendPackage') THEN 'Favor · ' ELSE 'Entrega · ' END)
           || COALESCE(NULLIF(o.vendor_name,''), NULLIF(o.pickup_address,''), 'Pedido'),
         COALESCE(NULLIF(o.pickup_address,''), o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         o.payment_method,
         ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int,
         ROUND(COALESCE(o.driver_earnings, 0) * 100)::int,
         ROUND(COALESCE(o.platform_commission, 0) * 100)::int,
         ROUND(public.order_driver_reimbursement(o.id) * 100)::int,
         CASE WHEN o.payment_method = 'cash' THEN ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int ELSE 0 END,
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE 0 END,
         -- acerto: positivo = ela deve à Bora (ficou com dinheiro a mais); negativo = a Bora deve-lhe
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE -(ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) END,
         o.distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da entrega' ||
                     CASE WHEN o.distance_km IS NOT NULL THEN ' (' || replace(ROUND(o.distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) AS p
            UNION ALL
            SELECT jsonb_build_object('nome', 'Gorjeta do cliente', 'valor_cents', o.tip_amount_cents, 'informativo', true)
             WHERE COALESCE(o.tip_amount_cents, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Adiantou na loja (talão)', 'valor_cents', ROUND(public.order_driver_reimbursement(o.id) * 100)::int)
             WHERE public.order_driver_reimbursement(o.id) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id)
         ) s),
         true,
         NULL::text
    FROM public.orders o
   WHERE o.assigned_driver_id = p_uid::text
     AND o.status = 'delivered'
     AND COALESCE(o.delivered_at, o.status_updated_at, o.created_at) >= p_de
     AND COALESCE(o.is_test_order, false) = false

  UNION ALL

  -- COMPENSAÇÕES (linha de ganho no livro-razão sem pedido entregue: cancelado depois de aceite)
  SELECT 'compensacao'::text,
         l.order_id::text,
         l.created_at,
         'Compensação · pedido cancelado depois de aceite' || COALESCE(' · ' || NULLIF(o.vendor_name, ''), ''),
         COALESCE(o.pickup_address, o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         NULL::text,
         0, ROUND(l.amount * 100)::int, 0, 0, 0, 0,
         -(ROUND(l.amount * 100)::int),
         NULL::numeric, 0,
         jsonb_build_array(jsonb_build_object('nome', 'Compensação de cancelamento', 'valor_cents', ROUND(l.amount * 100)::int)),
         false,
         'Está no livro-razão e aqui; ainda não entra no acerto semanal (achado contas-claras 20/09/2026).'
    FROM public.ledger_entries l
    LEFT JOIN public.orders o ON o.id = l.order_id::text
   WHERE l.user_type = 'driver' AND l.type = 'earning'
     AND l.user_id = p_uid::text
     AND l.created_at >= p_de
     AND (o.id IS NULL OR o.status <> 'delivered')

  UNION ALL

  -- CORRIDAS TVDE
  SELECT 'corrida'::text,
         r.id::text,
         r.updated_at,
         'Corrida · ' || COALESCE(NULLIF(r.origin_label, ''), 'Origem') || ' → ' || COALESCE(NULLIF(r.dest_label, ''), 'Destino'),
         COALESCE(r.origin_label, ''),
         COALESCE(r.dest_label, ''),
         COALESCE(r.payment_method, 'cash'),
         COALESCE(r.final_fare_cents, 0),
         COALESCE(r.driver_earn_cents, 0),
         COALESCE(r.bora_cut_cents, 0),
         0,
         CASE WHEN COALESCE(r.payment_method, 'cash') = 'cash' THEN COALESCE(r.final_fare_cents, 0) + COALESCE((ev.meta->>'stops_cash_cents')::int, 0) ELSE 0 END,
         CASE WHEN COALESCE(r.payment_method, 'cash') = 'cash' THEN GREATEST(COALESCE((ev.meta->>'settle_cents')::int, r.bora_cut_cents, 0), 0) ELSE 0 END,
         COALESCE((ev.meta->>'settle_cents')::int,
                  CASE WHEN COALESCE(r.payment_method, 'cash') = 'cash' THEN r.bora_cut_cents ELSE -r.driver_earn_cents END),
         r.final_distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da corrida' ||
                     CASE WHEN r.final_distance_km IS NOT NULL THEN ' (' || replace(ROUND(r.final_distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', COALESCE(r.driver_earn_cents, 0) - COALESCE((ev.meta->>'extra_stops_driver_cents')::int, 0)) AS p
            UNION ALL
            SELECT jsonb_build_object('nome', 'Paragens extra', 'valor_cents', (ev.meta->>'extra_stops_driver_cents')::int)
             WHERE COALESCE((ev.meta->>'extra_stops_driver_cents')::int, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text)
         ) s),
         false,
         'O TVDE ainda não entra no acerto semanal: fica na conta-corrente das corridas (achado contas-claras 20/09/2026).'
    FROM public.tvde_rides r
    LEFT JOIN LATERAL (
      SELECT e.meta FROM public.tvde_ride_events e
       WHERE e.ride_id = r.id AND e.status = 'finalizada'
       ORDER BY e.at DESC LIMIT 1
    ) ev ON true
   WHERE (r.driver_id = p_uid OR r.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = p_uid))
     AND r.status = 'finalizada'
     AND r.updated_at >= p_de
$$;

REVOKE ALL ON FUNCTION public._prestador_trabalhos(uuid, timestamptz) FROM PUBLIC, anon, authenticated;

-- 2) o extrato ---------------------------------------------------------------------------
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
    'nota', 'Positivo = a Bora deve-lhe (corridas pagas na app); negativo = deve à Bora (parte da Bora nas corridas a dinheiro). O TVDE ainda não entra no acerto semanal.');

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
  IF v_tvde IS NOT NULL AND v_tvde <> 0 THEN
    IF v_tvde < 0 THEN
      v_linhas_lhe := v_linhas_lhe || jsonb_build_object('nome', 'Corridas TVDE pagas na app (fora do acerto)', 'valor_cents', -ROUND(v_tvde * 100)::int, 'origem', 'tvde');
    ELSE
      v_linhas_dev := v_linhas_dev || jsonb_build_object('nome', 'Parte da Bora nas corridas a dinheiro (fora do acerto)', 'valor_cents', ROUND(v_tvde * 100)::int, 'origem', 'tvde');
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

REVOKE ALL ON FUNCTION public.extrato_prestador(integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extrato_prestador(integer, uuid) TO authenticated;

COMMENT ON FUNCTION public.extrato_prestador(integer, uuid) IS
  'Contas claras (20/09/2026): o extrato do estafeta/motorista — a única fonte do ecrã Ganhos. p_user_id só para admin.';

-- 3) driver_earnings_summary: mesmo contrato, mesma fonte -------------------------------
CREATE OR REPLACE FUNCTION public.driver_earnings_summary()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_dia_ini    timestamptz;
  v_sem_ini    timestamptz;
  v_semp_ini   timestamptz;
  v_itens      jsonb;
  v_dia_total  numeric := 0;
  v_sem_total  numeric := 0;
  v_semp_total numeric := 0;
  v_dia_tokens int := 0;
  v_sem_tokens int := 0;
  v_semp_tokens int := 0;
  v_settle     jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  v_dia_ini  := date_trunc('day',  now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_sem_ini  := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_semp_ini := v_sem_ini - interval '7 days';

  -- contas claras (20/09/2026): os itens vêm dos MESMOS trabalhos do extrato_prestador
  WITH fontes AS (
    SELECT t.quando AS ts,
           CASE t.tipo WHEN 'corrida' THEN 'tvde'
                       WHEN 'compensacao' THEN 'entrega'
                       ELSE CASE WHEN t.descricao LIKE 'Favor%' THEN 'favor_entrega' ELSE 'entrega' END END AS tipo,
           t.descricao,
           t.ganhou_cents AS valor_cents,
           0 AS tokens
      FROM public._prestador_trabalhos(v_uid, now() - interval '14 days') t
    UNION ALL
    SELECT b.created_at, 'tokens', 'Tokens da entrega/corrida', 0, b.amount
      FROM public.bora_tokens b
     WHERE b.user_id = v_uid AND b.role = 'driver' AND b.created_at > now() - interval '14 days'
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ts', to_char(ts AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
           'tipo', tipo, 'descricao', left(descricao, 60),
           'valor_cents', valor_cents, 'tokens', tokens) ORDER BY ts DESC),
         COALESCE(SUM(valor_cents) FILTER (WHERE ts >= v_dia_ini), 0),
         COALESCE(SUM(valor_cents) FILTER (WHERE ts >= v_sem_ini), 0),
         COALESCE(SUM(valor_cents) FILTER (WHERE ts >= v_semp_ini AND ts < v_sem_ini), 0),
         COALESCE(SUM(tokens) FILTER (WHERE ts >= v_dia_ini), 0)::int,
         COALESCE(SUM(tokens) FILTER (WHERE ts >= v_sem_ini), 0)::int,
         COALESCE(SUM(tokens) FILTER (WHERE ts >= v_semp_ini AND ts < v_sem_ini), 0)::int
    INTO v_itens, v_dia_total, v_sem_total, v_semp_total, v_dia_tokens, v_sem_tokens, v_semp_tokens
    FROM fontes;

  SELECT to_jsonb(s) INTO v_settle
    FROM public.driver_weekly_settlements s
   WHERE s.driver_id = v_uid
   ORDER BY s.week_start_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'dia',            jsonb_build_object('total_cents', v_dia_total,  'tokens', v_dia_tokens),
    'semana',         jsonb_build_object('total_cents', v_sem_total,  'tokens', v_sem_tokens),
    'semana_passada', jsonb_build_object('total_cents', v_semp_total, 'tokens', v_semp_tokens),
    'ultimo_acerto', v_settle,
    'itens', COALESCE(v_itens, '[]'::jsonb)
  );
END;
$$;

-- o talão real do Valdemir foi pago por MB Way a 19/09 (o carimbo anterior caía em 20/09 na hora de Lisboa)
UPDATE public.order_receipts_v2
   SET reimbursement_external_paid_at = '2026-09-19 12:00:00+01'
 WHERE id = 'b89e66d2-c815-4c72-b64d-94879c2cced6' AND reimbursement_method = 'mbway';
