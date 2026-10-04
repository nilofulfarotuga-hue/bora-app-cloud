-- Agente parceiro (ronda 04/10/2026) — A3, A4, C3
-- A3: o extrato do parceiro nunca mostra os 5 % ocultos. Vendas = ao preço da
--     loja (balcão); parte da Bora = comissão de 10 % (ou 0 quando a comissão é
--     paga pelo cliente: partner_commission_billing='client' ou app_markup_pct>0).
--     O que fica para a loja continua a vir de order_financials / partner_store_share
--     (a mesma fonte do ledger) — nada muda em dinheiro, só na apresentação.
-- A4: partner_loja_recebe(ids) devolve o que a loja recebe por pedido (cartão do pedido).
-- C3: partner_ganhos_resumo(loja) — hoje/semana/total com a MESMA fórmula do extrato
--     (só entregues, sem testes; cancelados/rejeitados/por aceitar não contam).

CREATE OR REPLACE FUNCTION public._parceiro_vendas_loja(p_fica numeric, p_restaurant_id text)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.restaurants r
                  WHERE r.id = p_restaurant_id
                    AND (COALESCE(r.app_markup_pct, 0) > 0
                         OR COALESCE(r.partner_commission_billing, 'partner') = 'client'))
      THEN ROUND(COALESCE(p_fica, 0), 2)
    ELSE ROUND(COALESCE(p_fica, 0)
               / NULLIF(1 - COALESCE((SELECT (value::text)::numeric FROM public.platform_settings
                                       WHERE key = 'partner_visible_commission_pct'), 0.10), 0), 2)
  END;
$fn$;
REVOKE ALL ON FUNCTION public._parceiro_vendas_loja(numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._parceiro_vendas_loja(numeric, text) TO authenticated, service_role;

-- O que a loja recebe por pedido (mesma expressão do extrato).
CREATE OR REPLACE FUNCTION public._parceiro_fica_pedido(p_order_id text)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT ROUND(COALESCE(f.restaurant_amount,
           public.partner_store_share(COALESCE(o.final_purchase_value, o.subtotal, 0)::numeric, o.restaurant_id::text)), 2)
    FROM public.orders o
    LEFT JOIN public.order_financials f ON f.order_id::text = o.id
   WHERE o.id = p_order_id;
$fn$;
REVOKE ALL ON FUNCTION public._parceiro_fica_pedido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._parceiro_fica_pedido(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.partner_loja_recebe(p_order_ids text[])
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(jsonb_object_agg(o.id, ROUND(public._parceiro_fica_pedido(o.id) * 100)::int), '{}'::jsonb)
    FROM public.orders o
   WHERE o.id = ANY (COALESCE(p_order_ids, '{}'::text[]))
     AND COALESCE(o.is_partner_store, false)
     AND (public.is_admin() OR o.restaurant_id IN (SELECT public.parceiro_minhas_lojas()));
$fn$;
REVOKE ALL ON FUNCTION public.partner_loja_recebe(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_loja_recebe(text[]) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.partner_ganhos_resumo(p_restaurant_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_hoje timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_semana timestamptz := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon') - interval '6 days';
  v jsonb;
BEGIN
  IF NOT public._parceiro_pode_loja(p_restaurant_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  WITH p AS (
    SELECT COALESCE(o.delivered_at, o.status_updated_at, o.created_at) AS quando,
           ROUND(COALESCE(f.restaurant_amount,
                 public.partner_store_share(COALESCE(o.final_purchase_value, o.subtotal, 0)::numeric, o.restaurant_id::text)) * 100)::int AS c
      FROM public.orders o
      LEFT JOIN public.order_financials f ON f.order_id::text = o.id
     WHERE o.restaurant_id = p_restaurant_id
       AND o.status = 'delivered'
       AND COALESCE(o.is_partner_store, false)
       AND COALESCE(o.is_test_order, false) = false
  )
  SELECT jsonb_build_object(
           'ok', true,
           'hoje_cents', COALESCE(SUM(c) FILTER (WHERE quando >= v_hoje), 0),
           'hoje_pedidos', COUNT(*) FILTER (WHERE quando >= v_hoje),
           'semana_cents', COALESCE(SUM(c) FILTER (WHERE quando >= v_semana), 0),
           'semana_pedidos', COUNT(*) FILTER (WHERE quando >= v_semana),
           'total_cents', COALESCE(SUM(c), 0),
           'total_pedidos', COUNT(*))
    INTO v FROM p;
  RETURN v;
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_ganhos_resumo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_ganhos_resumo(text) TO authenticated, service_role;

-- ── extrato_parceiro (versão do ar + vendas ao preço da loja) ──────────────
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
           ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int AS pago_real_cents,
           ROUND((COALESCE(o.delivery_fee, 0) + COALESCE(o.service_fee, 0)
                  + COALESCE(o.bag_fee, 0) + COALESCE(o.small_order_fee, 0)) * 100)::int AS taxas_cents,
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
  ), p AS (
    SELECT b.*,
           ROUND(public._parceiro_vendas_loja(b.parceiro_cents / 100.0, p_restaurant_id) * 100)::int AS produtos_cents
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
           'recebido_pelo_parceiro_cents', CASE WHEN p.payment_method = 'cash' AND p.takeaway THEN p.pago_real_cents ELSE 0 END,
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
           'recebido_pelo_parceiro_cents', COALESCE(SUM(CASE WHEN p.payment_method = 'cash' AND p.takeaway THEN p.pago_real_cents ELSE 0 END), 0),
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
           'vendas_cents', ROUND(public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id) * 100)::int,
           'parte_bora_cents', ROUND((public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id) - COALESCE(s.partner_share, 0)) * 100)::int,
           'sobre_txt', 'sobre ' || replace(public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id)::numeric(12,2)::text, '.', ',') || ' € de vendas',
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
$function$;

-- ── partner_my_weekly_closeout: vendas ao preço da loja ────────────────────
CREATE OR REPLACE FUNCTION public.partner_my_weekly_closeout(p_restaurant_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_current jsonb;
  v_history jsonb;
  v_share numeric;
  v_vendas numeric;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF NOT public._is_admin(v_caller) AND NOT EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = p_restaurant_id
        AND COALESCE(r.user_id, r.user_) = v_caller) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  v_current := public.compute_partner_weekly_settlement(p_restaurant_id, now(), false);
  IF v_current ? 'partner_share' THEN
    v_share := COALESCE((v_current->>'partner_share')::numeric, 0);
    v_vendas := public._parceiro_vendas_loja(v_share, p_restaurant_id);
    v_current := v_current || jsonb_build_object('gross_sales', v_vendas,
                                                 'commission_total', ROUND(v_vendas - v_share, 2));
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'week_start', s.week_start_at,
    'week_end', s.week_end_at,
    'total_orders', s.total_orders,
    'gross_sales', public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id),
    'commission_total', ROUND(public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id) - COALESCE(s.partner_share, 0), 2),
    'partner_share', s.partner_share,
    'cash_kept_by_partner', s.cash_kept_by_partner,
    'net_balance', s.net_balance,
    'direction', s.direction,
    'status', s.status,
    'paid_at', s.paid_at
  ) ORDER BY s.week_start_at DESC)
  INTO v_history
  FROM (SELECT * FROM public.partner_weekly_settlements
        WHERE partner_id = p_restaurant_id
        ORDER BY week_start_at DESC LIMIT 8) s;

  RETURN jsonb_build_object(
    'current_week', v_current,
    'history', COALESCE(v_history, '[]'::jsonb)
  );
