-- TAXA DE PEDIDO PEQUENO (2026-08-27) — PARTE APLICADA
--
-- APLICADA em producao a 2026-08-27 via MCP, em 6 migrations pequenas
-- (a Trava protege-banco obriga a separar). Este ficheiro e o consolidado.
-- A peca que FALTA vive em 20260827131000_PROPOSTA_..._pricing.sql e espera
-- o "vai" do Danilo.
--
-- Regra do Danilo, valida para TODAS as lojas e todas as categorias de
-- ENTREGA (restaurant + storeShopping, parceiro e nao-parceiro):
--   subtotal de produtos < min_order_cents  ->  cobra small_order_fee_cents
--   subtotal >= min_order_cents             ->  nao cobra nada
--
-- A taxa e RECEITA DA PLATAFORMA: nao entra no repasse do parceiro
-- (apply_order_financial_split le `subtotal`/`final_purchase_value`, nunca o
-- total; compute_partner_weekly_settlement soma `o.subtotal` e o ledger) nem
-- no ganho do estafeta (`driver_earnings` nao e tocado aqui).
--
-- NAO se aplica a: takeaway (nao ha entrega), errand, sendPackage,
-- carryGroceries (nao ha subtotal de produtos).

-- ── 1. Onde a taxa fica registada ────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS small_order_fee NUMERIC(10,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.orders.small_order_fee IS
  'Taxa de pedido pequeno cobrada ao cliente (EUR). Receita da plataforma: '
  'nao entra no repasse do parceiro nem no ganho do estafeta.';

-- ── 2. Override por loja (NULL = usa o valor global) ─────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS min_order_cents_override INTEGER,
  ADD COLUMN IF NOT EXISTS small_order_fee_cents_override INTEGER;

COMMENT ON COLUMN public.restaurants.min_order_cents_override IS
  'Minimo desta loja em centimos. NULL = usa platform_settings.min_order_cents.';
COMMENT ON COLUMN public.restaurants.small_order_fee_cents_override IS
  'Taxa desta loja em centimos. NULL = usa platform_settings.small_order_fee_cents.';

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_min_order_override_sane;
ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_min_order_override_sane
  CHECK (min_order_cents_override IS NULL
         OR (min_order_cents_override >= 0 AND min_order_cents_override <= 100000));

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_small_order_fee_override_sane;
ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_small_order_fee_override_sane
  CHECK (small_order_fee_cents_override IS NULL
         OR (small_order_fee_cents_override >= 0 AND small_order_fee_cents_override <= 2000));

-- ── 3. As chaves globais ficam identificadas no painel admin ─────────────────
UPDATE public.platform_settings
   SET category = 'fees',
       description = 'Pedido minimo sem taxa (cents). Abaixo disto o cliente paga a taxa de pedido pequeno.'
 WHERE key = 'min_order_cents';

UPDATE public.platform_settings
   SET category = 'fees',
       description = 'Taxa de pedido pequeno (cents), cobrada quando o subtotal fica abaixo do minimo.'
 WHERE key = 'small_order_fee_cents';

-- ── 4. INTERRUPTOR — nasce DESLIGADO ─────────────────────────────────────────
-- Existe porque a peca do lado do preco esta travada (ver a PROPOSTA). Sem
-- ele, o cliente mostraria uma linha que o servidor nao cobra em todos os
-- metodos de pagamento. Com ele, os dois lados acendem ao mesmo tempo.
INSERT INTO public.platform_settings (key, value, category, description)
VALUES ('small_order_fee_enabled', 'false'::jsonb, 'fees',
        'Interruptor da taxa de pedido pequeno. Fica false ate a funcao canonica de preco ser actualizada (accao humana do Danilo). Cliente e servidor acendem ao mesmo tempo.')
ON CONFLICT (key) DO NOTHING;

-- ── 5. FONTE UNICA DA VERDADE do calculo ─────────────────────────────────────
-- O cliente (Flutter) chama ESTA MESMA funcao por RPC — nao ha segunda
-- implementacao da regra em lado nenhum. Ver lib/services/small_order_fee.dart.
CREATE OR REPLACE FUNCTION public.small_order_fee_calc(
  p_service_type  TEXT,
  p_subtotal      NUMERIC,
  p_restaurant_id TEXT DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_enabled   BOOLEAN;
  v_min_cents INTEGER;
  v_fee_cents INTEGER;
BEGIN
  SELECT COALESCE((value::text)::BOOLEAN, false) INTO v_enabled
    FROM public.platform_settings WHERE key = 'small_order_fee_enabled';
  IF COALESCE(v_enabled, false) IS NOT TRUE THEN
    RETURN 0;
  END IF;

  -- So categorias de ENTREGA com subtotal de produtos.
  IF p_service_type IS NULL OR p_service_type NOT IN ('restaurant','storeShopping') THEN
    RETURN 0;
  END IF;
  IF p_subtotal IS NULL OR p_subtotal <= 0 THEN
    RETURN 0;
  END IF;

  SELECT (value::text)::INTEGER INTO v_min_cents
    FROM public.platform_settings WHERE key = 'min_order_cents';
  SELECT (value::text)::INTEGER INTO v_fee_cents
    FROM public.platform_settings WHERE key = 'small_order_fee_cents';

  -- Override por loja tem precedencia sobre o global.
  IF p_restaurant_id IS NOT NULL THEN
    SELECT COALESCE(r.min_order_cents_override,       v_min_cents),
           COALESCE(r.small_order_fee_cents_override, v_fee_cents)
      INTO v_min_cents, v_fee_cents
      FROM public.restaurants r WHERE r.id = p_restaurant_id;
  END IF;

  -- Sem configuracao valida nao se inventa taxa nenhuma.
  IF v_min_cents IS NULL OR v_fee_cents IS NULL
     OR v_min_cents <= 0 OR v_fee_cents <= 0 THEN
    RETURN 0;
  END IF;

  IF ROUND(p_subtotal * 100)::INTEGER >= v_min_cents THEN
    RETURN 0;
  END IF;

  RETURN ROUND(v_fee_cents / 100.0, 2);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.small_order_fee_calc(TEXT, NUMERIC, TEXT)
  TO anon, authenticated, service_role;

-- ── 6. Trigger: grava a linha e reconcilia o override por loja ───────────────
-- Nome comeca por `orders_aa_` de proposito: os triggers BEFORE correm por
-- ordem alfabetica e este TEM de correr antes do `orders_enforce_cash_limit`,
-- senao o tecto dos 40 EUR em dinheiro seria avaliado sobre um total ainda
-- por reconciliar.
--
-- O que ja vem no total e a taxa GLOBAL (a funcao canonica de preco nao
-- recebe o restaurant_id do create_order). Aqui recalcula-se COM override e
-- ajusta-se apenas a DIFERENCA. Loja sem override => delta 0 => nao mexe.
--
-- Excepcao deliberada: se o pedido ja chega pago por cartao (payment_status
-- 'paid' + payment_intent_id), o valor foi cobrado no Stripe ANTES de a order
-- existir, sobre a taxa global. Nesse caso nao se aplica o delta do override —
-- cobrar-se-ia um valor e registar-se-ia outro.
CREATE OR REPLACE FUNCTION public.fn_small_order_fee()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_global NUMERIC;
  v_real   NUMERIC;
  v_delta  NUMERIC;
BEGIN
  v_global := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NULL);
  v_real   := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NEW.restaurant_id);

  IF NEW.payment_status = 'paid' AND NEW.payment_intent_id IS NOT NULL THEN
    v_real := v_global;
  END IF;

  NEW.small_order_fee := COALESCE(v_real, 0);

  v_delta := ROUND((COALESCE(v_real, 0) - COALESCE(v_global, 0))::numeric, 2);
  IF v_delta = 0 THEN
    RETURN NEW;
  END IF;

  NEW.price := ROUND((COALESCE(NEW.price, 0) + v_delta)::numeric, 2);
  IF NEW.final_total IS NOT NULL THEN
    NEW.final_total := ROUND((NEW.final_total + v_delta)::numeric, 2);
  END IF;
  IF NEW.payment_buffer_total IS NOT NULL THEN
    NEW.payment_buffer_total := ROUND((NEW.payment_buffer_total + v_delta)::numeric, 2);
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS orders_aa_small_order_fee ON public.orders;
CREATE TRIGGER orders_aa_small_order_fee
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_small_order_fee();
