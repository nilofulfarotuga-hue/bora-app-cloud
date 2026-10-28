-- 28/10/2026 — entrega grátis também em lojas PARCEIRAS (ordem do Danilo, 28/10 12:17:
-- "acima de 30 euros a taxa sairia grátis ... e se não, tem que cobrar essa taxa. Pronto,
-- pode ser isso. É isso aí mesmo."). Loja parceira com restaurants.free_delivery_min_cents:
-- a partir desse subtotal (preço da app) o cliente não paga a taxa base de entrega
-- (delivery_base_fee_cents); os km acima da distância base e o suplemento de apartamento
-- continuam a pagar-se; o estafeta recebe igual; a Bora absorve. O ramo dos NÃO parceiros
-- (23/10) fica exatamente igual. Usado por quote_order_pricing e create_order.
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
    v_poupado := GREATEST(0, r.delivery_fee - COALESCE(v_apt, 0));
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

  RETURN QUERY SELECT r.delivery_fee, r.service_fee, r.platform_commission, r.driver_earnings,
                      r.customer_total, r.partner_markup_hidden, r.bag_fee;
END;
$function$;
