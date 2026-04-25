-- ============================================================
-- Fix bag fee — 2026-04-25
--
-- Bug 1: pricing_calculate não expunha bag_fee como coluna separada.
--        Adicionado bag_fee ao RETURNS TABLE.
-- Bug 2: create_order lia bag_fee do input do cliente (nunca enviado).
--        Passa a ler v_pricing.bag_fee calculado pelo servidor.
-- ============================================================

-- ── Fix 1: pricing_calculate — expor bag_fee como coluna separada ──────────

CREATE OR REPLACE FUNCTION pricing_calculate(
  p_service_type        TEXT,
  p_subtotal            NUMERIC,
  p_distance_km         NUMERIC,
  p_is_partner_store    BOOLEAN DEFAULT FALSE,
  p_apartment_delivery  BOOLEAN DEFAULT FALSE,
  p_is_stacked_partner  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  delivery_fee           NUMERIC,
  service_fee            NUMERIC,
  platform_commission    NUMERIC,
  driver_earnings        NUMERIC,
  customer_total         NUMERIC,
  partner_markup_hidden  NUMERIC,
  bag_fee                NUMERIC    -- NEW: exposto separadamente
)
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  -- Base constants
  c_driver_base_pay              CONSTANT NUMERIC := 3.80;
  c_driver_per_km                CONSTANT NUMERIC := 0.20;

  -- Partner
  c_partner_delivery_base        CONSTANT NUMERIC := 2.50;
  c_partner_commission_rate      CONSTANT NUMERIC := 0.10;
  c_partner_service_fee_rate     CONSTANT NUMERIC := 0.05;
  c_partner_markup_hidden_rate   CONSTANT NUMERIC := 0.05;
  c_partner_stacking_bonus       CONSTANT NUMERIC := 3.00;

  -- Non-partner
  c_non_partner_markup_rate      CONSTANT NUMERIC := 0.15;
  c_non_partner_purchase_fee     CONSTANT NUMERIC := 2.50;
  c_shopping_driver_bonus        CONSTANT NUMERIC := 0.80;
  c_driver_profit_share_rate     CONSTANT NUMERIC := 0.30;

  -- Logistics (carryGroceries / sendPackage)
  c_logistics_driver_base_pay    CONSTANT NUMERIC := 4.00;
  c_logistics_driver_per_km      CONSTANT NUMERIC := 0.50;
  c_package_base_fee             CONSTANT NUMERIC := 6.00;
  c_package_base_distance_km     CONSTANT NUMERIC := 4.00;
  c_package_extra_per_km         CONSTANT NUMERIC := 0.50;
  c_package_platform_share       CONSTANT NUMERIC := 2.00;

  -- Apartment surcharge
  c_apartment_surcharge_total    CONSTANT NUMERIC := 1.50;
  c_apartment_driver_share       CONSTANT NUMERIC := 1.00;
  c_apartment_platform_share     CONSTANT NUMERIC := 0.50;

  -- Restaurant bag fee (parceiro e não-parceiro)
  c_restaurant_bag_fee           CONSTANT NUMERIC := 0.30;

  -- Working variables
  v_distance       NUMERIC;
  v_subtotal       NUMERIC;
  v_apt_surcharge  NUMERIC;
  v_apt_driver     NUMERIC;
  v_apt_platform   NUMERIC;
  v_extra_dist     NUMERIC;

  v_delivery_fee          NUMERIC := 0;
  v_service_fee           NUMERIC := 0;
  v_platform_commission   NUMERIC := 0;
  v_driver_earnings       NUMERIC := 0;
  v_partner_markup_hidden NUMERIC := 0;
  v_bag_fee               NUMERIC := 0;

  v_is_partner_order BOOLEAN;
  v_is_package       BOOLEAN;
  v_is_non_partner   BOOLEAN;
