-- 15/10/2026 — Parceiro chama estafeta (regras 2.4.1), parte 3: fecho da loja e da Bora.
-- A loja fica com o preco de balcao (subtotal) e o dinheiro todo do cliente fica com ela;
-- deve a Bora 10% + 5% + entrega, descontado no acerto semanal. Remendos so actuam
-- nestes pedidos (pedido_parceiro_chamou); copia das funcoes em bkp_fn_parceiro_chama_20261015.
CREATE OR REPLACE FUNCTION pg_temp._remendar(p_fn regprocedure, p_old text[], p_new text[], p_n int[])
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v text := pg_get_functiondef(p_fn); i int; n int;
BEGIN
  FOR i IN 1 .. array_length(p_old, 1) LOOP
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    IF n <> p_n[i] THEN
      RAISE EXCEPTION 'remendo % #%: achei % vezes, esperava %', p_fn, i, n, p_n[i];
    END IF;
    v := replace(v, p_old[i], p_new[i]);
  END LOOP;
  EXECUTE v;
END $f$;

SELECT pg_temp._remendar('public.post_order_to_ledger()'::regprocedure,
  ARRAY[
    'v_restaurant_earn := public.partner_store_share(v_base, NEW.restaurant_id::TEXT);',
    'v_platform_comm   := ROUND(v_base - v_restaurant_earn, 2);'
  ],
  ARRAY[
    'v_restaurant_earn := CASE WHEN public.pedido_parceiro_chamou(NEW.is_partner_store, NEW.order_type, NEW.user_id) THEN v_base ELSE public.partner_store_share(v_base, NEW.restaurant_id::TEXT) END;  -- [15/10] parceiro chama estafeta: loja fica com o balcao',
    'v_platform_comm   := CASE WHEN public.pedido_parceiro_chamou(NEW.is_partner_store, NEW.order_type, NEW.user_id) THEN ROUND(COALESCE(NEW.partner_commission_visible, 0), 2) ELSE ROUND(v_base - v_restaurant_earn, 2) END;'
  ],
  ARRAY[1, 1]);

