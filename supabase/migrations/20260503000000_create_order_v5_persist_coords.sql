-- BUG 1: persist pickup/dropoff coords in create_order RPC.
-- Previous v4 (20260430260000_payment_drafts_gating.sql) omitted lat/lng
-- columns from the INSERT statement, leaving 90% of orders with NULL coords.
-- v5 adds the 4 columns and validates them up-front.
--
-- Validation:
--   dropoff_lat/dropoff_lng — REQUIRED for every service_type
--   pickup_lat/pickup_lng   — REQUIRED for restaurant/storeShopping/carryGroceries
--                             (sendPackage may have NULL pickup — origin is
--                             customer-supplied address)

CREATE OR REPLACE FUNCTION public.create_order(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_user_id            UUID;
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
  v_wallet_cents       INTEGER;
  v_wallet_eur         NUMERIC;
  v_charge_total       NUMERIC;
  v_max_wallet_cents   INTEGER;
  v_balance_check      INTEGER;
  v_restaurant_id      TEXT;
  v_credit_result      JSONB;
  v_credit_cents       INTEGER := 0;
  v_payment_already_confirmed BOOLEAN;
  v_payment_intent_id  TEXT;
  v_initial_payment_status TEXT;
  v_pickup_lat         DOUBLE PRECISION;
  v_pickup_lng         DOUBLE PRECISION;
  v_dropoff_lat        DOUBLE PRECISION;
  v_dropoff_lng        DOUBLE PRECISION;
BEGIN
  v_user_id := COALESCE((p_input->>'user_id')::UUID, auth.uid());
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: create_order requires an authenticated session or user_id';
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
  v_wallet_cents       := COALESCE((p_input->>'wallet_applied_cents')::INTEGER, 0);
  v_payment_already_confirmed := COALESCE((p_input->>'payment_already_confirmed')::BOOLEAN, FALSE);
  v_payment_intent_id  := p_input->>'payment_intent_id';

  -- Coord parsing (NULL-safe)
  v_pickup_lat  := NULLIF(p_input->>'pickup_lat', '')::DOUBLE PRECISION;
  v_pickup_lng  := NULLIF(p_input->>'pickup_lng', '')::DOUBLE PRECISION;
  v_dropoff_lat := NULLIF(p_input->>'dropoff_lat', '')::DOUBLE PRECISION;
  v_dropoff_lng := NULLIF(p_input->>'dropoff_lng', '')::DOUBLE PRECISION;

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;
  IF v_payment_method NOT IN ('cash','mbway','card') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_METHOD: %', v_payment_method;
  END IF;
  IF v_distance_km < 0 THEN
    RAISE EXCEPTION 'INVALID_DISTANCE: %', v_distance_km;
  END IF;
  IF v_wallet_cents < 0 THEN
    RAISE EXCEPTION 'INVALID_WALLET_AMOUNT: %', v_wallet_cents;
  END IF;

  -- BUG 1: hard-validate coords. No fallback geocoding.
  IF v_dropoff_lat IS NULL OR v_dropoff_lng IS NULL THEN
    RAISE EXCEPTION 'MISSING_DROPOFF_COORDS: dropoff_lat/dropoff_lng required for every service_type'
      USING ERRCODE = '23502';
  END IF;
  IF v_service_type IN ('restaurant','storeShopping','carryGroceries')
     AND (v_pickup_lat IS NULL OR v_pickup_lng IS NULL) THEN
    RAISE EXCEPTION 'MISSING_PICKUP_COORDS: pickup_lat/pickup_lng required for service_type=%', v_service_type
      USING ERRCODE = '23502';
  END IF;

  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id FOR UPDATE;
    IF v_balance_check IS NULL OR v_balance_check < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%',
        COALESCE(v_balance_check, 0), v_wallet_cents
        USING ERRCODE='23514';
    END IF;
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
        COALESCE(
          (SELECT p.price FROM products p WHERE p.id = (v_line->>'product_id') LIMIT 1),
          (v_line->>'unit_price')::NUMERIC, 0
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
    v_service_type, v_subtotal_server, v_distance_km,
    v_is_partner_store, v_apartment_delivery, FALSE
  );

  v_max_wallet_cents := ROUND(v_pricing.customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN
    v_wallet_cents := v_max_wallet_cents;
  END IF;
  v_wallet_eur := v_wallet_cents / 100.0;

  v_order_id := gen_random_uuid()::TEXT;

  IF v_is_partner_store AND v_vendor_name IS NOT NULL THEN
    SELECT id INTO v_restaurant_id FROM public.restaurants
      WHERE name = v_vendor_name LIMIT 1;
  END IF;

  IF v_restaurant_id IS NOT NULL THEN
    v_credit_result := public.consume_menu_credit_for_order(
      v_user_id, v_restaurant_id, v_order_id
    );
    IF (v_credit_result->>'used')::boolean THEN
      v_credit_cents := (v_credit_result->>'amount_cents')::int;
      IF v_credit_cents > (v_max_wallet_cents - v_wallet_cents) THEN
        v_credit_cents := GREATEST(v_max_wallet_cents - v_wallet_cents, 0);
      END IF;
    END IF;
  END IF;

  v_charge_total := v_pricing.customer_total - v_wallet_eur - (v_credit_cents / 100.0);

  IF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_charge_total * 1.15)::numeric, 2);
  ELSE
    v_buffer_total := v_charge_total;
  END IF;

  v_initial_payment_status := CASE
    WHEN v_payment_already_confirmed THEN 'paid'
    WHEN v_charge_total <= 0 THEN 'paid'
    ELSE 'pending'
  END;

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
    pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
    items, requires_car, order_type, wallet_applied_cents, menu_credit_applied_cents,
    payment_intent_id
  ) VALUES (
    v_order_id, v_user_id, 'created', v_initial_payment_status,
    v_service_type, v_vendor_name, v_is_partner_store, v_apartment_delivery,
    v_distance_km, v_payment_method, v_bag_count,
    v_subtotal_server, v_pricing.delivery_fee, v_pricing.service_fee,
    v_pricing.platform_commission, v_pricing.driver_earnings, v_pricing.bag_fee,
    v_pricing.customer_total, v_pricing.customer_total, v_buffer_total,
    CASE WHEN v_is_partner_store THEN v_pricing.platform_commission ELSE 0 END,
    v_pricing.partner_markup_hidden,
    CASE WHEN v_is_partner_store THEN v_pricing.service_fee ELSE 0 END,
    p_input->>'customer_name', p_input->>'customer_notes', p_input->>'client_phone',
    p_input->>'pickup_address', p_input->>'pickup_street', p_input->>'pickup_city', p_input->>'pickup_postal_code',
    p_input->>'dropoff_address', p_input->>'dropoff_street', p_input->>'dropoff_city', p_input->>'dropoff_postal_code',
    v_pickup_lat, v_pickup_lng, v_dropoff_lat, v_dropoff_lng,
    COALESCE(p_input->'items', '[]'::jsonb),
    COALESCE((p_input->>'requires_car')::BOOLEAN, FALSE),
    COALESCE(p_input->>'order_type', 'nonPartnerPurchase'),
    v_wallet_cents,
    v_credit_cents,
    v_payment_intent_id
  );

  IF v_wallet_cents > 0 THEN
    PERFORM wallet_debit_for_order(v_user_id, v_order_id, v_wallet_cents);
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'price', v_pricing.customer_total,
    'subtotal', v_subtotal_server,
    'delivery_fee', v_pricing.delivery_fee,
    'service_fee', v_pricing.service_fee,
    'platform_commission', v_pricing.platform_commission,
    'driver_earnings', v_pricing.driver_earnings,
    'bag_fee', v_pricing.bag_fee,
    'apartment_surcharge', CASE WHEN v_apartment_delivery THEN 1.50 ELSE 0 END,
    'payment_buffer_total', v_buffer_total,
    'customer_total', v_pricing.customer_total,
    'partner_markup_hidden', v_pricing.partner_markup_hidden,
    'wallet_applied_cents', v_wallet_cents,
    'menu_credit_applied_cents', v_credit_cents,
    'charge_total', v_charge_total,
    'fully_paid_by_wallet', v_charge_total <= 0,
    'payment_status', v_initial_payment_status
  );
END;
$function$;
