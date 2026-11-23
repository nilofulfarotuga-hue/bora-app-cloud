-- 20261123140000_farmacia_com_markup_rego
-- Aplicada em producao pela Claude.ai a 23/11/2026 ~21:30 (apply_migration farmacia_com_markup_rego),
-- com o AUTORIZO do Danilo de 23/11 13:36 e o 'eu autorizo' de 21:21. Hashes das outras lojas iguais antes e depois.
-- Rego, 10 EUR de balcao a 2 km: cliente 15,97; Rego 10,00; estafeta 4,20; comissao Bora 1,50.

create or replace function public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
 returns numeric
 language sql
 stable
 set search_path to 'public'
as $function$
  SELECT CASE
    -- 23/11/2026 farmácia com markup (Rego, AUTORIZO do Danilo 23/11 13:36): a farmácia recebe o balcão = subtotal / (1 + markup).
    WHEN public._e_farmacia_parceira(p_restaurant_id)
         AND COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    -- 14/11/2026 farmácias: preço ao cliente = preço da Glovo e a farmácia recebe tudo (sem markup oculto).
    WHEN public._e_farmacia_parceira(p_restaurant_id)
      THEN ROUND(p_subtotal, 2)
    WHEN COALESCE((SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id), 0) > 0
      THEN ROUND(p_subtotal / (1 + (SELECT r.app_markup_pct FROM public.restaurants r WHERE r.id = p_restaurant_id)), 2)
    ELSE public.partner_store_share(p_subtotal)
  END;
$function$;

-- Corpo igual ao que está no ar a 23/11/2026; só muda o bloco das farmácias (marcado 23/11).
create or replace function public.pricing_calculate_loja(p_service_type text, p_subtotal numeric, p_distance_km numeric, p_is_partner_store boolean, p_apartment_delivery boolean, p_is_stacked_partner boolean, p_bag_count integer, p_restaurant_id text)
 returns table(delivery_fee numeric, service_fee numeric, platform_commission numeric, driver_earnings numeric, customer_total numeric, partner_markup_hidden numeric, bag_fee numeric)
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
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
  v_emb NUMERIC;
  v_markup NUMERIC;
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
    SELECT COALESCE(x.app_markup_pct, 0) INTO v_markup FROM public.restaurants x WHERE x.id = p_restaurant_id;
    IF v_markup > 0 THEN
      -- 23/11/2026 farmácia com markup (Rego, AUTORIZO do Danilo 23/11 13:36): o markup já vem dentro do preço
      -- do produto (balcão × (1 + markup)) e fica para a Bora; taxa de serviço = só client_service_fee_pct do
      -- subtotal (sem os 0,99 € fixos); sem saco; entrega igual; pedido pequeno à parte, como nas farmácias.
      r.service_fee := ROUND(v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
      r.partner_markup_hidden := 0;
      r.platform_commission := ROUND(v_sub - ROUND(v_sub / (1 + v_markup), 2), 2)
                             + CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
    ELSE
      r.service_fee := ROUND(COALESCE((s->>'pharmacy_service_fee_fixed_cents')::NUMERIC, 0) / 100.0
                             + v_sub * COALESCE((s->>'client_service_fee_pct')::NUMERIC, 0), 2);
      r.partner_markup_hidden := 0;
      r.platform_commission := CASE WHEN COALESCE(p_apartment_delivery, false)
                                    THEN ROUND(COALESCE((s->>'apartment_platform_share_cents')::NUMERIC, 0) / 100.0, 2)
                                    ELSE 0 END;
    END IF;
    r.bag_fee := 0;
    r.customer_total := ROUND(v_sub + r.service_fee + r.delivery_fee + r.bag_fee, 2);
  END IF;

  -- 23/11/2026 embalagem da loja (AUTORIZO do Danilo 23/11 10:44): em vez do saco, o valor da loja; vai 100 % para a loja.
  IF p_service_type = 'restaurant' AND p_restaurant_id IS NOT NULL THEN
    v_emb := public.embalagem_loja_valor(p_restaurant_id, v_sub);
    IF v_emb IS NOT NULL THEN
      r.customer_total := ROUND(r.customer_total - COALESCE(r.bag_fee, 0) + v_emb, 2);
      r.bag_fee := v_emb;
    END IF;
  END IF;

  RETURN QUERY SELECT r.delivery_fee, r.service_fee, r.platform_commission, r.driver_earnings,
                      r.customer_total, r.partner_markup_hidden, r.bag_fee;
END;
$function$;
