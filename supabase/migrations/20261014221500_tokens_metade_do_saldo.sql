-- 14/10/2026 — TOKENS DO CLIENTE: regra do Danilo + desconto que nunca chegava à cobrança.
--
-- Regra (Danilo, 14/10/2026): em cada pedido/corrida o cliente só pode usar METADE do valor
-- dos tokens que tem (tem 5 EUR em tokens -> usa no máximo 2,50 EUR). O tecto antigo
-- (token_payment_max_pct = no máximo 50% do valor do pedido) continua por cima.
--
-- Erros encontrados (caso Ana Cláudia, Goola Açaí, 14/10 — 6 tentativas MB Way recusadas):
--   1. create_order gravava tokens_applied_value_cents mas NÃO o tirava do valor a cobrar:
--      MB Way, cartão (saldo) e dinheiro cobravam o total cheio e a app gastava os tokens na mesma.
--   2. quote_order_pricing ignorava os tokens: o cartão (rascunho -> PaymentIntent) cobrava cheio.
--   3. quote_order_pricing sem restaurant_id (a app não o manda no quote do ecrã) aplicava a
--      taxa de pedido pequeno (1,39 EUR) a lojas PARCEIRAS — o ecrã mostrava 16,68 em vez de 15,29.
--   4. TVDE gravava como "usados" todos os tokens pedidos mesmo quando o desconto era cortado.
--
-- Aplicada por MCP a 14/10/2026 (Claude.ai). Os blocos usam replace() sobre a definição viva e
-- param se a âncora não existir exatamente uma vez — reaplicar não duplica (guarda por marcador).

-- 0) Definição nova, editável no painel (Configurações).
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('token_balance_max_use_pct', '50'::jsonb,
        'Percentagem máxima do SALDO de tokens do cliente que pode ser usada num pedido/corrida (regra do Danilo 14/10/2026: metade).',
        'tokens')
ON CONFLICT (key) DO NOTHING;

-- 1) create_order
DO $mig$
DECLARE d text; n int; a text; r text;
BEGIN
  d := pg_get_functiondef('public.create_order'::regproc);

  -- 1a) tokens descontam no valor a cobrar
  IF position('(v_token_cents / 100.0)' in d) = 0 THEN
    a := 'v_charge_total := v_customer_total - v_wallet_eur - (v_credit_cents / 100.0);';
    IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'create_order: ancora charge_total'; END IF;
    d := replace(d, a, 'v_charge_total := GREATEST(0, v_customer_total - v_wallet_eur - (v_credit_cents / 100.0) - (v_token_cents / 100.0));  -- 14/10/2026: os tokens descontam no valor a cobrar (cartao, MB Way e dinheiro)');
  END IF;

  -- 1b) dinheiro: o estafeta cobra o valor já descontado
  IF position('cash_total_due = ROUND((v_charge_total' in d) = 0 THEN
    a := E'  RETURN jsonb_build_object(\n    ''order_id'', v_order_id,';
    IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'create_order: ancora return'; END IF;
    d := replace(d, a, E'  -- 14/10/2026: em dinheiro o estafeta cobra o valor ja com tokens/carteira descontados\n  IF v_payment_method = ''cash'' THEN\n    PERFORM set_config(''app.financial_bypass'', ''true'', true);\n    UPDATE public.orders SET cash_total_due = ROUND((v_charge_total - COALESCE(v_settlement_cents, 0) / 100.0)::numeric, 2) WHERE id = v_order_id;  -- a divida antiga vai a parte (debt_collected_cents), a app do estafeta soma-a\n    PERFORM set_config(''app.financial_bypass'', ''false'', true);\n  END IF;\n\n' || a);
  END IF;

  -- 1c) metade do saldo (lido de token_balance_max_use_pct)
  IF position('token_balance_max_use_pct' in d) = 0 THEN
    IF position('METADE do valor dos tokens' in d) > 0 THEN
      a := E'            / 2)::INTEGER);';
      IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'create_order: ancora metade'; END IF;
      d := replace(d, a, E'            * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_balance_max_use_pct''), 50) / 100.0)::INTEGER);');
    ELSE
      a := '  v_max_wallet_cents := ROUND(v_customer_total * 100)::INTEGER;';
      IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'create_order: ancora wallet'; END IF;
      d := replace(d, a, E'  -- 14/10/2026 (regra do Danilo): por pedido o cliente so usa METADE do valor dos tokens que tem.\n  IF v_token_cents > 0 THEN\n    v_token_cents := LEAST(v_token_cents,\n      FLOOR(public.get_user_tokens(v_user_id)\n            * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_value_cents_x100''), 50) / 100.0\n            * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_balance_max_use_pct''), 50) / 100.0)::INTEGER);\n  END IF;\n\n' || a);
    END IF;
  END IF;

  -- 1d) acima do tecto do pedido: corta em vez de rebentar (no cartão o dinheiro já foi cobrado)
  IF position('token_cap_exceeded' in d) > 0 THEN
    n := (length(d) - length(regexp_replace(d, 'RAISE EXCEPTION ''token_cap_exceeded:[^;]*;', '', 'g')));
    IF n = 0 THEN RAISE EXCEPTION 'create_order: ancora cap'; END IF;
    d := regexp_replace(d, 'RAISE EXCEPTION ''token_cap_exceeded:[^;]*;',
      'v_token_cents := v_token_cap_cents;  -- 14/10/2026: corta ao tecto em vez de rebentar');
  END IF;

  EXECUTE d;
