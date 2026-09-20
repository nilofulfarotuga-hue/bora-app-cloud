-- 2026-09-20 — CONTAS CLARAS · Bloco 4 — EXTRATO DO DONO (painel admin, uma RPC só).
--
-- Responde, no dia e no mês: quanto entrou e por que meio (cartão, MB Way, dinheiro — e o
-- dinheiro entra nas mãos de quem entregou, não na conta da Bora: fica escrito assim),
-- quanto saiu (acertos pagos, reembolsos, talões pagos, créditos dados), quanto está retido
-- (o que a Bora deve e ainda não pagou; o que devem à Bora e ainda não entrou), a quem a
-- Bora deve e quem deve à Bora — com nome, valor, origem e a função que marca pago.
--
-- Só leitura. Só admin. Nada é calculado por fórmula de preço: tudo é o que as tabelas
-- registaram (orders, tvde_rides, cleaning/carwash_bookings, acertos, talões, carteiras,
-- ledger). Onde uma arca não tem o dado, a chave vem NULL (a app mostra "—").

CREATE OR REPLACE FUNCTION public.admin_extrato_dono(p_de date DEFAULT NULL, p_ate date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_de   timestamptz;
  v_ate  timestamptz;
  v_entradas jsonb;
  v_saidas   jsonb;
  v_deve     jsonb := '[]'::jsonb;
  v_devem    jsonb := '[]'::jsonb;
  v_retido   jsonb;
  v_arcas    jsonb;
  v_r        record;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_ADMIN');
  END IF;
  v_de  := (COALESCE(p_de,  (now() AT TIME ZONE 'Europe/Lisbon')::date)::timestamp) AT TIME ZONE 'Europe/Lisbon';
  v_ate := ((COALESCE(p_ate, (now() AT TIME ZONE 'Europe/Lisbon')::date) + 1)::timestamp) AT TIME ZONE 'Europe/Lisbon';

  -- ENTRADAS por meio: pedidos entregues, corridas terminadas, limpezas e lavagens concluídas
  WITH e AS (
    SELECT 'pedido' AS origem, o.payment_method AS meio, ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int AS cents,
           ROUND(COALESCE(o.platform_commission, 0) * 100)::int AS parte_bora_cents
      FROM public.orders o
     WHERE o.status = 'delivered' AND COALESCE(o.is_test_order, false) = false
       AND COALESCE(o.delivered_at, o.status_updated_at) >= v_de AND COALESCE(o.delivered_at, o.status_updated_at) < v_ate
    UNION ALL
    SELECT 'corrida', COALESCE(r.payment_method, 'cash'), COALESCE(r.final_fare_cents, 0), COALESCE(r.bora_cut_cents, 0)
      FROM public.tvde_rides r
     WHERE r.status = 'finalizada' AND r.updated_at >= v_de AND r.updated_at < v_ate
    UNION ALL
    SELECT 'limpeza', COALESCE(b.payment_method, 'cash'), COALESCE(b.total_cents, 0), COALESCE(b.bora_fee_cents, 0)
      FROM public.cleaning_bookings b
     WHERE b.status = 'completed' AND b.completed_at >= v_de AND b.completed_at < v_ate
    UNION ALL
    SELECT 'lavagem', COALESCE(b.payment_method, 'cash'), COALESCE(b.total_cents, 0), COALESCE(b.bora_fee_cents, 0)
      FROM public.carwash_bookings b
     WHERE b.status = 'completed' AND b.completed_at >= v_de AND b.completed_at < v_ate
  )
  SELECT jsonb_build_object(
           'total_cents', COALESCE(SUM(cents), 0),
           'online_cents', COALESCE(SUM(cents) FILTER (WHERE meio IN ('card', 'mbway')), 0),
           'dinheiro_em_mao_de_terceiros_cents', COALESCE(SUM(cents) FILTER (WHERE meio = 'cash'), 0),
           'parte_bora_registada_cents', COALESCE(SUM(parte_bora_cents), 0),
           'por_meio', COALESCE((SELECT jsonb_agg(jsonb_build_object('meio', m.meio, 'n', m.n, 'cents', m.c) ORDER BY m.c DESC)
                                   FROM (SELECT meio, COUNT(*) AS n, SUM(cents) AS c FROM e GROUP BY meio) m), '[]'::jsonb),
           'por_origem', COALESCE((SELECT jsonb_agg(jsonb_build_object('origem', g.origem, 'n', g.n, 'cents', g.c, 'parte_bora_cents', g.pb) ORDER BY g.c DESC)
                                     FROM (SELECT origem, COUNT(*) AS n, SUM(cents) AS c, SUM(parte_bora_cents) AS pb FROM e GROUP BY origem) g), '[]'::jsonb),
           'n', COUNT(*))
    INTO v_entradas
    FROM e;

  -- SAÍDAS no período: acertos pagos pela Bora, reembolsos, talões pagos, créditos dados
  WITH s AS (
    SELECT 'acerto_estafeta' AS tipo, d.name AS quem, ROUND(s.net_balance * 100)::int AS cents, s.paid_at AS quando, s.payment_method AS meio, s.payment_reference AS ref
      FROM public.driver_weekly_settlements s LEFT JOIN public.drivers d ON d.user_id = s.driver_id
     WHERE s.status IN ('paid','received') AND s.direction = 'bora_pays_driver' AND s.paid_at >= v_de AND s.paid_at < v_ate
    UNION ALL
    SELECT 'acerto_parceiro', r.name, ROUND(s.net_balance * 100)::int, s.paid_at, NULL, s.payment_reference
      FROM public.partner_weekly_settlements s LEFT JOIN public.restaurants r ON r.id = s.partner_id
     WHERE s.status IN ('paid','received') AND s.direction = 'bora_pays_partner' AND s.paid_at >= v_de AND s.paid_at < v_ate
    UNION ALL
    SELECT 'acerto_limpeza', COALESCE(u.email, s.cleaner_id::text), s.net_payout_cents, s.paid_at, s.payment_method, s.payment_reference
      FROM public.cleaner_weekly_settlements s LEFT JOIN public.cleaners c ON c.id = s.cleaner_id LEFT JOIN auth.users u ON u.id = c.user_id
     WHERE s.status IN ('paid','received') AND s.direction = 'bora_pays_cleaner' AND s.paid_at >= v_de AND s.paid_at < v_ate
    UNION ALL
    SELECT 'acerto_lavagem', COALESCE(u.email, s.washer_id::text), s.net_payout_cents, s.paid_at, s.payment_method, s.payment_reference
      FROM public.washer_weekly_settlements s LEFT JOIN public.washers w ON w.id = s.washer_id LEFT JOIN auth.users u ON u.id = w.user_id
     WHERE s.status IN ('paid','received') AND s.direction = 'bora_pays_washer' AND s.paid_at >= v_de AND s.paid_at < v_ate
    UNION ALL
    SELECT 'reembolso_cliente', COALESCE(o.customer_name, o.user_id::text), ROUND(COALESCE(o.refund_amount, 0) * 100)::int, o.refunded_at, o.refund_method, o.refund_id
      FROM public.orders o
     WHERE o.refund_status = 'refunded' AND o.refunded_at >= v_de AND o.refunded_at < v_ate AND COALESCE(o.refund_amount, 0) > 0
    UNION ALL
    SELECT 'talao_pago_' || rc.reimbursement_method, d.name, COALESCE(rc.reimbursement_amount_cents, rc.driver_typed_total_cents),
           COALESCE(rc.reimbursement_external_paid_at, rc.reimbursement_processed_at), rc.reimbursement_method, rc.reimbursement_external_reference
      FROM public.order_receipts_v2 rc JOIN public.orders o ON o.id = rc.order_id LEFT JOIN public.drivers d ON d.user_id::text = o.assigned_driver_id
     WHERE rc.reimbursement_status = 'admin_paid'
       AND COALESCE(rc.reimbursement_external_paid_at, rc.reimbursement_processed_at) >= v_de
       AND COALESCE(rc.reimbursement_external_paid_at, rc.reimbursement_processed_at) < v_ate
    UNION ALL
    SELECT 'credito_carteira', COALESCE(u.email, wt.user_id::text), wt.amount_cents, wt.created_at, wt.kind, wt.reason
      FROM public.wallet_transactions wt LEFT JOIN auth.users u ON u.id = wt.user_id
     WHERE wt.kind IN ('admin_grant', 'cashback', 'referral', 'forgive') AND wt.amount_cents > 0
       AND wt.created_at >= v_de AND wt.created_at < v_ate
  )
  SELECT jsonb_build_object(
           'total_cents', COALESCE(SUM(cents), 0),
           'n', COUNT(*),
           'linhas', COALESCE(jsonb_agg(jsonb_build_object('tipo', tipo, 'quem', quem, 'cents', cents, 'quando', quando,
                       'quando_txt', to_char(quando AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'), 'meio', meio, 'ref', ref) ORDER BY quando DESC), '[]'::jsonb))
    INTO v_saidas
    FROM s;

  -- A QUEM A BORA DEVE (hoje, independentemente do período) — com o botão certo
  FOR v_r IN
    SELECT 'acerto_estafeta' AS tipo, s.driver_id::text AS quem_id, d.name AS quem, ROUND(s.net_balance * 100)::int AS cents,
           'Acerto da semana ' || to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') AS motivo, s.id::text AS ref,
           jsonb_build_object('rpc', 'admin_marcar_acerto_pago', 'p_user_id', s.driver_id, 'p_semana', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date) AS accao
      FROM public.driver_weekly_settlements s LEFT JOIN public.drivers d ON d.user_id = s.driver_id
     WHERE s.status NOT IN ('paid','received') AND s.direction = 'bora_pays_driver' AND s.net_balance > 0
    UNION ALL
    SELECT 'acerto_parceiro', s.partner_id, r.name, ROUND(s.net_balance * 100)::int,
           'Acerto da semana ' || to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM'), s.id::text,
           jsonb_build_object('rpc', 'admin_set_partner_settlement_status', 'p_settlement_id', s.id, 'p_new_status', 'paid')
      FROM public.partner_weekly_settlements s LEFT JOIN public.restaurants r ON r.id = s.partner_id
     WHERE s.status NOT IN ('paid','received') AND s.direction = 'bora_pays_partner' AND s.net_balance > 0
    UNION ALL
    SELECT 'tvde', b.driver_id::text, d.name, -ROUND(b.balance * 100)::int,
           'Corridas TVDE pagas na app (fora do acerto semanal)', NULL, NULL
      FROM public.tvde_driver_balances b LEFT JOIN public.drivers d ON d.user_id = b.driver_id OR d.id = b.driver_id
     WHERE b.balance < 0
    UNION ALL
    SELECT 'talao', o.assigned_driver_id, d.name, rc.driver_typed_total_cents,
           'Talão por reembolsar (pedido ' || left(rc.order_id, 8) || ')', rc.id::text,
           jsonb_build_object('rpc', 'admin_mark_receipt_paid | admin_mark_receipt_paid_external', 'p_receipt_id', rc.id)
      FROM public.order_receipts_v2 rc JOIN public.orders o ON o.id = rc.order_id LEFT JOIN public.drivers d ON d.user_id::text = o.assigned_driver_id
     WHERE rc.reimbursement_status = 'pending_admin'
    UNION ALL
    SELECT 'carteira_cliente', w.user_id::text, COALESCE(u.email, w.user_id::text), w.free_balance_cents,
           'Saldo livre na carteira (crédito que pode gastar na app)', NULL, NULL
      FROM public.client_wallets w LEFT JOIN auth.users u ON u.id = w.user_id
     WHERE w.free_balance_cents > 0
  LOOP
    v_deve := v_deve || jsonb_build_object('tipo', v_r.tipo, 'quem_id', v_r.quem_id, 'quem', v_r.quem, 'cents', v_r.cents,
                                           'motivo', v_r.motivo, 'ref', v_r.ref, 'accao', v_r.accao);
  END LOOP;

  -- QUEM DEVE À BORA (hoje)
  FOR v_r IN
    SELECT 'acerto_estafeta' AS tipo, s.driver_id::text AS quem_id, d.name AS quem, -ROUND(s.net_balance * 100)::int AS cents,
           'Acerto da semana ' || to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' (ficou com dinheiro da Bora)' AS motivo, s.id::text AS ref,
           jsonb_build_object('rpc', 'admin_marcar_acerto_pago', 'p_user_id', s.driver_id, 'p_semana', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date) AS accao
      FROM public.driver_weekly_settlements s LEFT JOIN public.drivers d ON d.user_id = s.driver_id
     WHERE s.status NOT IN ('paid','received') AND s.direction = 'driver_pays_bora' AND s.net_balance < 0
    UNION ALL
    SELECT 'acerto_parceiro', s.partner_id, r.name, -ROUND(s.net_balance * 100)::int,
           'Acerto da semana ' || to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' (recebeu em dinheiro)', s.id::text,
           jsonb_build_object('rpc', 'admin_set_partner_settlement_status', 'p_settlement_id', s.id, 'p_new_status', 'received')
      FROM public.partner_weekly_settlements s LEFT JOIN public.restaurants r ON r.id = s.partner_id
     WHERE s.status NOT IN ('paid','received') AND s.direction = 'partner_pays_bora' AND s.net_balance < 0
    UNION ALL
    SELECT 'tvde', b.driver_id::text, d.name, ROUND(b.balance * 100)::int,
           'Parte da Bora nas corridas a dinheiro (fora do acerto semanal)', NULL, NULL
      FROM public.tvde_driver_balances b LEFT JOIN public.drivers d ON d.user_id = b.driver_id OR d.id = b.driver_id
     WHERE b.balance > 0
    UNION ALL
    SELECT 'carteira_cliente', w.user_id::text, COALESCE(u.email, w.user_id::text), -w.free_balance_cents,
           'Carteira em negativo (taxa de cancelamento por pagar)', NULL,
           jsonb_build_object('rpc', 'admin_forgive_wallet_debt | wallet_settle_debt', 'p_user_id', w.user_id)
      FROM public.client_wallets w LEFT JOIN auth.users u ON u.id = w.user_id
     WHERE w.free_balance_cents < 0
  LOOP
    v_devem := v_devem || jsonb_build_object('tipo', v_r.tipo, 'quem_id', v_r.quem_id, 'quem', v_r.quem, 'cents', v_r.cents,
                                             'motivo', v_r.motivo, 'ref', v_r.ref, 'accao', v_r.accao);
  END LOOP;

  SELECT jsonb_build_object(
           'bora_deve_cents', COALESCE((SELECT SUM((x->>'cents')::int) FROM jsonb_array_elements(v_deve) x), 0),
           'devem_a_bora_cents', COALESCE((SELECT SUM((x->>'cents')::int) FROM jsonb_array_elements(v_devem) x), 0))
    INTO v_retido;

  -- as arcas, hoje (para o dono ver se batem)
  SELECT jsonb_build_object(
           'carteiras_saldo_cents', (SELECT COALESCE(SUM(free_balance_cents), 0) FROM public.client_wallets),
           'carteiras_historico_cents', (SELECT COALESCE(SUM(amount_cents), 0) FROM public.wallet_transactions WHERE kind <> ALL (public.wallet_kinds_fora_do_saldo())),
           'estafetas_saldo_cents', (SELECT COALESCE(ROUND(SUM(balance) * 100), 0)::int FROM public.driver_balances),
           'tvde_saldo_cents', (SELECT COALESCE(ROUND(SUM(balance) * 100), 0)::int FROM public.tvde_driver_balances),
           'ledger_comissao_cents', (SELECT COALESCE(ROUND(SUM(amount) * 100), 0)::int FROM public.ledger_entries WHERE user_type = 'platform'),
           'achados_abertos', (SELECT COUNT(*) FROM public.payment_reconciliation_findings WHERE resolved_at IS NULL))
    INTO v_arcas;

  RETURN jsonb_build_object(
    'ok', true,
    'gerado_em', now(),
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate),
    'entradas', v_entradas,
    'saidas', v_saidas,
    'retido', v_retido,
    'bora_deve', v_deve,
    'devem_a_bora', v_devem,
    'arcas', v_arcas
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_extrato_dono(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_extrato_dono(date, date) TO authenticated;

COMMENT ON FUNCTION public.admin_extrato_dono(date, date) IS
  'Contas claras (20/09/2026): a folha do dono — entradas por meio, saídas, retido, a quem a Bora deve e quem deve à Bora, com a função que marca pago. Só admin, só leitura.';
