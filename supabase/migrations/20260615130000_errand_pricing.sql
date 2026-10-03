-- ═══════════════════════════════════════════════════════════════════════════
-- FAVORES (errand) — Fase 2.A: cálculo de preço
-- C2: pricing_calculate fica INTACTA (byte-a-byte garantido por NÃO-modificação).
--     O cálculo errand vive numa função dedicada (pricing_calculate_errand) +
--     branch errand em quote_order_pricing (e create_order na Fase 2.B).
--     Racional: pricing_calculate não recebe speed/home_stop/purchase; adicionar
--     params criaria overload ambíguo p/ as chamadas existentes de 6 args. Função
--     isolada = zero risco para restaurant/storeShopping/carryGroceries/sendPackage.
-- C1: estende quote_order_pricing (não duplica) — 'errand' no allowlist + branch.
-- C3: SEC-1 (is_partner_store forçado false) + SEC-2 (distance vs haversine, tol. 20%).
-- C4: buffer errand = fees_total + round(estimativa × errand_buffer_multiplier),
--     NUNCA o charge_total × 1.15 do non-partner.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Helper haversine (km) — built-in math, IMMUTABLE ─────────────────────────
CREATE OR REPLACE FUNCTION public._haversine_km(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
  SELECT 6371.0 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$function$;

-- ── SEC-2: distância mínima do percurso do favor (soma de segmentos) ─────────
-- Percurso: (casa do cliente, se paragem) → local do favor → entrega.
-- Devolve NULL se faltarem coordenadas (não valida — fail-open só na validação).
CREATE OR REPLACE FUNCTION public.errand_min_distance_km(p_input jsonb)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_home_stop boolean := COALESCE((p_input->>'errand_home_stop')::boolean, false);
  v_flat numeric := (p_input->>'errand_location_lat')::numeric;
  v_flng numeric := (p_input->>'errand_location_lng')::numeric;
  v_dlat numeric := (p_input->>'dropoff_lat')::numeric;
  v_dlng numeric := (p_input->>'dropoff_lng')::numeric;
  v_hlat numeric := (p_input->>'pickup_lat')::numeric;
  v_hlng numeric := (p_input->>'pickup_lng')::numeric;
  v_total numeric;
BEGIN
  IF v_flat IS NULL OR v_flng IS NULL OR v_dlat IS NULL OR v_dlng IS NULL THEN
    RETURN NULL;
  END IF;
  v_total := public._haversine_km(v_flat, v_flng, v_dlat, v_dlng);
  IF v_home_stop AND v_hlat IS NOT NULL AND v_hlng IS NOT NULL THEN
    v_total := v_total + public._haversine_km(v_hlat, v_hlng, v_flat, v_flng);
  END IF;
  RETURN v_total;
END;
$function$;

-- ── Cálculo de preço do favor (tabela errand; 1:1 na compra, SEM ×1.15) ──────
-- Trabalha em cents (inteiros) e converte no fim → bate ao cêntimo (Exemplos A/B/C).
CREATE OR REPLACE FUNCTION public.pricing_calculate_errand(
  p_speed          text,
  p_home_stop      boolean,
  p_distance_km    numeric,
  p_purchase_cents integer DEFAULT 0
)
RETURNS TABLE(
  base_fee numeric, home_stop_fee numeric, km_extra_km numeric, km_extra_fee numeric,
  fees_total numeric, driver_earnings numeric, platform_commission numeric,
  purchase_value numeric, customer_total numeric
)
LANGUAGE plpgsql STABLE
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_settings    jsonb;
  c_fee_normal  INTEGER; c_fee_express INTEGER;
  c_drv_normal  INTEGER; c_drv_express INTEGER;
  c_home_fee    INTEGER; c_home_drv    INTEGER;
  c_base_dist   NUMERIC;
  c_per_km      INTEGER; c_drv_per_km  INTEGER;
  v_speed       TEXT;
  v_dist        NUMERIC; v_extra_km    NUMERIC;
  v_base_c      INTEGER; v_drv_base_c  INTEGER;
  v_home_fee_c  INTEGER; v_home_drv_c  INTEGER;
  v_km_fee_c    INTEGER; v_km_drv_c    INTEGER;
  v_fees_c      INTEGER; v_driver_c    INTEGER; v_platform_c INTEGER; v_purchase_c INTEGER;
BEGIN
  SELECT jsonb_object_agg(key, value) INTO v_settings FROM platform_settings;

  c_fee_normal  := (v_settings->>'errand_fee_normal_cents')::INTEGER;
  c_fee_express := (v_settings->>'errand_fee_express_cents')::INTEGER;
  c_drv_normal  := (v_settings->>'errand_driver_normal_cents')::INTEGER;
  c_drv_express := (v_settings->>'errand_driver_express_cents')::INTEGER;
  c_home_fee    := (v_settings->>'errand_home_stop_fee_cents')::INTEGER;
  c_home_drv    := (v_settings->>'errand_home_stop_driver_cents')::INTEGER;
  c_base_dist   := (v_settings->>'errand_base_distance_km')::NUMERIC;
  c_per_km      := (v_settings->>'errand_per_km_cents')::INTEGER;
  c_drv_per_km  := (v_settings->>'errand_driver_per_km_cents')::INTEGER;

  v_speed    := CASE WHEN p_speed = 'express' THEN 'express' ELSE 'normal' END;
  v_dist     := GREATEST(0.0, COALESCE(p_distance_km, 0.0));
  v_extra_km := GREATEST(0.0, v_dist - c_base_dist);

  v_base_c     := CASE WHEN v_speed = 'express' THEN c_fee_express ELSE c_fee_normal END;
  v_drv_base_c := CASE WHEN v_speed = 'express' THEN c_drv_express ELSE c_drv_normal END;
  v_home_fee_c := CASE WHEN p_home_stop THEN c_home_fee ELSE 0 END;
  v_home_drv_c := CASE WHEN p_home_stop THEN c_home_drv ELSE 0 END;
  v_km_fee_c   := ROUND(v_extra_km * c_per_km)::INTEGER;
  v_km_drv_c   := ROUND(v_extra_km * c_drv_per_km)::INTEGER;

  v_fees_c     := v_base_c + v_home_fee_c + v_km_fee_c;
  v_driver_c   := v_drv_base_c + v_home_drv_c + v_km_drv_c;
  v_platform_c := v_fees_c - v_driver_c;
  v_purchase_c := GREATEST(0, COALESCE(p_purchase_cents, 0));

  RETURN QUERY SELECT
    (v_base_c     / 100.0)::numeric,
    (v_home_fee_c / 100.0)::numeric,
    ROUND(v_extra_km, 2),
    (v_km_fee_c   / 100.0)::numeric,
    (v_fees_c     / 100.0)::numeric,
    (v_driver_c   / 100.0)::numeric,
    (v_platform_c / 100.0)::numeric,
    (v_purchase_c / 100.0)::numeric,
    ((v_fees_c + v_purchase_c) / 100.0)::numeric;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- quote_order_pricing — recriada (CREATE OR REPLACE, MESMA assinatura p_input jsonb).
-- Mudanças vs versão actual: (1) 'errand' no allowlist; (2) branch errand que
-- retorna cedo. TODO o resto (restaurant/storeShopping/carry/send + buffer ×1.15)
-- fica IDÊNTICO ao original.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.quote_order_pricing(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id            UUID := auth.uid();
  v_service_type       TEXT;
  v_distance_km        NUMERIC;
  v_is_partner_store   BOOLEAN;
  v_apartment_delivery BOOLEAN;
  v_subtotal_input     NUMERIC;
  v_subtotal_server    NUMERIC;
  v_pricing            RECORD;
  v_product_lines      JSONB;
  v_line               JSONB;
  v_wallet_cents       INTEGER;
  v_wallet_eur         NUMERIC;
  v_charge_total       NUMERIC;
  v_max_wallet_cents   INTEGER;
  v_balance_check      INTEGER;
  v_buffer_total       NUMERIC;
  v_include_debt       BOOLEAN;
  v_debt_cents         INTEGER := 0;
  v_items_in           JSONB;
  v_item               JSONB;
  v_line_extras        NUMERIC;
  v_line_priced        JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  v_service_type       := COALESCE(p_input->>'service_type', '');
  v_distance_km        := COALESCE((p_input->>'distance_km')::NUMERIC, 1);
  v_is_partner_store   := COALESCE((p_input->>'is_partner_store')::BOOLEAN, FALSE);
  v_apartment_delivery := COALESCE((p_input->>'apartment_delivery')::BOOLEAN, FALSE);
  v_subtotal_input     := COALESCE((p_input->>'subtotal')::NUMERIC, 0);
  v_product_lines      := p_input->'product_lines';
  v_wallet_cents       := COALESCE((p_input->>'wallet_applied_cents')::INTEGER, 0);
  v_include_debt       := COALESCE((p_input->>'include_debt')::BOOLEAN, FALSE);

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage','errand') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;

  -- ── BRANCH ERRAND (Bloco 2) — cálculo próprio, retorna cedo ────────────────
  IF v_service_type = 'errand' THEN
    DECLARE
      v_speed        TEXT    := COALESCE(p_input->>'errand_speed', 'normal');
      v_home_stop    BOOLEAN := COALESCE((p_input->>'errand_home_stop')::boolean, false);
      v_has_purchase BOOLEAN := COALESCE((p_input->>'errand_has_purchase')::boolean, false);
      v_est_cents    INTEGER := COALESCE((p_input->>'errand_estimated_purchase_cents')::integer, 0);
      v_buf_mult     NUMERIC := COALESCE((get_setting('errand_buffer_multiplier')::text)::numeric, 1.2);
      v_min_km       NUMERIC;
      v_e            RECORD;
      v_buffer       NUMERIC;
      v_purchase_c   INTEGER;
    BEGIN
      -- SEC-1: errand nunca é parceiro (ignora input do cliente)
      v_is_partner_store := FALSE;

      -- SEC-2: distância nunca abaixo de 80% da linha-recta total (folga GPS/Routes)
      v_min_km := public.errand_min_distance_km(p_input);
      IF v_min_km IS NOT NULL AND v_distance_km < (v_min_km * 0.8) THEN
        RAISE EXCEPTION 'ERRAND_DISTANCE_TOO_LOW: sent=%, min_haversine=%', v_distance_km, v_min_km
          USING ERRCODE = '23514';
      END IF;

      v_purchase_c := CASE WHEN v_has_purchase THEN GREATEST(0, v_est_cents) ELSE 0 END;
      SELECT * INTO v_e FROM public.pricing_calculate_errand(
        v_speed, v_home_stop, v_distance_km, v_purchase_c
      );

      -- C4: buffer errand (NÃO ×1.15). Só relevante p/ compra adiantada (cartão/MBWay).
      IF v_has_purchase THEN
        v_buffer := ROUND(v_e.fees_total + ((v_est_cents / 100.0) * v_buf_mult), 2);
      ELSE
        v_buffer := v_e.customer_total;
      END IF;

      RETURN jsonb_build_object(
        'service_type',        'errand',
        'price',               v_e.customer_total,
        'subtotal',            v_e.purchase_value,
        'base_fee',            v_e.base_fee,
        'home_stop_fee',       v_e.home_stop_fee,
        'km_extra_km',         v_e.km_extra_km,
        'km_extra_fee',        v_e.km_extra_fee,
        'fees_total',          v_e.fees_total,
        'purchase_estimate',   v_e.purchase_value,
        'delivery_fee',        v_e.fees_total,
        'service_fee',         0,
        'platform_commission', v_e.platform_commission,
        'driver_earnings',     v_e.driver_earnings,
        'bag_fee',             0,
        'apartment_surcharge', 0,
        'payment_buffer_total',v_buffer,
        'customer_total',      v_e.customer_total,
        'wallet_applied_cents',0,
        'charge_total',        v_e.customer_total,
        'fully_paid_by_wallet',false,
        'debt_settle_cents',   0
      );
    END;
  END IF;
  -- ── FIM BRANCH ERRAND. Abaixo = lógica original INALTERADA ─────────────────

  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id;
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

    v_items_in := COALESCE(p_input->'items', '[]'::jsonb);
    IF jsonb_typeof(v_items_in) = 'array' AND jsonb_array_length(v_items_in) > 0 THEN
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
        END IF;
      END LOOP;
    END IF;

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

  v_charge_total := v_pricing.customer_total - v_wallet_eur;

  IF v_include_debt THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NOT NULL AND v_balance_check < 0 THEN
      v_debt_cents := -v_balance_check;
      v_charge_total := v_charge_total + (v_debt_cents::numeric / 100);
    END IF;
  END IF;

  IF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_charge_total * 1.15)::numeric, 2);
  ELSE
    v_buffer_total := v_charge_total;
  END IF;

  RETURN jsonb_build_object(
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
    'wallet_applied_cents', v_wallet_cents,
    'charge_total', v_charge_total,
    'fully_paid_by_wallet', v_charge_total <= 0,
    'debt_settle_cents', v_debt_cents
  );
END;
$function$;
