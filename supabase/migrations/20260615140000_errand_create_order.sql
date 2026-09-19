-- ═══════════════════════════════════════════════════════════════════════════
-- FAVORES (errand) — Fase 2.B: create_order branch errand
-- Mudanças cirúrgicas vs versão actual:
--   (1) Allowlist: +'errand'.
--   (2) Bloco errand entre marcadores ╔BEGIN/END══╝, retorna cedo.
-- TODO o resto BYTE-A-BYTE IDÊNTICO ao original.
-- Prova de byte-a-byte: md5(DEPOIS strip(',''errand''' + bloco_marcado)) == ANTES.
-- final_total / final_purchase_value FICAM NULL (default) — escrita só em
-- finalize_errand_purchase (Fase 2.C) via GUC app.financial_bypass='true'.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_order(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id            UUID;
  v_service_type       TEXT;
  v_distance_km        NUMERIC;
  v_max_distance_km    NUMERIC;
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
  v_wallet_neg_enabled BOOLEAN;
  v_wallet_max_neg     INTEGER;
  v_wallet_balance_pre INTEGER := NULL;
  v_settlement_cents   INTEGER := 0;
  v_is_takeaway        BOOLEAN;
  v_takeaway_curbside  BOOLEAN;
  v_takeaway_pickup_code TEXT;
  v_delivery_fee       NUMERIC := 0;
  v_service_fee        NUMERIC := 0;
  v_platform_commission NUMERIC := 0;
  v_driver_earnings    NUMERIC := 0;
  v_customer_total     NUMERIC := 0;
  v_partner_markup     NUMERIC := 0;
  v_bag_fee            NUMERIC := 0;
  -- B3a (2026-06-12): cap de pagamento com tokens
  v_token_cents        INTEGER;
  v_token_max_pct      NUMERIC;
  v_token_cap_cents    INTEGER;
  -- T1 (2026-06-11): extras das opções escolhidas
  v_items_in           JSONB;
  v_item               JSONB;
  v_line_extras        NUMERIC;
  v_line_priced        JSONB;
  v_items_enriched     JSONB;
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
  v_token_cents        := COALESCE((p_input->>'token_discount_cents')::INTEGER, 0);
  v_payment_already_confirmed := COALESCE((p_input->>'payment_already_confirmed')::BOOLEAN, FALSE);
  v_payment_intent_id  := p_input->>'payment_intent_id';
  v_takeaway_curbside  := COALESCE((p_input->>'takeaway_is_curbside')::BOOLEAN, FALSE);
  v_is_takeaway        := (v_service_type = 'takeaway');
  -- T1: default = items tal como chegaram (enriquecidos só no ramo product_lines)
  v_items_enriched     := COALESCE(p_input->'items', '[]'::jsonb);

  v_pickup_lat  := NULLIF(p_input->>'pickup_lat', '')::DOUBLE PRECISION;
  v_pickup_lng  := NULLIF(p_input->>'pickup_lng', '')::DOUBLE PRECISION;
  v_dropoff_lat := NULLIF(p_input->>'dropoff_lat', '')::DOUBLE PRECISION;
  v_dropoff_lng := NULLIF(p_input->>'dropoff_lng', '')::DOUBLE PRECISION;

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage','takeaway','errand') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;
  IF v_payment_method NOT IN ('cash','mbway','card') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_METHOD: %', v_payment_method;
  END IF;
  IF v_distance_km < 0 THEN
    RAISE EXCEPTION 'INVALID_DISTANCE: %', v_distance_km;
  END IF;

  -- B1 (2026-06-12): cap de distância de entrega (auditoria pré-launch).
  IF NOT v_is_takeaway THEN
    SELECT (value::text)::NUMERIC INTO v_max_distance_km
      FROM platform_settings WHERE key = 'delivery_max_distance_km';
    v_max_distance_km := COALESCE(v_max_distance_km, 15);
    IF v_distance_km > v_max_distance_km THEN
      RAISE EXCEPTION 'delivery_distance_exceeded: % km > % km',
        v_distance_km, v_max_distance_km USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_wallet_cents < 0 THEN
    RAISE EXCEPTION 'INVALID_WALLET_AMOUNT: %', v_wallet_cents;
  END IF;
  IF v_token_cents < 0 THEN
    RAISE EXCEPTION 'INVALID_TOKEN_AMOUNT: %', v_token_cents;
  END IF;

  IF NOT v_is_takeaway THEN
    IF v_dropoff_lat IS NULL OR v_dropoff_lng IS NULL THEN
      RAISE EXCEPTION 'MISSING_DROPOFF_COORDS' USING ERRCODE = '23502';
    END IF;
  END IF;

  IF v_service_type IN ('restaurant','storeShopping','carryGroceries','takeaway')
     AND (v_pickup_lat IS NULL OR v_pickup_lng IS NULL) THEN
    RAISE EXCEPTION 'MISSING_PICKUP_COORDS' USING ERRCODE = '23502';
  END IF;

  -- ★ RESOLVE restaurant_id ANTES de tudo (incluindo para delivery normal)
  IF v_is_partner_store AND v_vendor_name IS NOT NULL THEN
    SELECT id INTO v_restaurant_id FROM public.restaurants
      WHERE name = v_vendor_name LIMIT 1;
  END IF;

  IF v_is_takeaway THEN
    IF NOT v_is_partner_store THEN
      RAISE EXCEPTION 'TAKEAWAY_REQUIRES_PARTNER';
    END IF;
    -- Verificar que takeaway está activo para este parceiro
    IF NOT EXISTS (
      SELECT 1 FROM public.restaurants
      WHERE id = v_restaurant_id AND takeaway_enabled = true
    ) THEN
      RAISE EXCEPTION 'TAKEAWAY_NOT_ENABLED: partner % does not accept takeaway', v_vendor_name;
    END IF;
  END IF;

  SELECT COALESCE((value::text)::boolean, true) INTO v_wallet_neg_enabled
    FROM platform_settings WHERE key='wallet_negative_enabled';
  v_wallet_neg_enabled := COALESCE(v_wallet_neg_enabled, true);

  IF v_wallet_neg_enabled THEN
    SELECT COALESCE((value::text)::int, -1000) INTO v_wallet_max_neg
      FROM platform_settings WHERE key='wallet_max_negative_balance_cents';
    v_wallet_max_neg := COALESCE(v_wallet_max_neg, -1000);

    INSERT INTO client_wallets (user_id, free_balance_cents)
      VALUES (v_user_id, 0)
      ON CONFLICT (user_id) DO NOTHING;
    SELECT free_balance_cents INTO v_wallet_balance_pre
      FROM client_wallets WHERE user_id = v_user_id FOR UPDATE;
    v_wallet_balance_pre := COALESCE(v_wallet_balance_pre, 0);

    IF v_wallet_balance_pre < v_wallet_max_neg THEN
      RAISE EXCEPTION 'WALLET_BLOCKED: saldo €%, regularize antes de novos pedidos',
        ROUND(v_wallet_balance_pre/100.0, 2) USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_wallet_cents > 0 THEN
    IF v_wallet_balance_pre IS NULL THEN
      SELECT free_balance_cents INTO v_balance_check
        FROM client_wallets WHERE user_id = v_user_id FOR UPDATE;
    ELSE
      v_balance_check := v_wallet_balance_pre;
    END IF;
    IF GREATEST(v_balance_check, 0) < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%',
        COALESCE(v_balance_check, 0), v_wallet_cents USING ERRCODE='23514';
    END IF;
  END IF;

  --╔══BEGIN_ERRAND_BRANCH══╗
  IF v_service_type = 'errand' THEN
    DECLARE
      v_e_avail BOOLEAN;
      v_e_speed TEXT := COALESCE(p_input->>'errand_speed', 'normal');
      v_e_home_stop BOOLEAN := COALESCE((p_input->>'errand_home_stop')::boolean, false);
      v_e_has_purchase BOOLEAN := COALESCE((p_input->>'errand_has_purchase')::boolean, false);
      v_e_est_cents INTEGER := COALESCE((p_input->>'errand_estimated_purchase_cents')::integer, 0);
      v_e_hs_reason TEXT := p_input->>'errand_home_stop_reason';
      v_e_hs_cash INTEGER := COALESCE((p_input->>'errand_home_stop_cash_cents')::integer, 0);
      v_e_desc TEXT := p_input->>'errand_description';
      v_e_loc TEXT := p_input->>'errand_location';
      v_e_loc_lat DOUBLE PRECISION := NULLIF(p_input->>'errand_location_lat','')::DOUBLE PRECISION;
      v_e_loc_lng DOUBLE PRECISION := NULLIF(p_input->>'errand_location_lng','')::DOUBLE PRECISION;
      v_e_desc_max INTEGER;
      v_e_max_adv INTEGER;
      v_e_max_cash INTEGER;
      v_e_buf_mult NUMERIC;
      v_e_min_km NUMERIC;
      v_e_p RECORD;
      v_e_buffer NUMERIC;
      v_e_purchase_c INTEGER;
      v_e_order_id TEXT;
      v_e_settlement INTEGER := 0;
      v_e_charge_total NUMERIC;
      v_e_wallet_eur NUMERIC;
      v_e_initial_payment TEXT;
    BEGIN
      -- Kill-switch (G4)
      SELECT (value::text)::boolean INTO v_e_avail FROM platform_settings WHERE key='errand_available';
      IF v_e_avail IS NOT NULL AND v_e_avail IS FALSE THEN
        RAISE EXCEPTION 'ERRAND_DISABLED' USING ERRCODE='P0001';
      END IF;
      -- Validações errand
      IF v_e_speed NOT IN ('normal','express') THEN
        RAISE EXCEPTION 'INVALID_ERRAND_SPEED: %', v_e_speed;
      END IF;
      IF v_e_home_stop AND v_e_hs_reason IS NOT NULL
         AND v_e_hs_reason NOT IN ('receita','cartao','dinheiro','outro') THEN
        RAISE EXCEPTION 'INVALID_ERRAND_HOME_STOP_REASON: %', v_e_hs_reason;
      END IF;
      SELECT (value::text)::int INTO v_e_desc_max FROM platform_settings WHERE key='errand_description_max_chars';
      v_e_desc_max := COALESCE(v_e_desc_max, 500);
      IF v_e_desc IS NULL OR length(trim(v_e_desc)) = 0 THEN
        RAISE EXCEPTION 'ERRAND_DESCRIPTION_REQUIRED' USING ERRCODE='23502';
      END IF;
      IF length(v_e_desc) > v_e_desc_max THEN
        RAISE EXCEPTION 'ERRAND_DESCRIPTION_TOO_LONG: %>% chars', length(v_e_desc), v_e_desc_max;
      END IF;
      IF v_e_loc_lat IS NULL OR v_e_loc_lng IS NULL THEN
        RAISE EXCEPTION 'MISSING_ERRAND_LOCATION_COORDS' USING ERRCODE='23502';
      END IF;
      IF v_e_home_stop AND (v_pickup_lat IS NULL OR v_pickup_lng IS NULL) THEN
        RAISE EXCEPTION 'MISSING_PICKUP_COORDS_FOR_HOME_STOP' USING ERRCODE='23502';
      END IF;

      -- SEC-1: errand NUNCA é parceiro (ignora input do cliente)
      v_is_partner_store := FALSE;
      v_restaurant_id := NULL;

      -- SEC-2: distância vs haversine (tolerância 20%)
      v_e_min_km := public.errand_min_distance_km(p_input);
      IF v_e_min_km IS NOT NULL AND v_distance_km < (v_e_min_km * 0.8) THEN
        RAISE EXCEPTION 'ERRAND_DISTANCE_TOO_LOW: sent=%, min_haversine=%', v_distance_km, v_e_min_km
          USING ERRCODE='23514';
      END IF;

      -- S1: trava de segurança dinheiro paragem-casa (estafeta não pode ficar a perder)
      IF v_payment_method = 'cash' AND v_e_has_purchase
         AND v_e_home_stop AND v_e_hs_reason = 'dinheiro'
         AND v_e_est_cents > v_e_hs_cash THEN
        RAISE EXCEPTION 'ERRAND_CASH_INSUFFICIENT: entregue=%cents, estimativa=%cents',
          v_e_hs_cash, v_e_est_cents USING ERRCODE='23514';
      END IF;

      -- Adiantamento máximo do estafeta sem paragem-casa
      SELECT (value::text)::int INTO v_e_max_adv FROM platform_settings WHERE key='errand_max_advance_cents';
      v_e_max_adv := COALESCE(v_e_max_adv, 4000);
      IF v_e_has_purchase AND NOT v_e_home_stop AND v_e_est_cents > v_e_max_adv THEN
        RAISE EXCEPTION 'ERRAND_ADVANCE_LIMIT_EXCEEDED: estimativa=%cents > max=%cents (ativar paragem em casa)',
          v_e_est_cents, v_e_max_adv USING ERRCODE='23514';
      END IF;

      -- Pricing errand (Fase 2.A)
      v_e_purchase_c := CASE WHEN v_e_has_purchase THEN GREATEST(0, v_e_est_cents) ELSE 0 END;
      SELECT * INTO v_e_p FROM public.pricing_calculate_errand(
        v_e_speed, v_e_home_stop, v_distance_km, v_e_purchase_c
      );

      -- D4: cash > max quando há compra adiantada sem paragem-dinheiro
      SELECT (value::text)::int INTO v_e_max_cash FROM platform_settings WHERE key='max_cash_amount_cents';
      v_e_max_cash := COALESCE(v_e_max_cash, 4000);
      IF v_payment_method = 'cash' AND v_e_has_purchase
         AND NOT (v_e_home_stop AND v_e_hs_reason = 'dinheiro')
         AND ROUND(v_e_p.customer_total * 100)::int > v_e_max_cash THEN
        RAISE EXCEPTION 'ERRAND_CASH_OVER_LIMIT: forcar paragem-dinheiro (cliente=%cents > max=%cents)',
          ROUND(v_e_p.customer_total * 100)::int, v_e_max_cash USING ERRCODE='23514';
      END IF;

      -- C4: buffer errand (NUNCA charge_total × 1.15)
      SELECT (value::text)::numeric INTO v_e_buf_mult FROM platform_settings WHERE key='errand_buffer_multiplier';
      v_e_buf_mult := COALESCE(v_e_buf_mult, 1.2);
      IF v_e_has_purchase THEN
        v_e_buffer := ROUND(v_e_p.fees_total + ((v_e_est_cents/100.0) * v_e_buf_mult), 2);
      ELSE
        v_e_buffer := v_e_p.customer_total;
      END IF;

      -- Wallet (mesmo padrão das outras categorias)
      v_max_wallet_cents := ROUND(v_e_p.customer_total * 100)::INTEGER;
      IF v_wallet_cents > v_max_wallet_cents THEN
        v_wallet_cents := v_max_wallet_cents;
      END IF;
      v_e_wallet_eur := v_wallet_cents / 100.0;
      v_e_charge_total := v_e_p.customer_total - v_e_wallet_eur;

      -- Settlement automático de dívida
      IF v_wallet_neg_enabled AND v_wallet_balance_pre IS NOT NULL AND v_wallet_balance_pre < 0 THEN
        v_e_settlement := -v_wallet_balance_pre;
        v_e_charge_total := v_e_charge_total + (v_e_settlement / 100.0);
        IF v_payment_already_confirmed THEN
          UPDATE client_wallets SET free_balance_cents = 0, updated_at = now()
            WHERE user_id = v_user_id;
          INSERT INTO wallet_transactions
            (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
            VALUES (v_user_id, v_e_settlement, 'settlement',
                    'previous_debt_settlement_errand', gen_random_uuid()::TEXT, 0,
                    'settle_create_order_errand_' || v_user_id::text || '_' || extract(epoch from now())::text);
        END IF;
      END IF;

      v_e_order_id := gen_random_uuid()::TEXT;
      v_e_initial_payment := CASE
        WHEN v_payment_already_confirmed THEN 'paid'
        WHEN v_e_charge_total <= 0 THEN 'paid'
        ELSE 'pending'
      END;

      -- INSERT errand. final_total e final_purchase_value FICAM NULL (Fase 2.C escreve via GUC).
      INSERT INTO orders (
        id, user_id, restaurant_id, status, payment_status,
        service_type, vendor_name, is_partner_store, apartment_delivery,
        distance_km, payment_method, bag_count,
        subtotal, delivery_fee, service_fee, platform_commission,
        driver_earnings, bag_fee, price, payment_buffer_total,
        partner_commission_visible, partner_markup_hidden, partner_service_fee_client,
        customer_name, customer_notes, client_phone,
        pickup_address, pickup_lat, pickup_lng,
        dropoff_address, dropoff_street, dropoff_city, dropoff_postal_code,
        dropoff_lat, dropoff_lng,
        items, requires_car, order_type, wallet_applied_cents, menu_credit_applied_cents,
        tokens_applied_value_cents, payment_intent_id, debt_collected_cents,
        errand_description, errand_location, errand_location_lat, errand_location_lng,
        errand_home_stop, errand_home_stop_reason, errand_home_stop_cash_cents,
        errand_speed, errand_has_purchase, errand_estimated_purchase_cents
      ) VALUES (
        v_e_order_id, v_user_id, NULL, 'created', v_e_initial_payment,
        'errand', NULL, FALSE, FALSE,
        v_distance_km, v_payment_method, 0,
        v_e_p.purchase_value, v_e_p.fees_total, 0, v_e_p.platform_commission,
        v_e_p.driver_earnings, 0, v_e_p.customer_total, v_e_buffer,
        0, 0, 0,
        p_input->>'customer_name', p_input->>'customer_notes', p_input->>'client_phone',
        p_input->>'pickup_address', v_pickup_lat, v_pickup_lng,
        p_input->>'dropoff_address', p_input->>'dropoff_street', p_input->>'dropoff_city', p_input->>'dropoff_postal_code',
        v_dropoff_lat, v_dropoff_lng,
        v_items_enriched,
        COALESCE((p_input->>'requires_car')::BOOLEAN, FALSE),
        'errand',
        v_wallet_cents, 0,
        v_token_cents, v_payment_intent_id, v_e_settlement,
        v_e_desc, v_e_loc, v_e_loc_lat, v_e_loc_lng,
        v_e_home_stop, v_e_hs_reason, v_e_hs_cash,
        v_e_speed, v_e_has_purchase, v_e_est_cents
      );

      IF v_wallet_cents > 0 THEN
        PERFORM wallet_debit_for_order(v_user_id, v_e_order_id, v_wallet_cents);
      END IF;

      RETURN jsonb_build_object(
        'order_id', v_e_order_id,
        'service_type', 'errand',
        'price', v_e_p.customer_total,
        'subtotal', v_e_p.purchase_value,
        'fees_total', v_e_p.fees_total,
        'base_fee', v_e_p.base_fee,
        'home_stop_fee', v_e_p.home_stop_fee,
        'km_extra_km', v_e_p.km_extra_km,
        'km_extra_fee', v_e_p.km_extra_fee,
        'delivery_fee', v_e_p.fees_total,
        'service_fee', 0,
        'platform_commission', v_e_p.platform_commission,
        'driver_earnings', v_e_p.driver_earnings,
        'bag_fee', 0,
        'apartment_surcharge', 0,
        'payment_buffer_total', v_e_buffer,
        'customer_total', v_e_p.customer_total,
        'purchase_estimate', v_e_p.purchase_value,
        'wallet_applied_cents', v_wallet_cents,
        'menu_credit_applied_cents', 0,
        'tokens_applied_value_cents', v_token_cents,
        'wallet_balance_pre_cents', v_wallet_balance_pre,
        'wallet_settlement_cents', v_e_settlement,
        'debt_collected_cents', v_e_settlement,
        'charge_total', v_e_charge_total,
        'fully_paid_by_wallet', v_e_charge_total <= 0,
        'payment_status', v_e_initial_payment,
        'takeaway_pickup_code', NULL,
        'restaurant_id', NULL
      );
    END;
  END IF;
  --╚══END_ERRAND_BRANCH══╝

  IF v_service_type IN ('restaurant','storeShopping','takeaway')
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

    -- T1 (2026-06-11): somar price_add das opções escolhidas (toppings/extras).
    v_items_in := COALESCE(p_input->'items', '[]'::jsonb);
    IF jsonb_typeof(v_items_in) = 'array' AND jsonb_array_length(v_items_in) > 0 THEN
      v_items_enriched := '[]'::jsonb;
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_in)
      LOOP
        IF jsonb_typeof(v_item->'selected_options') = 'array'
           AND jsonb_array_length(v_item->'selected_options') > 0 THEN
          SELECT t.extras_total, t.options_priced INTO v_line_extras, v_line_priced
            FROM public.order_line_options_extras(
              v_item->>'productId', v_item->'selected_options') t;
          IF v_line_extras > 0 THEN
            v_subtotal_server := v_subtotal_server
              + (v_line_extras * COALESCE((v_item->>'quantity')::NUMERIC, 1));
          END IF;
          v_item := v_item || jsonb_build_object('selected_options_priced', v_line_priced);
        END IF;
        v_items_enriched := v_items_enriched || jsonb_build_array(v_item);
      END LOOP;
    END IF;

    IF NOT v_is_partner_store AND NOT v_is_takeaway THEN
      v_subtotal_server := v_subtotal_server * 1.15;
    END IF;
    v_subtotal_server := ROUND(v_subtotal_server::numeric, 2);
  ELSE
    v_subtotal_server := ROUND(v_subtotal_input::numeric, 2);
  END IF;

  IF v_is_takeaway THEN
    v_delivery_fee        := 0;
    v_service_fee         := 0;
    v_platform_commission := ROUND(v_subtotal_server * 0.10, 2);
    v_driver_earnings     := 0;
    v_customer_total      := v_subtotal_server;
    v_partner_markup      := ROUND(v_subtotal_server * 0.05, 2);
    v_bag_fee             := 0;
  ELSE
    SELECT * INTO v_pricing FROM pricing_calculate(
      v_service_type, v_subtotal_server, v_distance_km,
      v_is_partner_store, v_apartment_delivery, FALSE, v_bag_count
    );
    v_delivery_fee        := v_pricing.delivery_fee;
    v_service_fee         := v_pricing.service_fee;
    v_platform_commission := v_pricing.platform_commission;
    v_driver_earnings     := v_pricing.driver_earnings;
    v_customer_total      := v_pricing.customer_total;
    v_partner_markup      := v_pricing.partner_markup_hidden;
    v_bag_fee             := v_pricing.bag_fee;
  END IF;

  -- B3a (2026-06-12): cap de pagamento com tokens — máx token_payment_max_pct
  -- (50%) do total do pedido, validado server-side (o UI também limita).
  -- total(EUR) × pct = cents (ex.: €10 × 50 = 500 cents = €5).
  IF v_token_cents > 0 THEN
    SELECT (value::text)::NUMERIC INTO v_token_max_pct
      FROM platform_settings WHERE key = 'token_payment_max_pct';
    v_token_max_pct := COALESCE(v_token_max_pct, 50);
    v_token_cap_cents := FLOOR(v_customer_total * v_token_max_pct)::INTEGER;
    IF v_token_cents > v_token_cap_cents THEN
      RAISE EXCEPTION 'token_cap_exceeded: tokens_cents=% > max_cents=% (pct=%, total=%)',
        v_token_cents, v_token_cap_cents, v_token_max_pct, v_customer_total
        USING ERRCODE = '23514';
    END IF;
  END IF;

  v_max_wallet_cents := ROUND(v_customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN
    v_wallet_cents := v_max_wallet_cents;
  END IF;
  v_wallet_eur := v_wallet_cents / 100.0;

  v_order_id := gen_random_uuid()::TEXT;

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

  v_charge_total := v_customer_total - v_wallet_eur - (v_credit_cents / 100.0);

  IF v_wallet_neg_enabled AND v_wallet_balance_pre IS NOT NULL AND v_wallet_balance_pre < 0 THEN
    v_settlement_cents := -v_wallet_balance_pre;
    v_charge_total := v_charge_total + (v_settlement_cents / 100.0);

    IF v_payment_already_confirmed THEN
      UPDATE client_wallets SET free_balance_cents = 0, updated_at = now()
        WHERE user_id = v_user_id;
      INSERT INTO wallet_transactions
        (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
        VALUES (v_user_id, v_settlement_cents, 'settlement',
                'previous_debt_settlement', v_order_id, 0,
                'settle_create_order_' || v_order_id);
    END IF;
  END IF;

  IF v_is_takeaway THEN
    v_buffer_total := v_charge_total;
  ELSIF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_charge_total * 1.15)::numeric, 2);
  ELSE
    v_buffer_total := v_charge_total;
  END IF;

  v_initial_payment_status := CASE
    WHEN v_payment_already_confirmed THEN 'paid'
    WHEN v_charge_total <= 0 THEN 'paid'
    ELSE 'pending'
  END;

  IF v_is_takeaway THEN
    v_takeaway_pickup_code := UPPER(SUBSTRING(MD5(v_order_id) FROM 1 FOR 6));
  END IF;

  INSERT INTO orders (
    id, user_id, restaurant_id, status, payment_status,
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
    tokens_applied_value_cents,
    payment_intent_id, debt_collected_cents,
    takeaway_is_curbside, takeaway_curbside_info, takeaway_pickup_code
  ) VALUES (
    v_order_id, v_user_id, v_restaurant_id, 'created', v_initial_payment_status,
    v_service_type, v_vendor_name, v_is_partner_store, v_apartment_delivery,
    v_distance_km, v_payment_method, v_bag_count,
    v_subtotal_server, v_delivery_fee, v_service_fee, v_platform_commission,
    v_driver_earnings, v_bag_fee, v_customer_total, v_customer_total, v_buffer_total,
    CASE WHEN v_is_partner_store THEN v_platform_commission ELSE 0 END,
    v_partner_markup,
    CASE WHEN v_is_partner_store AND NOT v_is_takeaway THEN v_service_fee ELSE 0 END,
    p_input->>'customer_name', p_input->>'customer_notes', p_input->>'client_phone',
    p_input->>'pickup_address', p_input->>'pickup_street', p_input->>'pickup_city', p_input->>'pickup_postal_code',
    p_input->>'dropoff_address', p_input->>'dropoff_street', p_input->>'dropoff_city', p_input->>'dropoff_postal_code',
    v_pickup_lat, v_pickup_lng, v_dropoff_lat, v_dropoff_lng,
    v_items_enriched,
    COALESCE((p_input->>'requires_car')::BOOLEAN, FALSE),
    COALESCE(p_input->>'order_type', CASE WHEN v_is_takeaway THEN 'takeaway' ELSE 'nonPartnerPurchase' END),
    v_wallet_cents,
    v_credit_cents,
    v_token_cents,
    v_payment_intent_id,
    v_settlement_cents,
    v_takeaway_curbside,
    p_input->>'takeaway_curbside_info',
    v_takeaway_pickup_code
  );

  IF v_wallet_cents > 0 THEN
    PERFORM wallet_debit_for_order(v_user_id, v_order_id, v_wallet_cents);
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order_id,
    'price', v_customer_total,
    'subtotal', v_subtotal_server,
    'delivery_fee', v_delivery_fee,
    'service_fee', v_service_fee,
    'platform_commission', v_platform_commission,
    'driver_earnings', v_driver_earnings,
    'bag_fee', v_bag_fee,
    'apartment_surcharge', CASE WHEN v_apartment_delivery THEN 1.50 ELSE 0 END,
    'payment_buffer_total', v_buffer_total,
    'customer_total', v_customer_total,
    'partner_markup_hidden', v_partner_markup,
    'wallet_applied_cents', v_wallet_cents,
    'menu_credit_applied_cents', v_credit_cents,
    'tokens_applied_value_cents', v_token_cents,
    'wallet_balance_pre_cents', v_wallet_balance_pre,
    'wallet_settlement_cents', v_settlement_cents,
    'debt_collected_cents', v_settlement_cents,
    'charge_total', v_charge_total,
    'fully_paid_by_wallet', v_charge_total <= 0,
    'payment_status', v_initial_payment_status,
    'takeaway_pickup_code', v_takeaway_pickup_code,
    'restaurant_id', v_restaurant_id
  );
END;
$function$;