BEGIN
  v_distance  := GREATEST(1.0, COALESCE(p_distance_km, 1.0));
  v_subtotal  := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));

  v_apt_surcharge := CASE WHEN p_apartment_delivery THEN c_apartment_surcharge_total ELSE 0 END;
  v_apt_driver    := CASE WHEN p_apartment_delivery THEN c_apartment_driver_share    ELSE 0 END;
  v_apt_platform  := CASE WHEN p_apartment_delivery THEN c_apartment_platform_share  ELSE 0 END;

  v_is_partner_order := p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');
  v_is_package       := p_service_type IN ('sendPackage','carryGroceries');
  v_is_non_partner   := NOT p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');

  IF v_is_partner_order THEN
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee        := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_service_fee         := ROUND(v_subtotal * c_partner_service_fee_rate, 2);
    v_platform_commission := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_partner_markup_hidden := ROUND(v_subtotal * c_partner_markup_hidden_rate, 2);
    v_driver_earnings     := ROUND(
      c_driver_base_pay
      + (c_driver_per_km * v_distance)
      + v_apt_driver
      + CASE WHEN p_is_stacked_partner THEN c_partner_stacking_bonus ELSE 0 END,
    2);

  ELSIF v_is_non_partner THEN
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_service_fee         := c_non_partner_purchase_fee;
    v_delivery_fee        := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_platform_commission := c_non_partner_purchase_fee + v_apt_platform;

    DECLARE
      v_shopping_bonus NUMERIC;
      v_driver_fixed   NUMERIC;
      v_bora_markup    NUMERIC;
      v_bora_gross     NUMERIC;
      v_bora_net       NUMERIC;
    BEGIN
      v_shopping_bonus := CASE WHEN p_service_type = 'storeShopping' THEN c_shopping_driver_bonus ELSE 0 END;
      v_driver_fixed   := ROUND(c_driver_base_pay + v_shopping_bonus + (c_driver_per_km * v_distance) + v_apt_driver, 2);
      v_bora_markup    := ROUND(v_subtotal * c_non_partner_markup_rate, 2);
      v_bora_gross     := v_bora_markup + v_delivery_fee + v_service_fee;
      v_bora_net       := GREATEST(0, v_bora_gross - v_driver_fixed);
      v_driver_earnings := ROUND(v_driver_fixed + ROUND(v_bora_net * c_driver_profit_share_rate, 2), 2);
    END;

  ELSIF v_is_package THEN
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee        := c_package_base_fee + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_platform_commission := c_package_platform_share + v_apt_platform;
    v_driver_earnings     := ROUND(
      c_logistics_driver_base_pay
      + (c_logistics_driver_per_km * v_distance)
      + c_shopping_driver_bonus
      + v_apt_driver,
    2);

  ELSE
    v_delivery_fee        := c_partner_delivery_base + v_apt_surcharge;
    v_platform_commission := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_driver_earnings     := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver, 2);
  END IF;

  -- Bag fee: €0.30 fixo para restaurant (parceiro e não-parceiro).
  -- StoreShopping: 0 aqui (driver conta sacos depois via updateBagCount).
  v_bag_fee := CASE WHEN p_service_type = 'restaurant' THEN c_restaurant_bag_fee ELSE 0 END;

  RETURN QUERY SELECT
    ROUND(v_delivery_fee, 2),
    ROUND(v_service_fee, 2),
    ROUND(v_platform_commission, 2),
    ROUND(v_driver_earnings, 2),
    ROUND(v_subtotal + v_service_fee + v_delivery_fee + v_bag_fee, 2),
    ROUND(v_partner_markup_hidden, 2),
    ROUND(v_bag_fee, 2);    -- NEW: bag_fee como coluna separada
END;
$$;


-- ── Fix 2: create_order — usar v_pricing.bag_fee em vez do input do cliente ─

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
      v_subtotal_server := v_subtotal_server + (
        SELECT COALESCE(p.price, 0) * COALESCE((v_line->>'quantity')::NUMERIC, 1)
        FROM products p
        WHERE p.id = (v_line->>'product_id')::UUID
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
    v_pricing.bag_fee,                -- FIX: era CASE WHEN p_input->>'bag_fee' ... → sempre 0
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
    'bag_fee',                   v_pricing.bag_fee,   -- FIX: era CASE WHEN p_input->>'bag_fee' ... → sempre 0
    'apartment_surcharge',       CASE WHEN v_apartment_delivery THEN 1.50 ELSE 0 END,
    'payment_buffer_total',      v_buffer_total,
    'customer_total',            v_pricing.customer_total,
    'partner_markup_hidden',     v_pricing.partner_markup_hidden
  );
END;
$$;
