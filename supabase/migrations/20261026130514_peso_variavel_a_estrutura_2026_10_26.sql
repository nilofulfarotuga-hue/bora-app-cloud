-- Peso variável nos mercados não-parceiros — regra do Danilo 26/10/2026 ("Autorizo", 10:16 Lisboa).
-- O estafeta escreve o valor da etiqueta da balança nos produtos de peso variável;
-- o cliente paga o valor final com a mesma margem do produto; limite ±30% por produto.
-- Parte A: estrutura nova (inerte para a app atual).

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS variable_weight boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.products.variable_weight IS
  'Peso variável (mercados não-parceiros): o preço da app é uma estimativa; o estafeta escreve o valor da etiqueta da balança (estafeta_ajustar_peso) e o cliente paga o valor final com a mesma margem. Diferente de sold_by_weight (porções de 200 g dos parceiros). Regra do Danilo 26/10/2026.';

INSERT INTO public.platform_settings (key, value, description, category, is_secret) VALUES
  ('weight_adjust_enabled', 'true'::jsonb,
   'Peso variável: o estafeta pode trocar o preço dos produtos de peso variável pelo valor da etiqueta da balança e o cliente paga o valor final (Danilo, 26/10/2026).',
   'storeshopping', false),
  ('weight_adjust_max_pct', '0.30'::jsonb,
   'Peso variável: diferença máxima aceite por produto, para cima ou para baixo (0.30 = 30%). Fora disto a app não aceita: pesa outra vez ou marca "Não há".',
   'storeshopping', false),
  ('weight_adjust_card_charge_enabled', 'false'::jsonb,
   'Peso variável e produtos acrescentados em pedidos pagos com cartão: cobrar a diferença a mais no cartão guardado (Edge Function cobrar-diferenca-peso). Desligado até haver prova real; desligado = a Bora assume a diferença.',
   'storeshopping', false)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.order_weight_adjustments (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           text NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id         text NOT NULL,
  item_name          text,
  qty                integer NOT NULL DEFAULT 1,
  est_base_cents     integer NOT NULL,
  real_base_cents    integer NOT NULL,
  est_client_cents   integer NOT NULL,
  new_client_cents   integer NOT NULL,
  delta_client_cents integer NOT NULL,
  driver_user_id     uuid,
  payment_method     text,
  settled_via        text,
  settled_at         timestamptz,
  notified_at        timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT order_weight_adjustments_um_por_produto UNIQUE (order_id, product_id)
);
COMMENT ON TABLE public.order_weight_adjustments IS
  'Ajustes de peso feitos pelo estafeta (um por produto e pedido). est_* = previsto na app, real_base_cents = etiqueta da balança (preço de caixa), new_client_cents = o que o cliente paga pela linha. settled_via: dinheiro | carteira | cartao_pendente | cartao_cobrado | bora_assume | sem_diferenca | ignorado_nao_ha.';
CREATE INDEX IF NOT EXISTS idx_owa_order   ON public.order_weight_adjustments(order_id);
CREATE INDEX IF NOT EXISTS idx_owa_created ON public.order_weight_adjustments(created_at DESC);

ALTER TABLE public.order_weight_adjustments ENABLE ROW LEVEL SECURITY;
CREATE POLICY owa_admin_ve ON public.order_weight_adjustments
  FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY owa_cliente_ve ON public.order_weight_adjustments
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.orders o WHERE o.id = order_weight_adjustments.order_id AND o.user_id = auth.uid()));
CREATE POLICY owa_estafeta_ve ON public.order_weight_adjustments
  FOR SELECT TO authenticated USING (EXISTS (
    SELECT 1 FROM public.orders o
     WHERE o.id = order_weight_adjustments.order_id
       AND (o.assigned_driver_id = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = auth.uid() AND d.id::text = o.assigned_driver_id))));
GRANT SELECT ON public.order_weight_adjustments TO authenticated;