END
$mig$;

-- 2) quote_order_pricing
DO $mig$
DECLARE d text; a text;
BEGIN
  d := pg_get_functiondef('public.quote_order_pricing'::regproc);
  IF position('token_balance_max_use_pct' in d) > 0 THEN RETURN; END IF;

  -- 2a) variáveis
  a := E'  v_bag_fee NUMERIC := 0;\nBEGIN';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'quote: ancora declare'; END IF;
  d := replace(d, a, E'  v_bag_fee NUMERIC := 0;\n  v_token_cents INTEGER := 0;   -- 14/10/2026\n  v_token_cap INTEGER;\nBEGIN');

  -- 2b) loja pelos produtos quando não vem id nem nome (o quote do ecrã não os manda)
  a := E'      WHERE name = p_input->>''vendor_name'' LIMIT 1;\n  END IF;';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'quote: ancora loja'; END IF;
  d := replace(d, a, a || E'\n  -- 14/10/2026: sem id nem nome, a loja sai dos produtos do carrinho (senao a taxa de\n  -- pedido pequeno caia em lojas PARCEIRAS e o ecra mostrava mais do que se cobra).\n  IF v_restaurant_id IS NULL AND jsonb_typeof(p_input->''product_lines'') = ''array''\n     AND v_service_type IN (''restaurant'',''storeShopping'',''takeaway'') THEN\n    SELECT p.restaurant_id::text INTO v_restaurant_id\n      FROM jsonb_array_elements(p_input->''product_lines'') pl\n      JOIN public.products p ON p.id::text = pl->>''product_id''\n     WHERE p.restaurant_id IS NOT NULL\n     LIMIT 1;\n  END IF;');

  -- 2c) tokens: metade do saldo, no máximo token_payment_max_pct do pedido, tirados do valor a cobrar
  a := E'  v_charge_total := v_customer_total - v_wallet_eur;\n';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'quote: ancora charge'; END IF;
  d := replace(d, a, E'  v_charge_total := v_customer_total - v_wallet_eur;\n  -- 14/10/2026: tokens (regra do Danilo: metade do saldo; e no maximo token_payment_max_pct do pedido)\n  v_token_cents := GREATEST(0, COALESCE((p_input->>''token_discount_cents'')::INTEGER, 0));\n  IF v_token_cents > 0 THEN\n    v_token_cap := FLOOR(v_customer_total * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_payment_max_pct''), 50))::INTEGER;\n    v_token_cents := LEAST(v_token_cents, v_token_cap,\n      FLOOR(public.get_user_tokens(v_user_id)\n            * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_value_cents_x100''), 50) / 100.0\n            * COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings WHERE key = ''token_balance_max_use_pct''), 50) / 100.0)::INTEGER);\n    v_charge_total := GREATEST(0, v_charge_total - v_token_cents / 100.0);\n  END IF;\n');

  -- 2d) devolve o desconto aplicado
  a := E'    ''restaurant_id'', v_restaurant_id\n  );';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'quote: ancora return'; END IF;
  d := replace(d, a, E'    ''restaurant_id'', v_restaurant_id,\n    ''tokens_applied_value_cents'', v_token_cents\n  );');

  EXECUTE d;
END
$mig$;

-- 3) tvde_request_ride: metade do saldo + contar só os tokens que deram desconto
DO $mig$
DECLARE d text; a text;
BEGIN
  d := pg_get_functiondef('public.tvde_request_ride'::regproc);
  IF position('token_balance_max_use_pct' in d) > 0 THEN RETURN; END IF;

  a := E'  IF p_tokens_to_apply > 0 AND v_client_fare > 0 THEN';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'tvde: ancora tokens'; END IF;
  d := replace(d, a, E'  -- 14/10/2026 (regra do Danilo): so metade dos tokens que o cliente tem.\n  IF p_tokens_to_apply > 0 THEN\n    p_tokens_to_apply := LEAST(p_tokens_to_apply,\n      FLOOR(public.get_user_tokens(v_uid) * COALESCE((public.get_setting(''token_balance_max_use_pct'') #>> ''{}'')::int, 50) / 100.0)::int);\n  END IF;\n' || a);

  a := E'    CASE WHEN v_tokens_discount_cents > 0 THEN p_tokens_to_apply ELSE 0 END,';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'tvde: ancora count'; END IF;
  d := replace(d, a, E'    CASE WHEN v_tokens_discount_cents > 0 THEN LEAST(p_tokens_to_apply, CEIL(v_tokens_discount_cents * 100.0 / v_token_value_x100)::int) ELSE 0 END,');

  EXECUTE d;
END
$mig$;
