-- ============================================================
-- Fix subtotal calculation (Opção C) — 2026-04-25
--
-- Bug: create_order calculava v_subtotal_server via lookup por
--      product_id na tabela products. O Flutter envia unit_price
--      mas NÃO envia product_id → subquery retorna NULL →
--      0 + NULL = NULL → v_subtotal_server = NULL →
--      pricing_calculate(NULL) → subtotal ignorado →
--      price = só delivery_fee + service_fee (~€5–6.50).
--
-- Fix (Opção C):
--   1. Primeiro tenta lookup por product_id (validação server-side)
--   2. Se não encontrado (ou product_id ausente), usa unit_price
--      do payload Flutter — campo já enviado pelo CartStore
--   3. COALESCE(..., 0) elimina propagação de NULL
--
-- Scope: só o loop de cálculo v_subtotal_server (8 linhas).
--        pricing_calculate, INSERT, RETURN, bag_fee, tokens,
--        dispatch — sem alterações.
-- ============================================================

CREATE OR REPLACE FUNCTION create_order(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_user_id            UUID := auth.uid();
  v_service_type       TEXT;
  v_distance_km        NUMERIC;
  v_is_partner_store   BOOLEAN;
  v_apartment_delivery BOOLEAN;
  v_payment_method     TEXT;
  v_vendor_name        TEXT;
  v_subtotal_input     NUMERIC;
  v_subtotal_server    NUMERIC;
  v_pricing            RECORD;
  v_order_id           TEXT;
  v_bag_count          INTEGER;
  v_buffer_total       NUMERIC;
  v_product_lines      JSONB;
  v_line               JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: create_order requires an authenticated session';
  END IF;

  v_service_type       := COALESCE(p_input->>'service_type', '');
  v_distance_km        := COALESCE((p_input->>'distance_km')::NUMERIC, 1);
  v_is_partner_store   := COALESCE((p_input->>'is_partner_store')::BOOLEAN, FALSE);
  v_apartment_delivery := COALESCE((p_input->>'apartment_delivery')::BOOLEAN, FALSE);
  v_payment_method     := COALESCE(p_input->>'payment_method', 'cash');
  v_vendor_name        := p_input->>'vendor_name';
  v_subtotal_input     := COALESCE((p_input->>'subtotal')::NUMERIC, 0);
  v_bag_count          := COALESCE((p_input->>'bag_count')::INTEGER, 0);
  v_product_lines      := p_input->'product_lines';

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;

  IF v_payment_method NOT IN ('cash','mbway','card') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_METHOD: %', v_payment_method;
  END IF;

  IF v_distance_km < 0 THEN
    RAISE EXCEPTION 'INVALID_DISTANCE: %', v_distance_km;
  END IF;

  IF v_service_type IN ('restaurant','storeShopping')
     AND v_product_lines IS NOT NULL
     AND jsonb_typeof(v_product_lines) = 'array'
     AND jsonb_array_length(v_product_lines) > 0
  THEN
    v_subtotal_server := 0;
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_product_lines)
    LOOP
      -- FIX (Opção C): tenta lookup product_id; fallback para unit_price do payload
      v_subtotal_server := v_subtotal_server + (
        COALESCE(
          (SELECT p.price FROM products p WHERE p.id = (v_line->>'product_id') LIMIT 1),
          (v_line->>'unit_price')::NUMERIC,
          0
        ) * COALESCE((v_line->>'quantity')::NUMERIC, 1)
      );
    END LOOP;
    IF NOT v_is_partner_store THEN
      v_subtotal_server := v_subtotal_server * 1.15;
    END IF;
    v_subtotal_server := ROUND(v_subtotal_server::numeric, 2);
  ELSE
    v_subtotal_server := ROUND(v_subtotal_input::numeric, 2);
  END IF;

  SELECT * INTO v_pricing FROM pricing_calculate(
    v_service_type,
    v_subtotal_server,
    v_distance_km,
    v_is_partner_store,
    v_apartment_delivery,
    FALSE
  );

  IF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_pricing.customer_total * 1.15)::numeric, 2);
  ELSE
    v_buffer_total := v_pricing.customer_total;
  END IF;

  v_order_id := gen_random_uuid()::TEXT;

  INSERT INTO orders (
    id, user_id, status, payment_status,
    service_type, vendor_name, is_partner_store, apartment_delivery,
    distance_km, payment_method, bag_count,
    subtotal, delivery_fee, service_fee, platform_commission,
    driver_earnings, bag_fee, price, final_total, payment_buffer_total,
    partner_commission_visible, partner_markup_hidden, partner_service_fee_client,
    customer_name, customer_notes, client_phone,
    pickup_address, pickup_street, pickup_city, pickup_postal_code,
    dropoff_address, dropoff_street, dropoff_city, dropoff_postal_code,
    items, requires_car, order_type
  ) VALUES (
    v_order_id, v_user_id, 'created', 'pending',
    v_service_type, v_vendor_name, v_is_partner_store, v_apartment_delivery,
    v_distance_km, v_payment_method, v_bag_count,
    v_subtotal_server,
    v_pricing.delivery_fee,
    v_pricing.service_fee,
    v_pricing.platform_commission,
    v_pricing.driver_earnings,
    v_pricing.bag_fee,
    v_pricing.customer_total,
    v_pricing.customer_total,
    v_buffer_total,
    CASE WHEN v_is_partner_store THEN v_pricing.platform_commission ELSE 0 END,
    v_pricing.partner_markup_hidden,
    CASE WHEN v_is_partner_store THEN v_pricing.service_fee ELSE 0 END,
    p_input->>'customer_name', p_input->>'customer_notes', p_input->>'client_phone',
    p_input->>'pickup_address', p_input->>'pickup_street', p_input->>'pickup_city', p_input->>'pickup_postal_code',
    p_input->>'dropoff_address', p_input->>'dropoff_street', p_input->>'dropoff_city', p_input->>'dropoff_postal_code',
    COALESCE(p_input->'items', '[]'::jsonb),
    COALESCE((p_input->>'requires_car')::BOOLEAN, FALSE),
    COALESCE(p_input->>'order_type', 'nonPartnerPurchase')
  );

  RETURN jsonb_build_object(
    'order_id',                  v_order_id,
    'price',                     v_pricing.customer_total,
    'subtotal',                  v_subtotal_server,
    'delivery_fee',              v_pricing.delivery_fee,
    'service_fee',               v_pricing.service_fee,
    'platform_commission',       v_pricing.platform_commission,
    'driver_earnings',           v_pricing.driver_earnings,
    'bag_fee',                   v_pricing.bag_fee,
    'apartment_surcharge',       CASE WHEN v_apartment_delivery THEN 1.50 ELSE 0 END,
    'payment_buffer_total',      v_buffer_total,
    'customer_total',            v_pricing.customer_total,
    'partner_markup_hidden',     v_pricing.partner_markup_hidden
  );
END;
$$;