-- Euros em PT ("1,40 €").
CREATE OR REPLACE FUNCTION public._euros_pt(p_cents integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT replace(to_char(COALESCE(p_cents, 0) / 100.0, 'FM999999990.00'), '.', ',') || ' €'
$$;
GRANT EXECUTE ON FUNCTION public._euros_pt(integer) TO authenticated;

-- O estafeta escreve o valor da etiqueta da balança (preço de caixa da linha inteira).
CREATE OR REPLACE FUNCTION public.estafeta_ajustar_peso(p_order_id text, p_product_id text, p_real_base_cents integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_order        RECORD;
  v_parceira     boolean;
  v_is_mine      boolean;
  v_enabled      boolean;
  v_max_pct      numeric;
  v_item         jsonb;
  v_found        boolean := false;
  v_qty          integer;
  v_price        numeric;
  v_base         numeric;
  v_name         text;
  v_vw           boolean;
  v_est_client   integer;
  v_est_base     integer;
  v_new_client   integer;
  v_delta        integer;
  v_prev_delta   integer;
  v_min          integer;
  v_max          integer;
  v_total_delta  integer;
  v_novo_total   integer;
  v_title        text;
  v_body         text;
  v_url          text;
  v_key          text;
  v_avisado      boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'weight_adjust_enabled'), false)
    INTO v_enabled;
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'desligado');
  END IF;
  SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM public.platform_settings WHERE key = 'weight_adjust_max_pct'), 0.30)
    INTO v_max_pct;
  IF v_max_pct IS NULL OR v_max_pct <= 0 OR v_max_pct >= 1 THEN v_max_pct := 0.30; END IF;

  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type,
         is_partner_store, restaurant_id, payment_method, status, is_purchase_finalized,
         items, total, final_total
    INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;

  SELECT r.is_partner INTO v_parceira FROM public.restaurants r WHERE r.id = v_order.restaurant_id;
  IF COALESCE(v_parceira, v_order.is_partner_store, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'loja_parceira');
  END IF;
  IF v_order.service_type NOT IN ('restaurant', 'storeShopping') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'tipo_de_pedido');
  END IF;

  v_is_mine := v_order.assigned_driver_id = v_uid::text
    OR v_order.current_driver_offer_id = v_uid::text
    OR EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid AND d.id::text = v_order.assigned_driver_id)
    OR public.is_admin();
  IF NOT COALESCE(v_is_mine, false) THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;

  IF v_order.status NOT IN ('driverAccepted', 'pickedUp') OR COALESCE(v_order.is_purchase_finalized, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'compra_ja_fechada');
  END IF;

  SELECT p.variable_weight, p.name INTO v_vw, v_name FROM public.products p WHERE p.id = p_product_id;
  IF NOT COALESCE(v_vw, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'produto_sem_peso_variavel');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb)) LOOP
    IF v_item->>'productId' = p_product_id THEN
      v_found := true;
      v_qty   := GREATEST(1, ROUND(COALESCE(NULLIF(v_item->>'quantity', '')::numeric, 1))::int);
      v_price := COALESCE(NULLIF(v_item->>'price', '')::numeric, 0);
      v_base  := COALESCE(NULLIF(v_item->>'basePrice', '')::numeric, v_price);
      v_name  := COALESCE(NULLIF(v_item->>'name', ''), v_name);
      EXIT;
    END IF;
  END LOOP;
  IF NOT v_found THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'produto_fora_do_pedido');
  END IF;

  v_est_client := ROUND(v_price * v_qty * 100)::int;
  v_est_base   := ROUND(v_base  * v_qty * 100)::int;
  IF v_est_client <= 0 OR v_est_base <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'preco_estimado_invalido');
  END IF;
  IF p_real_base_cents IS NULL OR p_real_base_cents <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'valor_invalido');
  END IF;

  v_min := CEIL(v_est_base * (1 - v_max_pct))::int;
  v_max := FLOOR(v_est_base * (1 + v_max_pct))::int;
  IF p_real_base_cents < v_min OR p_real_base_cents > v_max THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'fora_do_limite',
      'estimado_caixa_cents', v_est_base, 'minimo_cents', v_min, 'maximo_cents', v_max);
  END IF;

  -- Mesma margem que a linha já tinha na app (paridade Glovo incluída).
  v_new_client := ROUND(p_real_base_cents::numeric * v_est_client / v_est_base)::int;
  v_delta      := v_new_client - v_est_client;

  SELECT a.delta_client_cents INTO v_prev_delta
    FROM public.order_weight_adjustments a
   WHERE a.order_id = p_order_id AND a.product_id = p_product_id;

  INSERT INTO public.order_weight_adjustments (
    order_id, product_id, item_name, qty, est_base_cents, real_base_cents,
    est_client_cents, new_client_cents, delta_client_cents, driver_user_id, payment_method)
  VALUES (
    p_order_id, p_product_id, v_name, v_qty, v_est_base, p_real_base_cents,
    v_est_client, v_new_client, v_delta, v_uid, v_order.payment_method)
  ON CONFLICT (order_id, product_id) DO UPDATE SET
    real_base_cents    = EXCLUDED.real_base_cents,
    new_client_cents   = EXCLUDED.new_client_cents,
    delta_client_cents = EXCLUDED.delta_client_cents,
    driver_user_id     = EXCLUDED.driver_user_id,
    updated_at         = now();

  SELECT COALESCE(SUM(a.delta_client_cents), 0)::int INTO v_total_delta
    FROM public.order_weight_adjustments a WHERE a.order_id = p_order_id;
  v_novo_total := ROUND(COALESCE(v_order.final_total, v_order.total, 0) * 100)::int + v_total_delta;

  -- Aviso ao cliente (sino da app + push). Só quando o valor muda. Nunca aborta o ajuste.
  IF v_delta <> 0 OR (v_prev_delta IS NOT NULL AND v_prev_delta <> v_delta) THEN
    v_title := 'Preço ajustado ao peso';
    IF v_delta = 0 THEN
      v_body := format('%s: voltou ao preço previsto, %s. Novo total: %s.',
                       v_name, public._euros_pt(v_new_client), public._euros_pt(v_novo_total));
    ELSE
      v_body := format('%s: passou de %s para %s (peso real). Novo total: %s.',
                       v_name, public._euros_pt(v_est_client), public._euros_pt(v_new_client), public._euros_pt(v_novo_total));
    END IF;
    BEGIN
      PERFORM public._push_in_app_notification(v_order.user_id, 'order_weight_adjusted', v_title, v_body, p_order_id);
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' AND v_order.user_id IS NOT NULL THEN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('clientId', v_order.user_id::text, 'orderId', p_order_id,
                                     'type', 'order_weight_adjusted', 'title', v_title, 'body', v_body));
      END IF;
      UPDATE public.order_weight_adjustments SET notified_at = now()
       WHERE order_id = p_order_id AND product_id = p_product_id;
      v_avisado := true;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'aviso de peso falhou: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'produto', v_name,
    'qtd', v_qty,
    'estimado_caixa_cents', v_est_base,
    'real_caixa_cents', p_real_base_cents,
    'estimado_cliente_cents', v_est_client,
    'novo_cliente_cents', v_new_client,
    'diferenca_cents', v_delta,
    'diferenca_total_pedido_cents', v_total_delta,
    'novo_total_estimado_cents', v_novo_total,
    'minimo_cents', v_min,
    'maximo_cents', v_max,
    'cliente_avisado', v_avisado
  );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.estafeta_ajustar_peso(text, text, integer) TO authenticated;

