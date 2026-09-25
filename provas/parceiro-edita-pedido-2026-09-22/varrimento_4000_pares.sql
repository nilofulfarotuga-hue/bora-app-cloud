CREATE OR REPLACE FUNCTION pg_temp.mk(p_rid text, p_sub numeric, p_metodo text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE pc record; v_id text := gen_random_uuid()::text;
BEGIN
  SELECT * INTO pc FROM public.pricing_calculate('restaurant', p_sub, 2.3, true, false, false, 1);
  INSERT INTO public.orders (id, user_id, status, service_type, is_partner_store, restaurant_id, payment_method, payment_status, payment_intent_id, items, subtotal, delivery_fee, service_fee, bag_fee, bag_count,
     platform_commission, partner_commission_visible, partner_markup_hidden, partner_service_fee_client, driver_earnings, distance_km, price, final_total, payment_buffer_total, small_order_fee)
  VALUES (v_id, 'c9fccf85-03ee-4efc-83bf-613f211a78ff', 'preparing', 'restaurant', true, p_rid, p_metodo, 'paid', 'pi_x', '[]', p_sub, pc.delivery_fee, pc.service_fee, pc.bag_fee, 1,
     pc.platform_commission, pc.platform_commission, pc.partner_markup_hidden, pc.service_fee, pc.driver_earnings, 2.3, pc.customer_total, pc.customer_total, pc.customer_total, 0);
  RETURN v_id;
END $$;
DO $$
DECLARE i int; a numeric; b numeric; rid text; o text; ref text; m jsonb; r record; falhas int := 0; total int := 0; ex text;
BEGIN
  FOR i IN 1..4000 LOOP
    rid := CASE WHEN i % 2 = 0 THEN '12aa2cbb-01bd-443b-a17e-633c169d4864' ELSE 'mrkebab-guarda' END;
    a := round((random() * 199.99 + 0.01)::numeric, 2);
    b := round((random() * 199.99 + 0.01)::numeric, 2);
    o := pg_temp.mk(rid, a, 'card');
    ref := pg_temp.mk(rid, b, 'card');
    m := public._order_edit_money(o, b);
    SELECT * INTO r FROM public.orders WHERE id = ref;
    total := total + 1;
    IF (m->>'service_fee')::numeric <> r.service_fee OR (m->>'partner_markup_hidden')::numeric <> r.partner_markup_hidden
       OR (m->>'platform_commission')::numeric <> r.platform_commission OR (m->>'partner_commission_visible')::numeric <> r.partner_commission_visible
       OR (m->>'small_order_fee')::numeric <> r.small_order_fee OR (m->>'total_depois')::numeric <> r.final_total
       OR public.partner_store_share(b, rid) + (m->>'partner_markup_hidden')::numeric + (m->>'platform_commission')::numeric <> b THEN
      falhas := falhas + 1; ex := format('%s %s->%s %s vs %s', rid, a, b, m, row_to_json(r));
    END IF;
  END LOOP;
  RAISE EXCEPTION 'VARRIMENTO % pares, % falhas %', total, falhas, coalesce(ex,'');
END $$;
