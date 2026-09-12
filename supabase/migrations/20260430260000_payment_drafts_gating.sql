-- 20260430260000_payment_drafts_gating.sql
-- Fase 2 — BUG 1: Gate order creation behind payment confirmation.
--
-- Pattern: Stripe-first.
--   1. Cliente avança para pagamento → Edge Fn cria PaymentIntent + payment_drafts row
--   2. Stripe charge (succeeded webhook) → cria order via create_order com
--      payment_already_confirmed=TRUE
--   3. Se Stripe falha/cancela/utilizador fecha sheet → draft expira em 30min
--      e é apagado pelo pg_cron (sem order criada).
--
-- payment_drafts é a "intent inbox" (pending payments). Order só nasce em
-- payment_intent.succeeded.

BEGIN;

-- ── 1. Tabela payment_drafts ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payment_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_intent_id TEXT NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents >= 50),
  wallet_applied_cents INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 minutes'),
  used_at TIMESTAMPTZ,
  order_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_drafts_user_pending
  ON public.payment_drafts(user_id, created_at DESC)
  WHERE used_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_payment_drafts_expires
  ON public.payment_drafts(expires_at)
  WHERE used_at IS NULL;

-- RLS: owner só pode ver os seus drafts (read-only via Flutter para polling)
ALTER TABLE public.payment_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payment_drafts_owner_read ON public.payment_drafts;
CREATE POLICY payment_drafts_owner_read ON public.payment_drafts
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE só via service_role (Edge Fns + pg_cron).

-- ── 2. RPC quote_order_pricing — preço sem inserção ──────────────────────
-- Espelha a aritmética de create_order mas SEM I/O writes. Usado por
-- create-payment-intent v20 para calcular o amount Stripe.
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

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;

  -- Wallet balance check (sem FOR UPDATE — apenas leitura para quote)
  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NULL OR v_balance_check < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%',
        COALESCE(v_balance_check, 0), v_wallet_cents
        USING ERRCODE='23514';
    END IF;
  END IF;

  -- Server-trusted subtotal (mesma lógica que create_order)
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
    v_service_type, v_subtotal_server, v_distance_km,
    v_is_partner_store, v_apartment_delivery, FALSE
  );

  v_max_wallet_cents := ROUND(v_pricing.customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN
    v_wallet_cents := v_max_wallet_cents;
  END IF;
  v_wallet_eur := v_wallet_cents / 100.0;

  -- charge_total ignora menu_credit no quote (que é consumido em create_order
  -- atomicamente). Como o quote é apenas para Stripe amount, usamos o pior caso
  -- (sem menu_credit). Diferença é normalmente ≤ €5 e o webhook reconcilia.
  v_charge_total := v_pricing.customer_total - v_wallet_eur;

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
    'fully_paid_by_wallet', v_charge_total <= 0
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.quote_order_pricing(jsonb) TO authenticated;

-- ── 3. create_order v4 — payment_already_confirmed flag ──────────────────
-- Aceita flag p_input->>'payment_already_confirmed' (TRUE/FALSE).
-- Quando TRUE: payment_status='paid' direto (Stripe já cobrou).
-- Também aceita p_input->>'payment_intent_id' para gravar referência.
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
BEGIN
  -- Caller pode ser auth.uid() (cliente) OU service_role (webhook finalize).
  -- Quando service_role, p_input precisa de 'user_id' explícito.
  v_user_id := COALESCE(
    (p_input->>'user_id')::UUID,
    auth.uid()
  );
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

  -- Pre-validate wallet balance with FOR UPDATE
  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id FOR UPDATE;
    IF v_balance_check IS NULL OR v_balance_check < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%',
        COALESCE(v_balance_check, 0), v_wallet_cents
        USING ERRCODE='23514';
    END IF;
  END IF;

  -- Server-trusted subtotal
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

  -- BUG 1 (Fase 2): Se Stripe já confirmou cobrança, payment_status='paid' direto.
  v_initial_payment_status := CASE
    WHEN v_payment_already_confirmed THEN 'paid'
    WHEN v_charge_total <= 0 THEN 'paid'  -- 100% wallet/menu_credit
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

GRANT EXECUTE ON FUNCTION public.create_order(jsonb) TO authenticated, service_role;

-- ── 4. pg_cron — cleanup drafts expirados a cada 5min ────────────────────
-- Drafts não usados expiram após 30min (fix: utilizador kill app, perdeu rede).
-- DELETE simples; se Stripe entretanto cobrou, finalize chamado pelo webhook
-- já criou order (used_at NOT NULL, não apaga).
SELECT cron.unschedule('cleanup_payment_drafts')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='cleanup_payment_drafts');

SELECT cron.schedule(
  'cleanup_payment_drafts',
  '*/5 * * * *',
  $$
    DELETE FROM public.payment_drafts
    WHERE expires_at < NOW()
      AND used_at IS NULL;
  $$
);

-- ── 5. RPC admin_list_orphans — para painel admin ─────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_orphans()
  RETURNS TABLE(
    kind TEXT,
    id TEXT,
    user_id UUID,
    payment_intent_id TEXT,
    amount NUMERIC,
    age_minutes NUMERIC,
    notes TEXT
  )
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
  -- Drafts pendentes (sem order ainda)
  SELECT 'payment_draft'::TEXT AS kind,
         id::TEXT,
         user_id,
         payment_intent_id,
         (amount_cents / 100.0)::NUMERIC AS amount,
         EXTRACT(EPOCH FROM (NOW() - created_at)) / 60 AS age_minutes,
         CASE
           WHEN expires_at < NOW() THEN 'expired'
           WHEN used_at IS NOT NULL THEN 'used'
           ELSE 'pending'
         END AS notes
  FROM public.payment_drafts
  WHERE used_at IS NULL
  UNION ALL
  -- Orders cancelled_no_charge (BUG 3 marcadas)
  SELECT 'order_no_charge'::TEXT AS kind,
         id,
         user_id::UUID,
         payment_intent_id,
         total::NUMERIC AS amount,
         EXTRACT(EPOCH FROM (NOW() - created_at)) / 60 AS age_minutes,
         COALESCE(cancel_reason, 'unknown') AS notes
  FROM public.orders
  WHERE payment_status = 'cancelled_no_charge'
  ORDER BY age_minutes DESC
  LIMIT 100;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_list_orphans() TO service_role;

COMMIT;
