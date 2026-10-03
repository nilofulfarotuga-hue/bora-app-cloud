-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item A: pagamento do plano por CARTÃO (Stripe) + ativação automática.
--
-- Regra do Danilo (lote TVDE-CAMPO-01, 2026-07-03):
--   "Migration ISOLADA só em tvde_subscriptions (colunas de pagamento) +
--    Edge Function nova e separada. NÃO tocar no webhook Stripe existente."
--
-- Esta migration NÃO toca em nenhuma função de pagamento existente, nem no
-- webhook. Apenas:
--   1) adiciona colunas de pagamento a tvde_subscriptions (nullable → back-compat);
--   2) cria tvde_plan_price_cents() — preço do plano (server-side, anti-tampering);
--   3) cria tvde_activate_paid_subscription() — espelha admin_grant_subscription
--      mas para o cliente que PAGOU (chamada pela Edge Function após verificar o
--      PaymentIntent na Stripe). Idempotente por payment_intent_id.
--
-- O catálogo (14/30/60 corridas · 7/15/30 dias · daily=2 · preços em
-- platform_settings) é EXATAMENTE o de admin_grant_subscription — fonte única.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) Colunas de pagamento (só em tvde_subscriptions) ─────────────────────────
ALTER TABLE public.tvde_subscriptions
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS paid_amount_cents         INTEGER,
  ADD COLUMN IF NOT EXISTS payment_status            TEXT,
  ADD COLUMN IF NOT EXISTS activated_via             TEXT NOT NULL DEFAULT 'admin';

COMMENT ON COLUMN public.tvde_subscriptions.stripe_payment_intent_id IS
  'PaymentIntent Stripe que pagou este plano (NULL = concedido pelo admin).';
COMMENT ON COLUMN public.tvde_subscriptions.activated_via IS
  'admin (concedido) | stripe (pago pelo cliente).';

-- Idempotência: um PaymentIntent só pode ativar UMA subscrição (retry-safe).
CREATE UNIQUE INDEX IF NOT EXISTS uq_tvde_subs_payment_intent
  ON public.tvde_subscriptions (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- 2) Preço do plano (server-side — a Edge Function usa isto para criar o PI, o
--    cliente NUNCA envia o valor) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tvde_plan_price_cents(p_plan TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_price INT;
BEGIN
  IF p_plan = 'semanal' THEN
    v_price := (public.get_setting('tvde_plan_weekly_cents')   #>> '{}')::int;
  ELSIF p_plan = 'quinzenal' THEN
    v_price := (public.get_setting('tvde_plan_biweekly_cents') #>> '{}')::int;
  ELSIF p_plan = 'mensal' THEN
    v_price := (public.get_setting('tvde_plan_monthly_cents')  #>> '{}')::int;
  ELSE
    RAISE EXCEPTION 'invalid_plan: %', p_plan;
  END IF;
  IF v_price IS NULL OR v_price < 50 THEN
    RAISE EXCEPTION 'plan_price_unset_or_too_small: %', p_plan;
  END IF;
  RETURN v_price;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tvde_plan_price_cents(TEXT) TO authenticated, service_role;

-- 3) Ativação após pagamento verificado (chamada pela Edge Function) ──────────
--    Espelha admin_grant_subscription; diferença: activated_via='stripe',
--    guarda o PaymentIntent + valor pago, granted_by = NULL. Idempotente.
CREATE OR REPLACE FUNCTION public.tvde_activate_paid_subscription(
  p_client_id            UUID,
  p_plan                 TEXT,
  p_payment_intent_id    TEXT,
  p_paid_cents           INTEGER
)
RETURNS public.tvde_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rides_total INT; v_days INT; v_price INT;
  v_daily INT := (public.get_setting('tvde_plan_daily_included') #>> '{}')::int;
  v_sub public.tvde_subscriptions;
BEGIN
  IF p_client_id IS NULL THEN RAISE EXCEPTION 'client_id_required'; END IF;
  IF p_payment_intent_id IS NULL OR length(p_payment_intent_id) = 0 THEN
    RAISE EXCEPTION 'payment_intent_required';
  END IF;

  -- Idempotência: se este PaymentIntent já ativou uma subscrição, devolve-a.
  SELECT * INTO v_sub FROM public.tvde_subscriptions
    WHERE stripe_payment_intent_id = p_payment_intent_id LIMIT 1;
  IF FOUND THEN RETURN v_sub; END IF;

  IF p_plan = 'semanal' THEN
    v_rides_total := 14; v_days := 7;
  ELSIF p_plan = 'quinzenal' THEN
    v_rides_total := 30; v_days := 15;
  ELSIF p_plan = 'mensal' THEN
    v_rides_total := 60; v_days := 30;
  ELSE
    RAISE EXCEPTION 'invalid_plan: %', p_plan;
  END IF;

  v_price := public.tvde_plan_price_cents(p_plan);

  -- Defesa em profundidade: o valor pago tem de cobrir o preço do plano.
  IF p_paid_cents IS NULL OR p_paid_cents < v_price THEN
    RAISE EXCEPTION 'paid_below_plan_price: paid=% price=%', p_paid_cents, v_price;
  END IF;

  IF v_daily IS NULL OR v_daily < 1 THEN v_daily := 2; END IF;

  -- Desativa a subscrição ativa anterior (mesma regra do admin_grant).
  UPDATE public.tvde_subscriptions SET active = false
    WHERE client_id = p_client_id AND active = true;

  INSERT INTO public.tvde_subscriptions
    (client_id, plan, rides_total, daily_included, price_cents,
     granted_by, starts_at, ends_at, active,
     stripe_payment_intent_id, paid_amount_cents, payment_status, activated_via)
  VALUES
    (p_client_id, p_plan, v_rides_total, v_daily, v_price,
     NULL, now(), now() + (v_days || ' days')::interval, true,
     p_payment_intent_id, p_paid_cents, 'paid', 'stripe')
  RETURNING * INTO v_sub;

  RETURN v_sub;
END;
$$;

-- Só a Edge Function (service_role) ativa; o cliente nunca chama diretamente.
REVOKE ALL ON FUNCTION
  public.tvde_activate_paid_subscription(UUID, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  public.tvde_activate_paid_subscription(UUID, TEXT, TEXT, INTEGER) TO service_role;
