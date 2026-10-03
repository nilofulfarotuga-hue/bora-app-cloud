-- ============================================================================
-- 2026-09-14 — Missão parceiro-edita-preco-14-09 (Bloco 4, painel admin).
--
-- O painel admin editava só `products.price` (RPC admin_update_product_price)
-- e deixava `products.partner_shelf_price` para trás: o parceiro passava a
-- receber um valor que já não correspondia à etiqueta da loja dele.
--
-- Regra de preço das lojas parceiras (decisão do Danilo, 14/09):
--   partner_shelf_price = o preço de balcão (o que o parceiro recebe)
--   price               = round(balcão ÷ (1 − comissão_visível) × (1 + markup_oculto), 2)
--   As percentagens vêm de platform_settings (partner_visible_commission_pct e
--   partner_hidden_markup_pct). Loja com restaurants.app_markup_pct > 0
--   ("comissão paga pelo cliente"): price = round(balcão × (1 + app_markup_pct), 2).
--   A leitura inversa é a função canónica public.partner_store_share(price,
--   restaurant_id) — é ela que diz quanto o parceiro recebe.
--
-- SÓ ADITIVO: duas funções novas. Não se toca nas funções que repartem o
-- dinheiro nem em platform_settings. As antigas ficam como estavam.
--   1) admin_list_products_by_partner_v2 — a lista passa a trazer também
--      partner_shelf_price, is_partner e app_markup_pct (e category/is_popular,
--      que a ficha do parceiro no painel já lia sem lhe chegarem).
--   2) admin_update_product_prices — grava as DUAS colunas de uma vez e recusa
--      um par incoerente: partner_store_share(price) tem de devolver o balcão.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. admin_list_products_by_partner_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_products_by_partner_v2(
  p_restaurant_id TEXT,
  p_search        TEXT    DEFAULT NULL,
  p_only_inactive BOOLEAN DEFAULT false,
  p_limit         INT     DEFAULT 100,
  p_offset        INT     DEFAULT 0
)
RETURNS TABLE(
  id                  TEXT,
  name                TEXT,
  description         TEXT,
  price               NUMERIC,
  partner_shelf_price NUMERIC,
  photo_url           TEXT,
  is_available        BOOLEAN,
  is_popular          BOOLEAN,
  category            TEXT,
  category_root       TEXT,
  taxonomy_section    TEXT,
  is_partner          BOOLEAN,
  app_markup_pct      NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 100; END IF;

  RETURN QUERY
  SELECT p.id, p.name, p.description, p.price, p.partner_shelf_price, p.photo_url,
         p.is_available, COALESCE(p.is_popular, false), p.category, p.category_root,
         p.taxonomy_section, COALESCE(r.is_partner, false), r.app_markup_pct
  FROM public.products p
  LEFT JOIN public.restaurants r ON r.id = p.restaurant_id
  WHERE p.restaurant_id = p_restaurant_id
    AND (p_search IS NULL
         OR p.name ILIKE '%' || p_search || '%'
         OR p.description ILIKE '%' || p_search || '%')
    AND (NOT p_only_inactive OR p.is_available = false)
  ORDER BY p.is_available DESC, p.name
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_products_by_partner_v2(TEXT, TEXT, BOOLEAN, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_products_by_partner_v2(TEXT, TEXT, BOOLEAN, INT, INT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. admin_update_product_prices — balcão + preço no app, coerentes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_product_prices(
  p_product_id  TEXT,
  p_shelf_price NUMERIC,
  p_app_price   NUMERIC,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin      RECORD;
  v_old        RECORD;
  v_is_partner BOOLEAN;
  v_check      NUMERIC;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_shelf_price IS NULL OR p_shelf_price < 0 OR p_shelf_price > 9999 THEN
    RAISE EXCEPTION 'admin_update_product_prices: shelf price must be 0..9999';
  END IF;
  IF p_app_price IS NULL OR p_app_price < 0 OR p_app_price > 9999 THEN
    RAISE EXCEPTION 'admin_update_product_prices: app price must be 0..9999';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_update_product_prices: reason required (>= 3 chars)';
  END IF;

  SELECT p.id, p.restaurant_id, p.name, p.price, p.partner_shelf_price
    INTO v_old
    FROM public.products p WHERE p.id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_product_prices: product % not found', p_product_id;
  END IF;

  SELECT r.is_partner INTO v_is_partner
    FROM public.restaurants r WHERE r.id = v_old.restaurant_id;
  IF COALESCE(v_is_partner, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'admin_update_product_prices: loja % nao e parceira (usar admin_update_product_price)',
      v_old.restaurant_id;
  END IF;

  -- Coerência: o que o parceiro recebe do preço do app tem de ser o balcão.
  -- partner_store_share(price, restaurant_id) é a função canónica do repasse;
  -- se o par não bater, recusa-se em vez de gravar um preço que engana o parceiro.
  v_check := public.partner_store_share(p_app_price, v_old.restaurant_id);
  IF abs(v_check - p_shelf_price) > 0.005 THEN
    RAISE EXCEPTION 'admin_update_product_prices: par incoerente (balcao % mas partner_store_share(%) = %)',
      p_shelf_price, p_app_price, v_check;
  END IF;

  IF v_old.price IS NOT NULL AND abs(v_old.price - p_app_price) < 0.001
     AND v_old.partner_shelf_price IS NOT NULL
     AND abs(v_old.partner_shelf_price - p_shelf_price) < 0.001 THEN
    RETURN jsonb_build_object('success', true, 'no_change', true);
  END IF;

  UPDATE public.products
     SET price = p_app_price,
         partner_shelf_price = p_shelf_price
   WHERE id = p_product_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'product_prices_update', 'product', p_product_id,
    jsonb_build_object(
      'product_name',    v_old.name,
      'restaurant_id',   v_old.restaurant_id,
      'old_price',       v_old.price,
      'new_price',       p_app_price,
      'old_shelf_price', v_old.partner_shelf_price,
      'new_shelf_price', p_shelf_price,
      'reason',          trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'product_id', p_product_id,
    'old_price', v_old.price, 'new_price', p_app_price,
    'old_shelf_price', v_old.partner_shelf_price, 'new_shelf_price', p_shelf_price
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_product_prices(TEXT, NUMERIC, NUMERIC, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_product_prices(TEXT, NUMERIC, NUMERIC, TEXT) TO authenticated;