END;
$function$;

-- ── partner_monthly_statement: vendas ao preço da loja ─────────────────────
CREATE OR REPLACE FUNCTION public.partner_monthly_statement(p_partner_id text, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini timestamptz; v_fim timestamptz; r record;
  v_linhas jsonb; v_tot jsonb; v_acertos jsonb; v_pago numeric; v_parte numeric;
BEGIN
  SELECT * INTO r FROM public.restaurants WHERE id = p_partner_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'parceiro_nao_encontrado'; END IF;
  IF NOT (public.is_admin()
          OR coalesce(auth.jwt()->>'role','') = 'service_role'
          OR (auth.uid() IS NOT NULL AND (r.user_id = auth.uid() OR r.user_::text = auth.uid()::text))) THEN
    RAISE EXCEPTION 'sem_permissao';
  END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);

  WITH f AS (
    SELECT x.*, public._parceiro_vendas_loja(x.custo, p_partner_id) AS vendas_loja
      FROM public._fecho_pedidos(v_ini, v_fim) x
     WHERE x.restaurant_id = p_partner_id AND x.is_partner
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_id', f.order_id,
           'numero', upper(left(f.order_id, 8)),
           'data', to_char(f.delivered_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI'),
           'subtotal', f.vendas_loja,
           'comissao', ROUND(f.vendas_loja - f.custo, 2),
           'recebeu', f.custo,
           'pagamento', f.payment_method) ORDER BY f.delivered_at), '[]'::jsonb),
         jsonb_build_object('pedidos', count(*), 'vendas', coalesce(sum(f.vendas_loja),0),
                            'comissao', coalesce(sum(ROUND(f.vendas_loja - f.custo, 2)),0),
                            'parte_loja', coalesce(sum(f.custo),0))
    INTO v_linhas, v_tot
    FROM f;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana', to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '–' ||
                     to_char(s.week_end_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM'),
           'pedidos', s.total_orders, 'valor', s.partner_share, 'saldo', s.net_balance,
           'sentido', s.direction, 'estado', s.status,
           'pago_em', to_char(s.paid_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY'))
           ORDER BY s.week_start_at), '[]'::jsonb),
         coalesce(sum(s.partner_share) FILTER (WHERE s.status = 'paid'), 0)
    INTO v_acertos, v_pago
    FROM public.partner_weekly_settlements s
   WHERE s.partner_id = p_partner_id AND s.week_end_at >= v_ini AND s.week_end_at < v_fim;

  v_parte := (v_tot->>'parte_loja')::numeric;
  RETURN jsonb_build_object(
    'parceiro', jsonb_build_object('id', r.id, 'nome', r.name, 'nif', r.nif, 'email', r.email),
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month,
                                  'nome', (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                                                 'agosto','setembro','outubro','novembro','dezembro'])[p_month]),
    'pedidos', v_linhas,
    'totais', v_tot,
    'acertos_semanais', v_acertos,
    'total_pago_no_mes', v_pago,
    'saldo', v_parte - v_pago,
    'gerado_em', now());
END;
$function$;
