-- Ronda de correções 04/10/2026 · agente checkout
-- Parte da definição EM PRODUÇÃO (pg_get_functiondef) de cada função, não do repo.
--
-- 1. quote_order_pricing aceita 'takeaway' (Ir buscar), igual ao ramo takeaway do
--    create_order: sem entrega, sem taxa de serviço, sem saco, sem markup; total =
--    subtotal. Antes recusava com INVALID_SERVICE_TYPE — o cartão em takeaway (que
--    passa pelo quote dentro do create-payment-intent) nunca funcionava.
-- 2. O markup do não-parceiro (×1.15) deixa de estar cravado: lê
--    platform_settings.non_partner_markup_pct (já existia, = 0.15). O buffer de
--    pré-autorização do não-parceiro (×1.15) lê a chave nova
--    non_partner_payment_buffer_multiplier (nasce com o valor de hoje, 1.15).
-- 3. Limite de dinheiro: o gatilho enforce_cash_payment_limit lê
--    platform_settings.max_cash_amount_cents (antes `> 40` cravado). Takeaway
--    ("Pagar na loja") fica fora do limite, como a app sempre disse ao cliente:
--    não há estafeta a transportar o dinheiro.
-- 4. create_order grava orders.deixar_a_porta a partir do input ("Deixar à porta").
-- 5. Pedido do agente parceiro: create_order (e o quote, para o cartão não cobrar
--    antes de falhar) recusa loja em pausa (restaurants.pausa_ate > now()). Lido
--    por to_jsonb(r) para não partir enquanto a coluna não existir.
-- 6. O quote resolve a loja também pelo vendor_name (como o create_order), para o
--    is_partner e a taxa de pedido pequeno saírem iguais.

INSERT INTO public.platform_settings (key, value, description)
VALUES ('non_partner_payment_buffer_multiplier', '1.15'::jsonb,
        'Multiplicador da pré-autorização (cartão/MB Way) dos pedidos de loja NÃO-parceira, para cobrir diferenças de preço na loja. O que sobra é devolvido.')
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Gatilho do limite de dinheiro
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_cash_payment_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_total     NUMERIC;
  v_max_cents INTEGER;
