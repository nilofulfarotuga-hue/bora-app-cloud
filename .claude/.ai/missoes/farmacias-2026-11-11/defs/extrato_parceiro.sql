CREATE OR REPLACE FUNCTION public.extrato_parceiro(p_restaurant_id text, p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  WITH base AS (
    SELECT o.id,
           COALESCE(o.delivered_at, o.status_updated_at, o.created_at) AS quando,
           o.customer_name, o.payment_method,
           (o.takeaway_pickup_code IS NOT NULL) AS takeaway,
           -- 10/11/2026 pagar-na-loja: o estafeta pagou a loja em mao na recolha
           ROUND(CASE WHEN public.pedido_loja_estado(o.is_partner_store, o.order_type, o.service_type, o.user_id, o.payment_method) = 'pagar_loja' AND COALESCE(o.is_purchase_finalized, false) THEN COALESCE(o.final_purchase_value, 0) ELSE 0 END * 100)::int AS pago_recolha_cents,
           ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int AS pago_real_cents,
           ROUND((COALESCE(o.delivery_fee, 0) + COALESCE(o.service_fee, 0)
                  + COALESCE(o.bag_fee, 0) + COALESCE(o.small_order_fee, 0)) * 100)::int AS taxas_cents,
           ROUND(COALESCE(f.restaurant_amount,
                          public.partner_store_share(COALESCE(CASE WHEN public.pedido_loja_estado(o.is_partner_store, o.order_type, o.service_type, o.user_id, o.payment_method) = 'pagar_loja' THEN NULL ELSE o.final_purchase_value END, o.subtotal, 0)::numeric, o.restaurant_id::text)) * 100)::int AS parceiro_cents,
           (f.order_id IS NOT NULL) AS tem_linha_financeira, public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) AS parceiro_chamou, COALESCE(o.partner_commission_visible, 0) AS comissao_pc,
           o.items
      FROM public.orders o
      LEFT JOIN public.order_financials f ON f.order_id::text = o.id
     WHERE o.restaurant_id = p_restaurant_id
       AND o.status = 'delivered'
       AND COALESCE(o.is_partner_store, false)
       AND COALESCE(o.is_test_order, false) = false
       AND COALESCE(o.delivered_at, o.status_updated_at, o.created_at) >= v_de
  ), p AS (
    SELECT b.*,
           CASE WHEN b.parceiro_chamou THEN ROUND((b.parceiro_cents / 100.0 + b.comissao_pc) * 100)::int ELSE ROUND(public._parceiro_vendas_loja(b.parceiro_cents / 100.0, p_restaurant_id) * 100)::int END AS produtos_cents
      FROM base b
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'pedido_id', p.id, 'quando', p.quando,
           'quando_txt', to_char(p.quando AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'),
           'dia', to_char(p.quando AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD'),
           'cliente', p.customer_name, 'pagamento', p.payment_method, 'takeaway', p.takeaway,
           'cliente_pagou_cents', p.produtos_cents + p.taxas_cents,
           'produtos_cents', p.produtos_cents,
           'entrega_e_taxas_cents', p.taxas_cents,
           'fica_para_o_parceiro_cents', p.parceiro_cents,
           'parte_bora_cents', p.produtos_cents - p.parceiro_cents,
           'parte_bora_pct', CASE WHEN p.produtos_cents > 0 THEN ROUND((p.produtos_cents - p.parceiro_cents) * 100.0 / p.produtos_cents, 1) ELSE NULL END,
           'sobre_txt', 'sobre ' || replace((p.produtos_cents / 100.0)::numeric(12,2)::text, '.', ',') || ' € de vendas',
           'recebido_pelo_parceiro_cents', CASE WHEN p.payment_method = 'cash' AND (p.takeaway OR p.parceiro_chamou) THEN p.pago_real_cents ELSE p.pago_recolha_cents END,
           'recebido_em_mao_na_recolha_cents', p.pago_recolha_cents,
           'fonte', CASE WHEN p.tem_linha_financeira THEN 'order_financials' ELSE 'partner_store_share' END,
           'n_itens', CASE WHEN jsonb_typeof(p.items) = 'array' THEN jsonb_array_length(p.items) ELSE NULL END
         ) ORDER BY p.quando DESC), '[]'::jsonb),
         jsonb_build_object(
           'pedidos', COUNT(*),
           'cliente_pagou_cents', COALESCE(SUM(p.produtos_cents + p.taxas_cents), 0),
           'produtos_cents', COALESCE(SUM(p.produtos_cents), 0),
           'entrega_e_taxas_cents', COALESCE(SUM(p.taxas_cents), 0),
           'fica_para_o_parceiro_cents', COALESCE(SUM(p.parceiro_cents), 0),
           'parte_bora_cents', COALESCE(SUM(p.produtos_cents - p.parceiro_cents), 0),
           'recebido_pelo_parceiro_cents', COALESCE(SUM(CASE WHEN p.payment_method = 'cash' AND (p.takeaway OR p.parceiro_chamou) THEN p.pago_real_cents ELSE p.pago_recolha_cents END), 0), 'recebido_em_mao_na_recolha_cents', COALESCE(SUM(p.pago_recolha_cents), 0),
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
           'vendas_cents', ROUND(public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at) * 100)::int,
           'parte_bora_cents', ROUND((public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at) - COALESCE(s.partner_share, 0)) * 100)::int,
           'sobre_txt', 'sobre ' || replace(public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at)::numeric(12,2)::text, '.', ',') || ' € de vendas',
           'fica_para_o_parceiro_cents', ROUND(COALESCE(s.partner_share, 0) * 100)::int,
           'recebido_pelo_parceiro_cents', ROUND(COALESCE(s.cash_kept_by_partner, 0) * 100)::int,
           'recebido_em_mao_na_recolha_cents', ROUND(COALESCE(s.pago_em_mao_na_recolha, 0) * 100)::int,
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
$function$
;