SELECT pg_temp._remendar('public.apply_order_financial_split()'::regprocedure,
  ARRAY['v_restaurant := public.partner_store_share(v_base, NEW.restaurant_id::TEXT);'],
  ARRAY['IF public.pedido_parceiro_chamou(NEW.is_partner_store, NEW.order_type, NEW.user_id) THEN  -- [15/10] parceiro chama estafeta
    v_restaurant := v_base;
    v_base := ROUND(v_base + COALESCE(NEW.partner_commission_visible, 0), 2);
  ELSE
    v_restaurant := public.partner_store_share(v_base, NEW.restaurant_id::TEXT);
  END IF;'],
  ARRAY[1]);

SELECT pg_temp._remendar('public.compute_partner_weekly_settlement(text, timestamptz, boolean)'::regprocedure,
  ARRAY[
    'COALESCE(SUM(o.subtotal), 0),',
    'AND o.takeaway_picked_up_at IS NOT NULL'
  ],
  ARRAY[
    'COALESCE(SUM(COALESCE(o.subtotal, 0) + CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.partner_commission_visible, 0) ELSE 0 END), 0),',
    'AND (o.takeaway_picked_up_at IS NOT NULL OR public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id))'
  ],
  ARRAY[1, 1]);

SELECT pg_temp._remendar('public.partner_my_weekly_closeout(text)'::regprocedure,
  ARRAY[
    'public._parceiro_vendas_loja(v_share, p_restaurant_id)',
    'public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id)'
  ],
  ARRAY[
    'public._parceiro_vendas_semana(v_share, p_restaurant_id, (v_current->>''week_start'')::timestamptz, (v_current->>''week_end'')::timestamptz)',
    'public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at)'
  ],
  ARRAY[1, 2]);

SELECT pg_temp._remendar('public.extrato_parceiro(text, integer)'::regprocedure,
  ARRAY[
    '(f.order_id IS NOT NULL) AS tem_linha_financeira,',
    'ROUND(public._parceiro_vendas_loja(b.parceiro_cents / 100.0, p_restaurant_id) * 100)::int AS produtos_cents',
    'p.payment_method = ''cash'' AND p.takeaway THEN',
    'public._parceiro_vendas_loja(COALESCE(s.partner_share, 0), p_restaurant_id)'
  ],
  ARRAY[
    '(f.order_id IS NOT NULL) AS tem_linha_financeira, public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) AS parceiro_chamou, COALESCE(o.partner_commission_visible, 0) AS comissao_pc,',
    'CASE WHEN b.parceiro_chamou THEN ROUND((b.parceiro_cents / 100.0 + b.comissao_pc) * 100)::int ELSE ROUND(public._parceiro_vendas_loja(b.parceiro_cents / 100.0, p_restaurant_id) * 100)::int END AS produtos_cents',
    'p.payment_method = ''cash'' AND (p.takeaway OR p.parceiro_chamou) THEN',
    'public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at)'
  ],
  ARRAY[1, 1, 2, 3]);

SELECT pg_temp._remendar('public.partner_monthly_statement(text, integer, integer)'::regprocedure,
  ARRAY[
    'SELECT x.*, public._parceiro_vendas_loja(x.custo, p_partner_id) AS vendas_loja',
    'FROM public._fecho_pedidos(v_ini, v_fim) x'
  ],
  ARRAY[
    'SELECT x.*, CASE WHEN public.pedido_parceiro_chamou(o2.is_partner_store, o2.order_type, o2.user_id) THEN ROUND(x.custo + COALESCE(o2.partner_commission_visible, 0), 2) ELSE public._parceiro_vendas_loja(x.custo, p_partner_id) END AS vendas_loja',
    'FROM public._fecho_pedidos(v_ini, v_fim) x LEFT JOIN public.orders o2 ON o2.id = x.order_id'
  ],
  ARRAY[1, 1]);

SELECT pg_temp._remendar('public._fecho_pedidos(timestamptz, timestamptz)'::regprocedure,
  ARRAY[
    'THEN round(coalesce(c.subtotal,0),2) - c.v_custo',
    'THEN round(coalesce(c.cash_total_due, c.final_total, 0), 2) ELSE 0 END,'
  ],
  ARRAY[
    'THEN CASE WHEN public.pedido_parceiro_chamou(c.is_partner_store, c.order_type, c.user_id) THEN round(coalesce(c.partner_commission_visible,0),2) ELSE round(coalesce(c.subtotal,0),2) - c.v_custo END',
    'THEN CASE WHEN public.pedido_parceiro_chamou(c.is_partner_store, c.order_type, c.user_id) THEN 0 ELSE round(coalesce(c.cash_total_due, c.final_total, 0), 2) END ELSE 0 END,'
  ],
  ARRAY[1, 1]);

SELECT pg_temp._remendar('public.admin_partner_payout_summary(text, timestamptz, timestamptz)'::regprocedure,
  ARRAY[
    '  v_orders_net numeric;',
    'COALESCE(SUM(COALESCE(o.subtotal, 0)), 0),',
    '- public.partner_store_share(COALESCE(o.subtotal, 0), o.restaurant_id)), 0)',
    'INTO v_orders_count, v_orders_gross, v_orders_commission',
    'v_orders_net := v_orders_gross - v_orders_commission;',
    '''orders_net_eur'', v_orders_net,'
  ],
  ARRAY[
    '  v_orders_net numeric;
  v_orders_cash_kept numeric;',
    'COALESCE(SUM(COALESCE(o.subtotal, 0) + CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.partner_commission_visible, 0) ELSE 0 END), 0),',
    '- CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.subtotal, 0) - COALESCE(o.partner_commission_visible, 0) ELSE public.partner_store_share(COALESCE(o.subtotal, 0), o.restaurant_id) END), 0),
    COALESCE(SUM(CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.final_total, o.price, 0) ELSE 0 END), 0)',
    'INTO v_orders_count, v_orders_gross, v_orders_commission, v_orders_cash_kept',
    'v_orders_net := v_orders_gross - v_orders_commission - COALESCE(v_orders_cash_kept, 0);',
    '''orders_net_eur'', v_orders_net,
    ''orders_cash_kept_by_partner_eur'', COALESCE(v_orders_cash_kept, 0),'
  ],
  ARRAY[1, 1, 1, 1, 1, 1]);