BEGIN
  IF NEW.payment_method IS DISTINCT FROM 'cash' THEN RETURN NEW; END IF;
  -- "Ir buscar": paga-se na loja, sem estafeta a levar dinheiro.
  IF NEW.service_type = 'takeaway' THEN RETURN NEW; END IF;
  SELECT (value::text)::INTEGER INTO v_max_cents
    FROM public.platform_settings WHERE key = 'max_cash_amount_cents';
  v_max_cents := COALESCE(v_max_cents, 4000);
  v_total := COALESCE(NEW.final_total, NEW.price, 0);
  IF ROUND(v_total * 100) > v_max_cents THEN
    RAISE EXCEPTION 'CASH_LIMIT_EXCEEDED: pagamento em dinheiro disponivel apenas ate % EUR (pedido = % EUR)',
      ROUND(v_max_cents / 100.0, 2), v_total
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1, 2, 5, 6. quote_order_pricing
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.quote_order_pricing(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_service_type TEXT;
  v_distance_km NUMERIC;
  v_is_partner_store BOOLEAN;
  v_apartment_delivery BOOLEAN;
  v_subtotal_input NUMERIC;
  v_subtotal_server NUMERIC;
  v_pricing RECORD;
  v_product_lines JSONB;
  v_line JSONB;
  v_wallet_cents INTEGER;
  v_wallet_eur NUMERIC;
  v_charge_total NUMERIC;
  v_max_wallet_cents INTEGER;
  v_balance_check INTEGER;
  v_buffer_total NUMERIC;
  v_include_debt BOOLEAN;
  v_debt_cents INTEGER := 0;
  v_items_in JSONB;
  v_item JSONB;
  v_line_extras NUMERIC;
  v_line_priced JSONB;
  v_small_order_fee NUMERIC := 0;
  v_customer_total NUMERIC;
  -- 04/10/2026
  v_is_takeaway BOOLEAN;
  v_restaurant_id TEXT;
  v_markup NUMERIC;
  v_buffer_mult NUMERIC;
  v_pausa_ate TIMESTAMPTZ;
  -- parcelas devolvidas (o record v_pricing não existe em takeaway)
  v_delivery_fee NUMERIC := 0;
  v_service_fee NUMERIC := 0;
  v_platform_commission NUMERIC := 0;
  v_driver_earnings NUMERIC := 0;
  v_bag_fee NUMERIC := 0;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  v_service_type       := COALESCE(p_input->>'service_type', '');
  v_distance_km        := COALESCE((p_input->>'distance_km')::NUMERIC, 1);
  v_is_partner_store   := COALESCE((p_input->>'is_partner_store')::BOOLEAN, FALSE);
  v_apartment_delivery := COALESCE((p_input->>'apartment_delivery')::BOOLEAN, FALSE);
  v_subtotal_input     := COALESCE((p_input->>'subtotal')::NUMERIC, 0);
  v_product_lines      := p_input->'product_lines';
  v_wallet_cents       := COALESCE((p_input->>'wallet_applied_cents')::INTEGER, 0);
  v_include_debt       := COALESCE((p_input->>'include_debt')::BOOLEAN, FALSE);
  v_is_takeaway        := (v_service_type = 'takeaway');

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage','errand','takeaway') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;

  -- 04/10: percentagens das definições, nunca cravadas.
  SELECT (value::text)::NUMERIC INTO v_markup
    FROM public.platform_settings WHERE key = 'non_partner_markup_pct';
  v_markup := COALESCE(v_markup, 0.15);
  SELECT (value::text)::NUMERIC INTO v_buffer_mult
    FROM public.platform_settings WHERE key = 'non_partner_payment_buffer_multiplier';
  v_buffer_mult := COALESCE(v_buffer_mult, 1.15);

  -- 04/10: loja pelo id ou, como no create_order, pelo nome.
  v_restaurant_id := NULLIF(p_input->>'restaurant_id', '');
  IF v_restaurant_id IS NULL AND NULLIF(p_input->>'vendor_name', '') IS NOT NULL
     AND v_service_type IN ('restaurant','storeShopping','takeaway') THEN
    SELECT id INTO v_restaurant_id FROM public.restaurants
      WHERE name = p_input->>'vendor_name' LIMIT 1;
  END IF;

  --╔══BEGIN_SEC_HARDENING_QUOTE══╗
  -- SEC-1 (Tarefa 1): is_partner_store NUNCA vem do input para carry/send;
  -- para restaurant/storeShopping/takeaway faz-se lookup server-side em restaurants
  -- quando a loja é conhecida. Errand já força FALSE no seu branch.
  IF v_service_type IN ('carryGroceries','sendPackage') THEN
    v_is_partner_store := FALSE;
  ELSIF v_service_type IN ('restaurant','storeShopping','takeaway') AND v_restaurant_id IS NOT NULL THEN
    SELECT is_partner INTO v_is_partner_store FROM public.restaurants WHERE id = v_restaurant_id;
    v_is_partner_store := COALESCE(v_is_partner_store, FALSE);
  END IF;
  -- SEC-2 (Tarefa 1): distance_km validada vs haversine real. Se as coordenadas
  -- necessárias não estiverem no input, é um quote-preview puro (skip).
  DECLARE
    v_min_km_q NUMERIC;
    v_r_lat_q DOUBLE PRECISION;
    v_r_lng_q DOUBLE PRECISION;
    v_p_lat_q DOUBLE PRECISION := NULLIF(p_input->>'pickup_lat','')::DOUBLE PRECISION;
    v_p_lng_q DOUBLE PRECISION := NULLIF(p_input->>'pickup_lng','')::DOUBLE PRECISION;
    v_d_lat_q DOUBLE PRECISION := NULLIF(p_input->>'dropoff_lat','')::DOUBLE PRECISION;
    v_d_lng_q DOUBLE PRECISION := NULLIF(p_input->>'dropoff_lng','')::DOUBLE PRECISION;
  BEGIN
    IF v_service_type IN ('restaurant','storeShopping') AND v_restaurant_id IS NOT NULL THEN
      SELECT lat, lng INTO v_r_lat_q, v_r_lng_q FROM public.restaurants WHERE id = v_restaurant_id;
      IF v_r_lat_q IS NOT NULL AND v_r_lng_q IS NOT NULL AND v_d_lat_q IS NOT NULL AND v_d_lng_q IS NOT NULL THEN
        v_min_km_q := public._haversine_km(v_r_lat_q::numeric, v_r_lng_q::numeric, v_d_lat_q::numeric, v_d_lng_q::numeric);
      END IF;
    ELSIF v_service_type IN ('carryGroceries','sendPackage') THEN
      IF v_p_lat_q IS NOT NULL AND v_p_lng_q IS NOT NULL AND v_d_lat_q IS NOT NULL AND v_d_lng_q IS NOT NULL THEN
        v_min_km_q := public._haversine_km(v_p_lat_q::numeric, v_p_lng_q::numeric, v_d_lat_q::numeric, v_d_lng_q::numeric);
      END IF;
    END IF;
    IF v_min_km_q IS NOT NULL AND v_distance_km < (v_min_km_q * 0.8) THEN
      RAISE EXCEPTION 'DISTANCE_MISMATCH: sent=%, min_haversine=%', v_distance_km, v_min_km_q USING ERRCODE='23514';
    END IF;
  END;
  --╚══END_SEC_HARDENING_QUOTE══╝

  -- 04/10 (pedido do agente parceiro): loja em pausa não recebe pedidos.
  IF v_restaurant_id IS NOT NULL THEN
    SELECT NULLIF(to_jsonb(r)->>'pausa_ate', '')::timestamptz INTO v_pausa_ate
      FROM public.restaurants r WHERE r.id = v_restaurant_id;
    IF v_pausa_ate IS NOT NULL AND v_pausa_ate > now() THEN
      RAISE EXCEPTION 'STORE_PAUSED: loja em pausa ate %', v_pausa_ate USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- 04/10: "Ir buscar" — mesmas regras do ramo takeaway do create_order.
  IF v_is_takeaway THEN
    IF NOT v_is_partner_store THEN
      RAISE EXCEPTION 'TAKEAWAY_REQUIRES_PARTNER';
    END IF;
    IF v_restaurant_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.restaurants WHERE id = v_restaurant_id AND takeaway_enabled = true
    ) THEN
      RAISE EXCEPTION 'TAKEAWAY_NOT_ENABLED: partner % does not accept takeaway', v_restaurant_id;
    END IF;
  END IF;

  -- BRANCH ERRAND
  IF v_service_type = 'errand' THEN
    DECLARE
      v_speed TEXT := COALESCE(p_input->>'errand_speed', 'normal');
      v_home_stop BOOLEAN := COALESCE((p_input->>'errand_home_stop')::boolean, false);
      v_has_purchase BOOLEAN := COALESCE((p_input->>'errand_has_purchase')::boolean, false);
      v_est_cents INTEGER := COALESCE((p_input->>'errand_estimated_purchase_cents')::integer, 0);
      v_buf_mult NUMERIC := COALESCE((get_setting('errand_buffer_multiplier')::text)::numeric, 1.2);
      v_min_km NUMERIC;
      v_e RECORD;
      v_buffer NUMERIC;
      v_purchase_c INTEGER;
    BEGIN
      v_is_partner_store := FALSE; -- SEC-1
      v_min_km := public.errand_min_distance_km(p_input);
      IF v_min_km IS NOT NULL AND v_distance_km < (v_min_km * 0.8) THEN
        RAISE EXCEPTION 'ERRAND_DISTANCE_TOO_LOW: sent=%, min_haversine=%', v_distance_km, v_min_km USING ERRCODE = '23514';
      END IF;
      v_purchase_c := CASE WHEN v_has_purchase THEN GREATEST(0, v_est_cents) ELSE 0 END;
      SELECT * INTO v_e FROM public.pricing_calculate_errand(v_speed, v_home_stop, v_distance_km, v_purchase_c);
      IF v_has_purchase THEN
        v_buffer := ROUND(v_e.fees_total + ((v_est_cents / 100.0) * v_buf_mult), 2);
      ELSE
        v_buffer := v_e.customer_total;
      END IF;
      RETURN jsonb_build_object(
        'service_type','errand','price', v_e.customer_total, 'subtotal', v_e.purchase_value,
        'base_fee', v_e.base_fee, 'home_stop_fee', v_e.home_stop_fee,
        'km_extra_km', v_e.km_extra_km, 'km_extra_fee', v_e.km_extra_fee,
        'fees_total', v_e.fees_total, 'purchase_estimate', v_e.purchase_value,
        'delivery_fee', v_e.fees_total, 'service_fee', 0,
        'platform_commission', v_e.platform_commission, 'driver_earnings', v_e.driver_earnings,
        'bag_fee', 0, 'apartment_surcharge', 0,
        'small_order_fee', 0,
        'payment_buffer_total', v_buffer, 'customer_total', v_e.customer_total,
        'wallet_applied_cents', 0, 'charge_total', v_e.customer_total,
        'fully_paid_by_wallet', false, 'debt_settle_cents', 0
      );
    END;
  END IF;

  -- LÓGICA ORIGINAL ABAIXO (markup/buffer passam a vir das definições; takeaway somado)
  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NULL OR v_balance_check < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%', COALESCE(v_balance_check, 0), v_wallet_cents USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_service_type IN ('restaurant','storeShopping','takeaway')
     AND v_product_lines IS NOT NULL
     AND jsonb_typeof(v_product_lines) = 'array'
     AND jsonb_array_length(v_product_lines) > 0
  THEN
    v_subtotal_server := 0;
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_product_lines) LOOP
      -- F1 (2026-08-16): unitario arredondado AO CENTIMO no markup; linha =
      -- round(unit,2) x qtd; subtotal = soma das linhas (igual ao que o cliente ve).
      v_subtotal_server := v_subtotal_server + (
        CASE WHEN NOT v_is_partner_store AND NOT v_is_takeaway THEN
          ROUND((COALESCE(
            (SELECT p.price FROM products p WHERE p.id = (v_line->>'product_id') LIMIT 1),
            (v_line->>'unit_price')::NUMERIC, 0) * (1 + v_markup))::numeric, 2)
        ELSE
          COALESCE(
            (SELECT p.price FROM products p WHERE p.id = (v_line->>'product_id') LIMIT 1),
            (v_line->>'unit_price')::NUMERIC, 0)
        END * COALESCE((v_line->>'quantity')::NUMERIC, 1)
      );
    END LOOP;
    v_items_in := COALESCE(p_input->'items', '[]'::jsonb);
    IF jsonb_typeof(v_items_in) = 'array' AND jsonb_array_length(v_items_in) > 0 THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_items_in) LOOP
        IF jsonb_typeof(v_item->'selected_options') = 'array'
           AND jsonb_array_length(v_item->'selected_options') > 0 THEN
          SELECT t.extras_total, t.options_priced INTO v_line_extras, v_line_priced
            FROM public.order_line_options_extras(v_item->>'productId', v_item->'selected_options') t;
          IF v_line_extras > 0 THEN
            v_subtotal_server := v_subtotal_server
              + (CASE WHEN NOT v_is_partner_store AND NOT v_is_takeaway
                      THEN ROUND((v_line_extras * (1 + v_markup))::numeric, 2)
                      ELSE v_line_extras END
                 * COALESCE((v_item->>'quantity')::NUMERIC, 1));
          END IF;
        END IF;
      END LOOP;
    END IF;
    v_subtotal_server := ROUND(v_subtotal_server::numeric, 2);
  ELSE
    v_subtotal_server := ROUND(v_subtotal_input::numeric, 2);
  END IF;

  IF v_is_takeaway THEN
    -- Igual ao create_order: o cliente paga só os produtos.
    v_customer_total := v_subtotal_server;
    v_platform_commission := ROUND(v_subtotal_server
      - public.partner_store_share(v_subtotal_server)
      - ROUND(public.partner_store_share(v_subtotal_server)
          * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings
                       WHERE key = 'partner_hidden_markup_pct'), 0.05), 2), 2);
  ELSE
    SELECT * INTO v_pricing FROM pricing_calculate(
      v_service_type, v_subtotal_server, v_distance_km, v_is_partner_store, v_apartment_delivery, FALSE
    );
    v_delivery_fee        := v_pricing.delivery_fee;
    v_service_fee         := v_pricing.service_fee;
    v_platform_commission := v_pricing.platform_commission;
    v_driver_earnings     := v_pricing.driver_earnings;
    v_bag_fee             := v_pricing.bag_fee;

    -- TAXA DE PEDIDO PEQUENO (2026-08-27). Devolve 0 se o interruptor
    -- small_order_fee_enabled estiver desligado; com a loja, igual ao create_order
    -- (parceiro nao leva taxa).
    v_small_order_fee := COALESCE(
      public.small_order_fee_calc(v_service_type, v_subtotal_server, v_restaurant_id), 0);
    v_customer_total := ROUND((v_pricing.customer_total + v_small_order_fee)::numeric, 2);
  END IF;

  v_max_wallet_cents := ROUND(v_customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN v_wallet_cents := v_max_wallet_cents; END IF;
  v_wallet_eur := v_wallet_cents / 100.0;
  v_charge_total := v_customer_total - v_wallet_eur;

  IF v_include_debt THEN
    SELECT free_balance_cents INTO v_balance_check FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NOT NULL AND v_balance_check < 0 THEN
      v_debt_cents := -v_balance_check;
      v_charge_total := v_charge_total + (v_debt_cents::numeric / 100);
    END IF;
  END IF;

  IF v_is_takeaway THEN
    v_buffer_total := v_charge_total;
  ELSIF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_charge_total * v_buffer_mult)::numeric, 2);
  ELSE
    v_buffer_total := v_charge_total;
  END IF;

  RETURN jsonb_build_object(
    'service_type', v_service_type,
    'price', v_customer_total, 'subtotal', v_subtotal_server,
    'delivery_fee', v_delivery_fee, 'service_fee', v_service_fee,
    'platform_commission', v_platform_commission, 'driver_earnings', v_driver_earnings,
    'bag_fee', v_bag_fee,
    'apartment_surcharge', CASE WHEN v_apartment_delivery AND NOT v_is_takeaway THEN 1.50 ELSE 0 END,
    'small_order_fee', v_small_order_fee,
    'payment_buffer_total', v_buffer_total, 'customer_total', v_customer_total,
    'wallet_applied_cents', v_wallet_cents, 'charge_total', v_charge_total,
    'fully_paid_by_wallet', v_charge_total <= 0, 'debt_settle_cents', v_debt_cents,
    'restaurant_id', v_restaurant_id
  );
END; $function$;

