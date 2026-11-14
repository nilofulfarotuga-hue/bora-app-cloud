-- Aplicado pela Claude.ai a 14/11/2026 (AUTORIZO do Danilo 13/11 e 14/11 11:44/11:48). Fonte: .claude/.ai/missoes/farmacias-loja-2026-11-14/bloco1-proposta-dinheiro.md
-- 1) Quem é farmácia parceira e qual a comissão extra em vigor numa data
CREATE OR REPLACE FUNCTION public._e_farmacia_parceira(p_restaurant_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.restaurants r
                  WHERE r.id = p_restaurant_id
                    AND r.category = 'pharmacy'
                    AND COALESCE(r.is_partner, false));
$function$;

CREATE OR REPLACE FUNCTION public._comissao_extra_pct(p_restaurant_id text, p_em timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- % extra (ex.: 0,10) só a partir de partner_extra_commission_starts_at; antes, ou sem data, 0.
  SELECT COALESCE((SELECT r.partner_extra_commission_pct
                     FROM public.restaurants r
                    WHERE r.id = p_restaurant_id
                      AND r.partner_extra_commission_pct IS NOT NULL
                      AND r.partner_extra_commission_starts_at IS NOT NULL
                      AND p_em >= r.partner_extra_commission_starts_at), 0);
$function$;

REVOKE ALL ON FUNCTION public._e_farmacia_parceira(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._comissao_extra_pct(text, timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._e_farmacia_parceira(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._comissao_extra_pct(text, timestamp with time zone) TO authenticated, service_role;

-- 2) A parte da loja: farmácia parceira fica com 100 % do subtotal
CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- 14/11/2026 farmácias: preço ao cliente = preço da Glovo e a farmácia recebe tudo (sem markup oculto).
    WHEN public._e_farmacia_parceira(p_restaurant_id)
      THEN ROUND(p_subtotal, 2)
    WHEN COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    ELSE public.partner_store_share(p_subtotal)
  END;
$function$;

-- 3) Inverso usado nos extratos: na farmácia, vendas = o que fica para a loja
CREATE OR REPLACE FUNCTION public._parceiro_vendas_loja(p_fica numeric, p_restaurant_id text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.restaurants r
                  WHERE r.id = p_restaurant_id
                    AND (COALESCE(r.app_markup_pct, 0) > 0
                         OR COALESCE(r.partner_commission_billing, 'partner') = 'client'
                         OR (r.category = 'pharmacy' AND COALESCE(r.is_partner, false))))
      THEN ROUND(COALESCE(p_fica, 0), 2)
    ELSE ROUND(COALESCE(p_fica, 0)
               / NULLIF(1 - COALESCE((SELECT (value::text)::numeric FROM public.platform_settings
                                       WHERE key = 'partner_visible_commission_pct'), 0.10), 0), 2)
  END;
$function$;

CREATE OR REPLACE FUNCTION public._parceiro_vendas_semana(p_share numeric, p_restaurant_id text, p_ini timestamp with time zone, p_fim timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- 14/11/2026 farmácias: o fecho guarda a parte já sem os 10 %; as vendas são a soma dos produtos.
    WHEN public._e_farmacia_parceira(p_restaurant_id) THEN
      (SELECT ROUND(COALESCE(SUM(COALESCE(o.subtotal, 0)), 0), 2)
         FROM public.orders o
        WHERE o.restaurant_id = p_restaurant_id
          AND o.status = 'delivered'
          AND o.delivered_at >= p_ini AND o.delivered_at <= p_fim)
    ELSE
      (SELECT ROUND(public._parceiro_vendas_loja(COALESCE(p_share, 0) - COALESCE(x.parte, 0), p_restaurant_id)
                    + COALESCE(x.vendas, 0), 2)
         FROM (SELECT SUM(COALESCE(o.subtotal, 0)) AS parte,
                      SUM(COALESCE(o.subtotal, 0) + COALESCE(o.partner_commission_visible, 0)) AS vendas
                 FROM public.orders o
                WHERE o.restaurant_id = p_restaurant_id
                  AND o.status = 'delivered'
                  AND public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id)
                  AND o.delivered_at >= p_ini AND o.delivered_at <= p_fim) x)
  END;
$function$;

-- 4) Preço ao cliente na farmácia
CREATE OR REPLACE FUNCTION public.pricing_calculate_loja(p_service_type text, p_subtotal numeric, p_distance_km numeric, p_is_partner_store boolean, p_apartment_delivery boolean, p_is_stacked_partner boolean, p_bag_count integer, p_restaurant_id text)
 RETURNS TABLE(delivery_fee numeric, service_fee numeric, platform_commission numeric, driver_earnings numeric, customer_total numeric, partner_markup_hidden numeric, bag_fee numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  r RECORD;
  s jsonb;
  v_sub NUMERIC;
  v_apt NUMERIC := 0;
  v_apt_driver NUMERIC := 0;
  v_poupado NUMERIC;
  v_fixo NUMERIC;
  v_liquido NUMERIC;
  v_min_parceiro INTEGER;
BEGIN
  SELECT * INTO r FROM public.pricing_calculate(p_service_type, p_subtotal, p_distance_km,
    p_is_partner_store, p_apartment_delivery, p_is_stacked_partner, COALESCE(p_bag_count, 0));

  v_sub := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));

  IF NOT COALESCE(p_is_partner_store, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND p_restaurant_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.restaurants x
                  WHERE x.id = p_restaurant_id
                    AND x.free_delivery_min_cents IS NOT NULL
                    AND NOT COALESCE(x.is_partner, false)
                    AND ROUND(v_sub * 100) >= x.free_delivery_min_cents) THEN
    SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
    IF p_apartment_delivery THEN
      v_apt        := ((s->>'apartment_surcharge_total_cents')::NUMERIC) / 100.0;
      v_apt_driver := ((s->>'apartment_driver_share_cents')::NUMERIC) / 100.0;
    END IF;
    -- só a taxa base (primeiros 4 km) é grátis; km extra e suplemento de apartamento pagam-se
    v_poupado := LEAST(GREATEST(0, r.delivery_fee - COALESCE(v_apt, 0)),
                       COALESCE(((s->>'delivery_base_fee_cents')::NUMERIC) / 100.0, 0));
    v_fixo := ROUND(((s->>'driver_base_fee_cents')::NUMERIC) / 100.0
                  + CASE WHEN p_service_type = 'storeShopping'
                         THEN ((s->>'driver_surcharge_cents')::NUMERIC) / 100.0 ELSE 0 END
                  + ((s->>'driver_per_km_cents')::NUMERIC) / 100.0 * GREATEST(1.0, COALESCE(p_distance_km, 1.0))
                  + COALESCE(v_apt_driver, 0), 2);
    v_liquido := GREATEST(0, ROUND(v_sub * (s->>'non_partner_markup_pct')::NUMERIC, 2)
                           + (r.delivery_fee - v_poupado) + r.service_fee - v_fixo);
    r.driver_earnings := ROUND(v_fixo + ROUND(v_liquido * (s->>'driver_profit_share_pct')::NUMERIC, 2), 2);
    r.delivery_fee    := ROUND(r.delivery_fee - v_poupado, 2);
    r.customer_total  := ROUND(r.customer_total - v_poupado, 2);
  END IF;

  -- 28/10/2026: loja PARCEIRA com entrega grátis a partir de um valor — só a taxa base sai.
  IF COALESCE(p_is_partner_store, false)
     AND NOT COALESCE(p_is_stacked_partner, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND p_restaurant_id IS NOT NULL THEN
    SELECT x.free_delivery_min_cents INTO v_min_parceiro
      FROM public.restaurants x
     WHERE x.id = p_restaurant_id AND COALESCE(x.is_partner, false);
    IF v_min_parceiro IS NOT NULL AND ROUND(v_sub * 100) >= v_min_parceiro THEN
      SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
      v_poupado := LEAST(GREATEST(r.delivery_fee, 0),
                         COALESCE(((s->>'delivery_base_fee_cents')::NUMERIC) / 100.0, 0));
      r.delivery_fee   := ROUND(r.delivery_fee - v_poupado, 2);
      r.customer_total := ROUND(r.customer_total - v_poupado, 2);
    END IF;
  END IF;

  -- 14/11/2026 farmácias parceiras (AUTORIZO do Danilo 13/11 e 14/11 11:44/11:48): o preço dos produtos é o da
  -- Glovo e vai todo para a farmácia (sem markup oculto nem comissão no pedido). O cliente paga subtotal + taxa
  -- de serviço (pharmacy_service_fee_fixed_cents + client_service_fee_pct do subtotal, numa linha só) + entrega
  -- (a mesma de sempre). Sem saco. A taxa de pedido pequeno soma-se à parte (small_order_fee_calc).
  IF COALESCE(p_is_partner_store, false)
     AND p_service_type IN ('restaurant', 'storeShopping')
     AND public._e_farmacia_parceira(p_restaurant_id) THEN
    SELECT jsonb_object_agg(key, value) INTO s FROM public.platform_settings;
    r.service_fee := ROUND(COALESCE((s->>'pharmacy_service_fee_fixed_cents')::NUMERIC, 0) / 100.0
                           + v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
    r.partner_markup_hidden := 0;
    r.platform_commission := CASE WHEN COALESCE(p_apartment_delivery, false)
                                  THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                  ELSE 0 END;
    r.bag_fee := 0;
    r.customer_total := ROUND(v_sub + r.service_fee + r.delivery_fee + r.bag_fee, 2);
  END IF;

  RETURN QUERY SELECT r.delivery_fee, r.service_fee, r.platform_commission, r.driver_earnings,
                      r.customer_total, r.partner_markup_hidden, r.bag_fee;
END;
$function$;

-- 5) Taxa de pedido pequeno: as lojas parceiras continuam a 0, menos as farmácias
CREATE OR REPLACE FUNCTION public.small_order_fee_calc(p_service_type text, p_subtotal numeric, p_restaurant_id text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_enabled   BOOLEAN;
  v_min_cents INTEGER;
  v_fee_cents INTEGER;
BEGIN
  SELECT COALESCE((value::text)::BOOLEAN, false) INTO v_enabled
    FROM public.platform_settings WHERE key = 'small_order_fee_enabled';
  IF COALESCE(v_enabled, false) IS NOT TRUE THEN
    RETURN 0;
  END IF;

  IF p_service_type IS NULL OR p_service_type NOT IN ('restaurant','storeShopping') THEN
    RETURN 0;
  END IF;
  IF p_subtotal IS NULL OR p_subtotal <= 0 THEN
    RETURN 0;
  END IF;

  -- 2026-09-22 (regra do Danilo): loja PARCEIRA nao leva taxa de pedido pequeno.
  -- 14/11/2026 (AUTORIZO do Danilo): as farmácias parceiras levam (min_order_cents / small_order_fee_cents,
  -- com o override por loja).
  IF p_restaurant_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.restaurants r
        WHERE r.id = p_restaurant_id AND COALESCE(r.is_partner, false)
          AND COALESCE(r.category, '') <> 'pharmacy'
     ) THEN
    RETURN 0;
  END IF;

  SELECT (value::text)::INTEGER INTO v_min_cents
    FROM public.platform_settings WHERE key = 'min_order_cents';
  SELECT (value::text)::INTEGER INTO v_fee_cents
    FROM public.platform_settings WHERE key = 'small_order_fee_cents';

  IF p_restaurant_id IS NOT NULL THEN
    SELECT COALESCE(r.min_order_cents_override,       v_min_cents),
           COALESCE(r.small_order_fee_cents_override, v_fee_cents)
      INTO v_min_cents, v_fee_cents
      FROM public.restaurants r WHERE r.id = p_restaurant_id;
  END IF;

  IF v_min_cents IS NULL OR v_fee_cents IS NULL
     OR v_min_cents <= 0 OR v_fee_cents <= 0 THEN
    RETURN 0;
  END IF;

  IF ROUND(p_subtotal * 100)::INTEGER >= v_min_cents THEN
    RETURN 0;
  END IF;

  RETURN ROUND(v_fee_cents / 100.0, 2);
END;
$function$;

-- 6) Editar pedido: recalcula com o preço da loja (a farmácia tem a sua taxa de serviço)
CREATE OR REPLACE FUNCTION public._order_edit_money(p_order_id text, p_new_subtotal numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o        public.orders%ROWTYPE;
  pc       RECORD;
  v_sub    numeric := ROUND(p_new_subtotal, 2);
  v_pct    numeric;
  v_rate   numeric;
  v_share0 numeric; v_share1 numeric; v_markup numeric; v_comm numeric;
  v_small  numeric; v_small_in_total boolean; v_delta numeric;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_sub <= 0 THEN RAISE EXCEPTION 'SUBTOTAL_ZERO: usa cancelar o pedido'; END IF;
  -- 14/11/2026: pricing_calculate_loja (com a loja) em vez de pricing_calculate — igual para as outras lojas
  -- (só muda entrega/total, que aqui não se usam) e dá a taxa de serviço própria das farmácias.
  SELECT * INTO pc FROM public.pricing_calculate_loja(
    o.service_type, v_sub, o.distance_km, true,
    COALESCE(o.apartment_delivery, false), false, COALESCE(o.bag_count, 0), o.restaurant_id::text);
  SELECT app_markup_pct INTO v_pct FROM public.restaurants WHERE id = o.restaurant_id;
  v_markup := pc.partner_markup_hidden;
  v_comm   := pc.platform_commission;
  IF COALESCE(v_pct, 0) > 0 THEN
    v_rate   := COALESCE((SELECT (value::text)::numeric FROM public.platform_settings
                           WHERE key = 'partner_hidden_markup_pct'), 0.05);
    v_share0 := public.partner_store_share(v_sub);
    v_share1 := public.partner_store_share(v_sub, o.restaurant_id);
    v_markup := ROUND(v_share1 * v_rate, 2);
    v_comm   := pc.platform_commission + (v_share0 - v_share1) + (pc.partner_markup_hidden - v_markup);
  END IF;
  v_small := COALESCE(public.small_order_fee_calc(o.service_type, v_sub, o.restaurant_id), 0);
  v_small_in_total := ABS(COALESCE(o.price, 0)
      - (COALESCE(o.subtotal,0) + COALESCE(o.service_fee,0) + COALESCE(o.delivery_fee,0)
         + COALESCE(o.bag_fee,0) + COALESCE(o.small_order_fee,0))) < 0.005;
  IF NOT v_small_in_total THEN v_small := COALESCE(o.small_order_fee, 0); END IF;
  v_delta := ROUND((v_sub - COALESCE(o.subtotal, 0))
                 + (pc.service_fee - COALESCE(o.service_fee, 0))
                 + (v_small - COALESCE(o.small_order_fee, 0)), 2);
  RETURN jsonb_build_object(
    'subtotal', v_sub,
    'service_fee', pc.service_fee,
    'partner_service_fee_client', pc.service_fee,
    'partner_markup_hidden', v_markup,
    'partner_commission_visible', ROUND(v_comm, 2),
    'platform_commission', ROUND(v_comm, 2),
    'small_order_fee', v_small,
    'delta_total', v_delta,
    'total_antes', ROUND(COALESCE(o.final_total, o.price, 0), 2),
    'total_depois', ROUND(COALESCE(o.final_total, o.price, 0) + v_delta, 2),
    'loja_recebe_depois', public.partner_store_share(v_sub, o.restaurant_id));
END $function$;

-- 7) Fecho semanal do parceiro: comissão extra (migração 05 de 11/11 refeita sobre o fecho de 10/11)
ALTER TABLE public.partner_weekly_settlements
  ADD COLUMN IF NOT EXISTS comissao_extra numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comissao_extra_receitas numeric NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.compute_partner_weekly_settlement(p_partner_id text, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_bounds record;
  v_total_orders int := 0;
  v_gross numeric := 0;
  v_share numeric := 0;
  v_cash_partner numeric := 0;
  v_pago_recolha numeric := 0; -- 10/11/2026 pagar-na-loja: estafeta pagou a loja em mao na recolha
  v_commission numeric := 0;
  v_net numeric := 0;
  v_deposit numeric := 0;   -- 09/11/2026 Volta
  v_extra numeric := 0;     -- 14/11/2026 farmacias: comissao extra das vendas na app depois da data de inicio
  v_receitas numeric := 0;  -- 14/11/2026 farmacias: valor dos medicamentos das receitas/pedidos especiais entregues
  v_extra_receitas numeric := 0;
  v_direction text;
  v_id uuid;
BEGIN
  IF v_caller IS NOT NULL AND NOT public._is_admin(v_caller) THEN
    IF NOT EXISTS (SELECT 1 FROM public.restaurants r
                    WHERE r.id = p_partner_id
                      AND COALESCE(r.user_id, r.user_) = v_caller) THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT
    COUNT(*),
    COALESCE(SUM(COALESCE(o.subtotal, 0) + CASE WHEN public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id) THEN COALESCE(o.partner_commission_visible, 0) ELSE 0 END), 0),
    COALESCE(SUM(ls.share), 0),
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND (o.takeaway_picked_up_at IS NOT NULL OR public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id))
                  THEN COALESCE(o.final_total, o.total, o.price, 0)
                  ELSE 0 END), 0),
    -- 10/11/2026 pagar-na-loja: pedido de app a dinheiro em loja parceira em que o estafeta
    -- pagou a loja na recolha. A loja ja recebeu este valor em mao.
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND COALESCE(o.is_partner_store, false)
                       AND COALESCE(o.is_purchase_finalized, false)
                       AND o.takeaway_picked_up_at IS NULL
                       AND NOT public.pedido_parceiro_chamou(o.is_partner_store, o.order_type, o.user_id)
                  THEN COALESCE(o.final_purchase_value, 0)
                  ELSE 0 END), 0),
    -- 14/11/2026 farmacias (AUTORIZO do Danilo): comissao extra (ex.: 10 %) sobre a parte da loja, so nos
    -- pedidos criados a partir de restaurants.partner_extra_commission_starts_at. Lojas sem % ou sem data: 0.
    COALESCE(ROUND(SUM(COALESCE(ls.share, 0) * public._comissao_extra_pct(o.restaurant_id, o.created_at)), 2), 0)
  INTO v_total_orders, v_gross, v_share, v_cash_partner, v_pago_recolha, v_extra
  FROM public.orders o
  LEFT JOIN LATERAL (
    SELECT SUM(le.amount) AS share
    FROM public.ledger_entries le
    WHERE le.order_id::text = o.id
      AND le.user_type = 'restaurant'
      AND le.type = 'earning'
  ) ls ON true
  WHERE o.restaurant_id = p_partner_id
    AND o.status = 'delivered'
    AND o.delivered_at >= v_bounds.week_start
    AND o.delivered_at <= v_bounds.week_end;

  v_cash_partner := ROUND(v_cash_partner + v_pago_recolha, 2);
  -- A comissao extra sai da parte da loja (a loja ja recebeu ou vai receber 100 %; fica a dever a diferenca).
  v_share := ROUND(v_share - v_extra, 2);
  v_commission := ROUND(v_gross - v_share, 2);

  -- 14/11/2026 farmacias: receitas e pedidos especiais (Favor) entregues na semana. O estafeta paga os
  -- medicamentos na farmacia (a farmacia ja recebeu); depois da data de inicio a farmacia deve os 10 %.
  SELECT COALESCE(ROUND(SUM(COALESCE(pp.valor_medicamentos_cents, 0)) / 100.0, 2), 0),
         COALESCE(ROUND(SUM(COALESCE(pp.valor_medicamentos_cents, 0) / 100.0
                            * public._comissao_extra_pct(pp.restaurant_id, pp.created_at)), 2), 0)
    INTO v_receitas, v_extra_receitas
    FROM public.pedidos_prescricao pp
   WHERE pp.restaurant_id = p_partner_id
     AND pp.estado = 'entregue'
     AND NOT COALESCE(pp.is_demo, false)
     AND pp.entregue_em >= v_bounds.week_start
     AND pp.entregue_em <= v_bounds.week_end;
  v_commission := ROUND(v_commission + v_extra_receitas, 2);

  -- 09/11/2026 Volta: depositos dos pedidos da semana, 100 % do parceiro, a parte da comissao.
  SELECT COALESCE(SUM(le.amount), 0) INTO v_deposit
    FROM public.ledger_entries le
    JOIN public.orders o ON o.id = le.order_id::text
   WHERE le.user_type = 'restaurant' AND le.type = 'deposit_volta'
     AND o.restaurant_id = p_partner_id
     AND o.status = 'delivered'
     AND o.delivered_at >= v_bounds.week_start
     AND o.delivered_at <= v_bounds.week_end;
  v_net := ROUND(v_share + v_deposit - v_cash_partner - v_extra_receitas, 2);
  v_direction := CASE
    WHEN v_net > 0 THEN 'bora_pays_partner'
    WHEN v_net < 0 THEN 'partner_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.partner_weekly_settlements (
      partner_id, week_start_at, week_end_at,
      total_orders, gross_sales, commission_total, partner_share,
      cash_kept_by_partner, net_balance, direction, status, deposit_volta_total,
      pago_em_mao_na_recolha, comissao_extra, comissao_extra_receitas
    ) VALUES (
      p_partner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_orders, v_gross, v_commission, v_share,
      v_cash_partner, v_net, v_direction, 'pending', v_deposit,
      v_pago_recolha, v_extra, v_extra_receitas
    )
    ON CONFLICT (partner_id, week_start_at) DO UPDATE SET
      total_orders            = EXCLUDED.total_orders,
      gross_sales             = EXCLUDED.gross_sales,
      commission_total        = EXCLUDED.commission_total,
      partner_share           = EXCLUDED.partner_share,
      cash_kept_by_partner    = EXCLUDED.cash_kept_by_partner,
      net_balance             = EXCLUDED.net_balance,
      deposit_volta_total     = EXCLUDED.deposit_volta_total,
      pago_em_mao_na_recolha  = EXCLUDED.pago_em_mao_na_recolha,
      comissao_extra          = EXCLUDED.comissao_extra,
      comissao_extra_receitas = EXCLUDED.comissao_extra_receitas,
      direction               = EXCLUDED.direction
    WHERE public.partner_weekly_settlements.status NOT IN ('paid','received')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'total_orders', v_total_orders,
    'gross_sales', v_gross,
    'commission_total', v_commission,
    'comissao_extra', v_extra,
    'receitas_valor', v_receitas,
    'comissao_extra_receitas', v_extra_receitas,
    'partner_share', v_share,
    'cash_kept_by_partner', v_cash_partner,
    'pago_em_mao_na_recolha', v_pago_recolha,
    'net_balance', v_net,
    'deposit_volta_total', v_deposit,
    'direction', v_direction,
    'settlement_id', v_id,
    'persisted', p_persist
  );
END;
$function$;
