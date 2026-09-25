-- 2026-09-20 — CONTAS CLARAS · Bloco 3 — EXTRATO DO PARCEIRO (uma RPC só).
--
-- Na linguagem do parceiro: pedido a pedido, quanto o cliente pagou, quanto era de produtos,
-- quanto fica para a loja, quanto é da Bora e SOBRE O QUÊ (nunca "comissão" solta), o que já
-- foi transferido e o que falta, com datas; a semana em curso pela fórmula oficial do fecho
-- (via partner_my_weekly_closeout, que já existe) e o estado da conta Stripe Connect.
--
-- Fonte por pedido: order_financials (base_amount / restaurant_amount / platform_amount),
-- escrita pelo gatilho do pedido entregue e pago — é a mesma linha que vai para o livro-razão
-- e para o fecho semanal (medido a 20/09: Goola, 4 pedidos, order_financials = ledger =
-- partner_store_share, ao cêntimo). Fallback quando ainda não há linha: partner_store_share().
--
-- Achado que isto corrige: o ecrã "Ganhos" do parceiro calculava em Dart
-- `subtotal − comissão visível` (12,72 − 1,27 = 11,45 €) quando a loja recebe 10,90 €
-- (order_financials). O Flutter deixa de fazer contas.

CREATE OR REPLACE FUNCTION public.extrato_parceiro(p_restaurant_id text, p_dias integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller   uuid := auth.uid();
  v_de       timestamptz;
  v_pedidos  jsonb;
  v_totais   jsonb;
  v_por_dia  jsonb;
  v_semanas  jsonb;
  v_transf   jsonb;
  v_por_tr   jsonb;
  v_semana   jsonb;
  v_stripe   jsonb;
  v_bate     jsonb;
  v_nome     text;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF NOT public.is_admin() AND NOT EXISTS (
      SELECT 1 FROM public.restaurants r
       WHERE r.id = p_restaurant_id AND COALESCE(r.user_id, r.user_) = v_caller) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  p_dias := LEAST(GREATEST(COALESCE(p_dias, 30), 1), 365);
  v_de := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon') - make_interval(days => p_dias - 1);
  SELECT r.name INTO v_nome FROM public.restaurants r WHERE r.id = p_restaurant_id;

  WITH p AS (
    SELECT o.id,
           COALESCE(o.delivered_at, o.status_updated_at, o.created_at) AS quando,
           o.customer_name, o.payment_method,
           (o.takeaway_pickup_code IS NOT NULL) AS takeaway,
           ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int AS cliente_pagou_cents,
           ROUND(COALESCE(f.base_amount, o.final_purchase_value, o.subtotal, 0) * 100)::int AS produtos_cents,
           ROUND(COALESCE(f.restaurant_amount,
                          public.partner_store_share(COALESCE(o.final_purchase_value, o.subtotal, 0)::numeric, o.restaurant_id::text)) * 100)::int AS parceiro_cents,
           (f.order_id IS NOT NULL) AS tem_linha_financeira,
           o.items
      FROM public.orders o
      LEFT JOIN public.order_financials f ON f.order_id::text = o.id
     WHERE o.restaurant_id = p_restaurant_id
       AND o.status = 'delivered'
       AND COALESCE(o.is_partner_store, false)
       AND COALESCE(o.is_test_order, false) = false
       AND COALESCE(o.delivered_at, o.status_updated_at, o.created_at) >= v_de
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'pedido_id', p.id, 'quando', p.quando,
           'quando_txt', to_char(p.quando AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
           'dia', to_char(p.quando AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD'),
           'cliente', p.customer_name, 'pagamento', p.payment_method, 'takeaway', p.takeaway,
           'cliente_pagou_cents', p.cliente_pagou_cents,
           'produtos_cents', p.produtos_cents,
           'entrega_e_taxas_cents', p.cliente_pagou_cents - p.produtos_cents,
           'fica_para_o_parceiro_cents', p.parceiro_cents,
           'parte_bora_cents', p.produtos_cents - p.parceiro_cents,
           'parte_bora_pct', CASE WHEN p.produtos_cents > 0 THEN ROUND((p.produtos_cents - p.parceiro_cents) * 100.0 / p.produtos_cents, 1) ELSE NULL END,
           'sobre_txt', 'sobre ' || replace((p.produtos_cents / 100.0)::numeric(12,2)::text, '.', ',') || ' € de produtos',
           'recebido_pelo_parceiro_cents', CASE WHEN p.payment_method = 'cash' AND p.takeaway THEN p.cliente_pagou_cents ELSE 0 END,
           'fonte', CASE WHEN p.tem_linha_financeira THEN 'order_financials' ELSE 'partner_store_share' END,
           'n_itens', CASE WHEN jsonb_typeof(p.items) = 'array' THEN jsonb_array_length(p.items) ELSE NULL END
         ) ORDER BY p.quando DESC), '[]'::jsonb),
         jsonb_build_object(
           'pedidos', COUNT(*),
           'cliente_pagou_cents', COALESCE(SUM(p.cliente_pagou_cents), 0),
           'produtos_cents', COALESCE(SUM(p.produtos_cents), 0),
           'entrega_e_taxas_cents', COALESCE(SUM(p.cliente_pagou_cents - p.produtos_cents), 0),
           'fica_para_o_parceiro_cents', COALESCE(SUM(p.parceiro_cents), 0),
           'parte_bora_cents', COALESCE(SUM(p.produtos_cents - p.parceiro_cents), 0),
           'recebido_pelo_parceiro_cents', COALESCE(SUM(CASE WHEN p.payment_method = 'cash' AND p.takeaway THEN p.cliente_pagou_cents ELSE 0 END), 0),
           'media_por_pedido_cents', CASE WHEN COUNT(*) > 0 THEN ROUND(SUM(p.parceiro_cents)::numeric / COUNT(*))::int ELSE NULL END),
         COALESCE((SELECT jsonb_agg(jsonb_build_object('dia', d.dia, 'pedidos', d.n, 'fica_para_o_parceiro_cents', d.c) ORDER BY d.dia)
                     FROM (SELECT to_char(quando AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD') AS dia, COUNT(*) AS n, SUM(parceiro_cents) AS c
                             FROM p GROUP BY 1) d), '[]'::jsonb)
    INTO v_pedidos, v_totais, v_por_dia
    FROM p;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'semana', to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '–' || to_char(s.week_end_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM'),
           'week_start', s.week_start_at, 'pedidos', s.total_orders,
           'vendas_cents', ROUND(s.gross_sales * 100)::int,
           'parte_bora_cents', ROUND(COALESCE(s.commission_total, 0) * 100)::int,
           'sobre_txt', 'sobre ' || replace(s.gross_sales::numeric(12,2)::text, '.', ',') || ' € de vendas',
           'fica_para_o_parceiro_cents', ROUND(COALESCE(s.partner_share, 0) * 100)::int,
           'recebido_pelo_parceiro_cents', ROUND(COALESCE(s.cash_kept_by_partner, 0) * 100)::int,
           'liquido_cents', ROUND(s.net_balance * 100)::int,
           'sentido', s.direction, 'estado', s.status,
           'pago_em', s.paid_at,
           'pago_em_txt', CASE WHEN s.paid_at IS NULL THEN NULL ELSE to_char(s.paid_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY') END,
           'referencia', s.payment_reference,
           'comprovativo', (SELECT jsonb_build_object('estado', sr.status, 'enviado_em', sr.sent_at, 'para', sr.to_email)
                              FROM public.settlement_receipts sr
                             WHERE sr.subject_type = 'partner' AND sr.subject_id = p_restaurant_id
                               AND sr.week_start_at = s.week_start_at
                             ORDER BY sr.created_at DESC LIMIT 1)
         ) ORDER BY s.week_start_at DESC), '[]'::jsonb),
         jsonb_build_object(
           'total_cents', COALESCE(SUM(ROUND(s.net_balance * 100)::int) FILTER (WHERE s.status IN ('paid','received') AND s.direction = 'bora_pays_partner'), 0),
           'ultimo_em', MAX(s.paid_at) FILTER (WHERE s.status IN ('paid','received')),
           'semanas', COUNT(*) FILTER (WHERE s.status IN ('paid','received'))),
         jsonb_build_object(
           'total_cents', COALESCE(SUM(ROUND(s.net_balance * 100)::int) FILTER (WHERE s.status NOT IN ('paid','received') AND s.direction = 'bora_pays_partner'), 0),
           'semanas', COUNT(*) FILTER (WHERE s.status NOT IN ('paid','received') AND s.direction = 'bora_pays_partner'),
           'a_entregar_a_bora_cents', COALESCE(SUM(-ROUND(s.net_balance * 100)::int) FILTER (WHERE s.status NOT IN ('paid','received') AND s.direction = 'partner_pays_bora'), 0))
    INTO v_semanas, v_transf, v_por_tr
    FROM (SELECT * FROM public.partner_weekly_settlements WHERE partner_id = p_restaurant_id ORDER BY week_start_at DESC LIMIT 12) s;

  BEGIN
    v_semana := (public.partner_my_weekly_closeout(p_restaurant_id))->'current_week';
  EXCEPTION WHEN OTHERS THEN
    v_semana := jsonb_build_object('erro', 'previsao_indisponivel', 'detalhe', SQLERRM);
  END;

  SELECT jsonb_build_object(
           'conta', r.stripe_account_id IS NOT NULL,
           'estado', r.stripe_account_status,
           'transferencias_activas', r.stripe_payouts_enabled,
           'iban_registado', NULLIF(trim(COALESCE(r.iban, '')), '') IS NOT NULL,
           'mbway', r.mbway_phone,
           'ultimo_evento', (SELECT jsonb_build_object('tipo', e.type, 'quando', e.received_at)
                               FROM public.stripe_connect_events e
                              WHERE e.account_id = r.stripe_account_id
                              ORDER BY e.received_at DESC LIMIT 1))
    INTO v_stripe
    FROM public.restaurants r WHERE r.id = p_restaurant_id;

  SELECT jsonb_build_object(
           'ledger_ganhos_cents', COALESCE((SELECT ROUND(SUM(l.amount) * 100)::int FROM public.ledger_entries l
                                             WHERE l.user_type = 'restaurant' AND l.type = 'earning' AND l.user_id = p_restaurant_id), 0),
           'order_financials_cents', COALESCE((SELECT ROUND(SUM(f.restaurant_amount) * 100)::int FROM public.order_financials f
                                                 JOIN public.orders o ON o.id = f.order_id::text
                                                WHERE o.restaurant_id = p_restaurant_id), 0),
           'acertos_cents', COALESCE((SELECT ROUND(SUM(s.partner_share) * 100)::int FROM public.partner_weekly_settlements s
                                        WHERE s.partner_id = p_restaurant_id), 0))
    INTO v_bate;
  v_bate := v_bate || jsonb_build_object('bate',
              (v_bate->>'ledger_ganhos_cents') = (v_bate->>'order_financials_cents'));

  RETURN jsonb_build_object(
    'ok', true,
    'gerado_em', now(),
    'loja', jsonb_build_object('id', p_restaurant_id, 'nome', v_nome),
    'periodo', jsonb_build_object('de', v_de, 'ate', now(), 'dias', p_dias),
    'totais', v_totais,
    'por_dia', v_por_dia,
    'pedidos', v_pedidos,
    'semanas', v_semanas,
    'transferido', v_transf,
    'por_transferir', v_por_tr,
    'semana_em_curso', v_semana,
    'stripe', v_stripe,
    'arcas', v_bate
  );
END;
$$;

REVOKE ALL ON FUNCTION public.extrato_parceiro(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extrato_parceiro(text, integer) TO authenticated;

COMMENT ON FUNCTION public.extrato_parceiro(text, integer) IS
  'Contas claras (20/09/2026): o extrato do parceiro — a única fonte do ecrã Ganhos do parceiro. Dono da loja ou admin.';
