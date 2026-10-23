-- 23/10/2026 — ENTREGA GRÁTIS POR LOJA (ordem do Danilo, "eu autorizo", 23/10 22:27 e 22:37)
-- McDonald's: entrega grátis a partir de 20 € de produtos.
-- Continente e Burger King: entrega grátis a partir de 30 € de produtos.
-- Abaixo do mínimo: paga a entrega normal (2,50 € + km) e NÃO paga a taxa de pedido pequeno.
-- A taxa de serviço (0,99 €) fica sempre.
-- Sem tocar no pricing_calculate (zona protegida): função nova pricing_calculate_loja que o
-- embrulha e, quando a loja dá entrega grátis, tira a entrega e recalcula a parte de 30% do
-- estafeta (o fixo do estafeta não muda). quote_order_pricing e create_order passam a usá-la.

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS free_delivery_min_cents integer
  CHECK (free_delivery_min_cents IS NULL OR free_delivery_min_cents >= 0);
COMMENT ON COLUMN public.restaurants.free_delivery_min_cents IS
  'Entrega grátis a partir deste subtotal (cêntimos). NULL = sem entrega grátis. Só lojas NÃO-parceiras. Ordem do Danilo 23/10/2026.';

CREATE OR REPLACE FUNCTION public.pricing_calculate_loja(
  p_service_type text, p_subtotal numeric, p_distance_km numeric,
  p_is_partner_store boolean, p_apartment_delivery boolean, p_is_stacked_partner boolean,
  p_bag_count integer, p_restaurant_id text)
RETURNS TABLE(delivery_fee numeric, service_fee numeric, platform_commission numeric,
              driver_earnings numeric, customer_total numeric, partner_markup_hidden numeric, bag_fee numeric)
LANGUAGE plpgsql STABLE
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
    -- mesmo cálculo do ramo não-parceiro do pricing_calculate, sem a entrega no bruto da Bora
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

  RETURN QUERY SELECT r.delivery_fee, r.service_fee, r.platform_commission, r.driver_earnings,
                      r.customer_total, r.partner_markup_hidden, r.bag_fee;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.pricing_calculate_loja(text,numeric,numeric,boolean,boolean,boolean,integer,text)
  TO authenticated, service_role;

DO $do$
DECLARE
  v_old text := pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure);
  v_new text;
  a1 text := 'FROM pricing_calculate(' || chr(10) || '      v_service_type, v_subtotal_server, v_distance_km, v_is_partner_store, v_apartment_delivery, FALSE' || chr(10) || '    );';
  a2 text := '''tokens_applied_value_cents'', v_token_cents' || chr(10) || '  );';
BEGIN
  IF position(a1 in v_old) = 0 OR position(a2 in v_old) = 0 THEN
    RAISE EXCEPTION 'quote_order_pricing: trechos nao encontrados';
  END IF;
  v_new := replace(v_old, a1,
    'FROM public.pricing_calculate_loja(' || chr(10) || '      v_service_type, v_subtotal_server, v_distance_km, v_is_partner_store, v_apartment_delivery, FALSE, 0, v_restaurant_id' || chr(10) || '    );');
  v_new := replace(v_new, a2,
    '''tokens_applied_value_cents'', v_token_cents,' || chr(10)
 || '    ''free_delivery_min_cents'', (SELECT r.free_delivery_min_cents FROM public.restaurants r' || chr(10)
 || '                                  WHERE r.id = v_restaurant_id AND NOT COALESCE(r.is_partner, false))' || chr(10)
 || '  );');
  EXECUTE v_new;
END
$do$;

DO $do$
DECLARE
  v_old text := pg_get_functiondef('public.create_order(jsonb)'::regprocedure);
  a1 text := 'FROM pricing_calculate(' || chr(10) || '      v_service_type, v_subtotal_server, v_distance_km,' || chr(10) || '      v_is_partner_store, v_apartment_delivery, FALSE, v_bag_count' || chr(10) || '    );';
BEGIN
  IF position(a1 in v_old) = 0 THEN
    RAISE EXCEPTION 'create_order: trecho nao encontrado';
  END IF;
  IF position('INTO v_restaurant_id' in v_old) = 0
     OR position('INTO v_restaurant_id' in v_old) > position(a1 in v_old) THEN
    RAISE EXCEPTION 'create_order: v_restaurant_id nao e definido antes do preco';
  END IF;
  EXECUTE replace(v_old, a1,
    'FROM public.pricing_calculate_loja(' || chr(10) || '      v_service_type, v_subtotal_server, v_distance_km,' || chr(10) || '      v_is_partner_store, v_apartment_delivery, FALSE, v_bag_count, v_restaurant_id' || chr(10) || '    );');
END
$do$;

DO $do$
DECLARE
  v_old text := pg_get_functiondef('public._restaurants_campos_so_admin()'::regprocedure);
  a1 text := '  IF cardinality(v_campos) > 0 THEN';
BEGIN
  IF position('free_delivery_min_cents' in v_old) = 0 THEN
    EXECUTE replace(v_old, a1,
      '  IF NEW.free_delivery_min_cents IS DISTINCT FROM OLD.free_delivery_min_cents THEN v_campos := array_append(v_campos, ''free_delivery_min_cents''); END IF;' || chr(10) || a1);
  END IF;
END
$do$;

UPDATE public.restaurants SET free_delivery_min_cents = 2000, small_order_fee_cents_override = 0
 WHERE id = 'mcdonalds-guarda';
UPDATE public.restaurants SET free_delivery_min_cents = 3000, small_order_fee_cents_override = 0
 WHERE id IN ('continente-guarda', 'burgerking-guarda');