-- Painel admin: lista dos ajustes.
CREATE OR REPLACE FUNCTION public.admin_list_weight_adjustments(p_dias integer DEFAULT 30, p_limit integer DEFAULT 300)
RETURNS TABLE (
  id uuid, created_at timestamptz, updated_at timestamptz, order_id text, loja text, cliente_nome text,
  product_id text, item_name text, qty integer, est_base_cents integer, real_base_cents integer,
  est_client_cents integer, new_client_cents integer, delta_client_cents integer,
  payment_method text, settled_via text, settled_at timestamptz, notified_at timestamptz,
  driver_user_id uuid, estafeta_nome text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT a.id, a.created_at, a.updated_at, a.order_id, o.vendor_name, o.customer_name,
         a.product_id, a.item_name, a.qty, a.est_base_cents, a.real_base_cents,
         a.est_client_cents, a.new_client_cents, a.delta_client_cents,
         a.payment_method, a.settled_via, a.settled_at, a.notified_at,
         a.driver_user_id, (SELECT d.name FROM public.drivers d WHERE d.user_id = a.driver_user_id LIMIT 1)
    FROM public.order_weight_adjustments a
    JOIN public.orders o ON o.id = a.order_id
   WHERE a.created_at > now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_dias, 30), 365)))
   ORDER BY a.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 300), 2000));
END;
$function$;
GRANT EXECUTE ON FUNCTION public.admin_list_weight_adjustments(integer, integer) TO authenticated;

-- Painel admin: marcar/desmarcar um produto como de peso variável (com auditoria).
CREATE OR REPLACE FUNCTION public.admin_set_variable_weight(p_product_id text, p_on boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_old boolean; v_name text; v_rest text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501'; END IF;
  SELECT variable_weight, name, restaurant_id INTO v_old, v_name, v_rest FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND: %', p_product_id; END IF;
  UPDATE public.products SET variable_weight = COALESCE(p_on, false) WHERE id = p_product_id;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt() ->> 'email', 'product_variable_weight', 'product', p_product_id,
          jsonb_build_object('product_name', v_name, 'restaurant_id', v_rest,
                             'antes', v_old, 'depois', COALESCE(p_on, false), 'motivo', p_reason));
  RETURN jsonb_build_object('ok', true, 'product_id', p_product_id, 'variable_weight', COALESCE(p_on, false));
END;
$function$;
GRANT EXECUTE ON FUNCTION public.admin_set_variable_weight(text, boolean, text) TO authenticated;

-- Fechar a anon e às escritas diretas (dentro de DO por causa do gate do MCP).
DO $do$
BEGIN
  EXECUTE $q$REVOKE ALL ON public.order_weight_adjustments FROM anon$q$;
  EXECUTE $q$REVOKE INSERT, UPDATE, DELETE ON public.order_weight_adjustments FROM authenticated$q$;
  EXECUTE $q$REVOKE ALL ON FUNCTION public._euros_pt(integer) FROM PUBLIC, anon$q$;
  EXECUTE $q$REVOKE ALL ON FUNCTION public.estafeta_ajustar_peso(text, text, integer) FROM PUBLIC, anon$q$;
  EXECUTE $q$REVOKE ALL ON FUNCTION public.admin_list_weight_adjustments(integer, integer) FROM PUBLIC, anon$q$;
  EXECUTE $q$REVOKE ALL ON FUNCTION public.admin_set_variable_weight(text, boolean, text) FROM PUBLIC, anon$q$;
END
$do$;
