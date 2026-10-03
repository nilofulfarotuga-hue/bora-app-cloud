-- Venda ao peso (2026-09-18, missão sistema-redondo-2026-09-18).
--
-- Uma única função monta o produto ao peso a partir do preço por quilo que o
-- parceiro quer receber: grava `sold_by_weight` e `shelf_price_per_kg`, põe o
-- preço base da linha a valer a porção de 200 g e (re)constrói o grupo
-- obrigatório "Escolhe a quantidade" com 200 g / 300 g / 400 g / 500 g / 1 kg.
--
-- As percentagens vêm SEMPRE de platform_settings
-- (partner_visible_commission_pct, partner_hidden_markup_pct) — o espelho
-- exacto, lido ao contrário, de public.partner_store_share(). Nunca se escreve
-- 0,90 nem 1,05 à mão. Só a porção de 200 g passa pela fórmula; as outras são
-- múltiplos exactos dela (300 g = 1,5×, 1 kg = 5×), para o "€/kg" do cartão
-- (5 × base) ser sempre o preço do 1 kg. A inversa preço_cliente × (1 − comissão)
-- ÷ (1 + markup) devolve ao cêntimo o balcão/kg (provado a 18/09 nos dois
-- produtos da Sabores de Casa).
--
-- Loja não parceira: o preço gravado é o puro (balcão) e o markup de
-- não-parceiro continua a ser aplicado em runtime pela app, como em qualquer
-- outro produto de mercado. partner_shelf_price fica NULL nesse caso.
--
-- Quem pode chamar: admin (app_metadata.role = 'admin') ou o dono da loja
-- (restaurants.user_id = auth.uid()). Chamado pelo ecrã do parceiro e pelo
-- painel admin — uma verdade só, sem gémeos em Dart.

CREATE OR REPLACE FUNCTION public.set_product_weight_pricing(
  p_product_id        text,
  p_sold_by_weight    boolean,
  p_shelf_price_per_kg numeric DEFAULT NULL,
  p_reason            text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_is_admin     boolean := COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
  v_prod         RECORD;
  v_is_partner   boolean;
  v_app_markup   numeric;
  v_visible      numeric;
  v_hidden       numeric;
  v_group_id     text;
  v_shelf_200    numeric;
  v_price_200    numeric;
  v_grams        int;
  v_label        text;
  v_price_g      numeric;
  v_sort         int := 0;
  v_items        jsonb := '[]'::jsonb;
  c_group_name   constant text := 'Escolhe a quantidade';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_product_weight_pricing: not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT p.id, p.restaurant_id, p.name, p.price, p.partner_shelf_price
    INTO v_prod
    FROM public.products p WHERE p.id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'set_product_weight_pricing: product % not found', p_product_id;
  END IF;

  SELECT r.is_partner, COALESCE(r.app_markup_pct, 0)
    INTO v_is_partner, v_app_markup
    FROM public.restaurants r WHERE r.id = v_prod.restaurant_id;

  IF NOT v_is_admin AND NOT EXISTS (
       SELECT 1 FROM public.restaurants r
        WHERE r.id = v_prod.restaurant_id AND r.user_id = v_uid) THEN
    RAISE EXCEPTION 'set_product_weight_pricing: not owner nor admin' USING ERRCODE = '42501';
  END IF;

  -- Desligar: tira as colunas e o grupo das porções. O preço fica como está;
  -- quem desliga escreve o preço unitário novo no mesmo ecrã.
  IF NOT COALESCE(p_sold_by_weight, false) THEN
    UPDATE public.products
       SET sold_by_weight = false, shelf_price_per_kg = NULL
     WHERE id = p_product_id;
    DELETE FROM public.product_option_groups
     WHERE product_id = p_product_id AND name = c_group_name;
    IF v_is_admin THEN
      INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
      VALUES (v_uid, auth.jwt() ->> 'email', 'product_weight_off', 'product', p_product_id,
              jsonb_build_object('product_name', v_prod.name, 'reason', p_reason));
    END IF;
    RETURN jsonb_build_object('success', true, 'sold_by_weight', false);
  END IF;

  IF p_shelf_price_per_kg IS NULL OR p_shelf_price_per_kg <= 0 OR p_shelf_price_per_kg > 9999 THEN
    RAISE EXCEPTION 'set_product_weight_pricing: shelf price per kg must be 0.01..9999';
  END IF;

  SELECT (value::text)::numeric INTO v_visible FROM public.platform_settings WHERE key = 'partner_visible_commission_pct';
  SELECT (value::text)::numeric INTO v_hidden  FROM public.platform_settings WHERE key = 'partner_hidden_markup_pct';
  IF v_is_partner AND (v_visible IS NULL OR v_hidden IS NULL OR v_visible >= 1) THEN
    RAISE EXCEPTION 'set_product_weight_pricing: percentagens em falta em platform_settings';
  END IF;

  -- Porção base = 200 g.
  v_shelf_200 := ROUND(p_shelf_price_per_kg * 0.2, 2);
  IF v_is_partner THEN
    IF v_app_markup > 0 THEN
      v_price_200 := ROUND(p_shelf_price_per_kg * 0.2 * (1 + v_app_markup), 2);
    ELSE
      v_price_200 := ROUND(p_shelf_price_per_kg * 0.2 * (1 + v_hidden) / (1 - v_visible), 2);
    END IF;
  ELSE
    v_price_200 := v_shelf_200;
  END IF;

  UPDATE public.products
     SET sold_by_weight      = true,
         shelf_price_per_kg  = p_shelf_price_per_kg,
         price               = v_price_200,
         partner_shelf_price = CASE WHEN v_is_partner THEN v_shelf_200 ELSE partner_shelf_price END,
         unit                = 'porção'
   WHERE id = p_product_id;

  -- Grupo obrigatório das porções (um só; recriado a cada gravação).
  SELECT id INTO v_group_id FROM public.product_option_groups
   WHERE product_id = p_product_id AND name = c_group_name
   ORDER BY sort_order LIMIT 1;
  IF v_group_id IS NULL THEN
    INSERT INTO public.product_option_groups (product_id, name, is_required, min_choices, max_choices, sort_order)
    VALUES (p_product_id, c_group_name, true, 1, 1, 0)
    RETURNING id INTO v_group_id;
  ELSE
    UPDATE public.product_option_groups
       SET is_required = true, min_choices = 1, max_choices = 1
     WHERE id = v_group_id;
    DELETE FROM public.product_option_items WHERE group_id = v_group_id;
  END IF;

  FOREACH v_grams IN ARRAY ARRAY[200, 300, 400, 500, 1000] LOOP
    v_label := CASE v_grams
                 WHEN 500  THEN '500 g (meio quilo)'
                 WHEN 1000 THEN '1 kg'
                 ELSE v_grams::text || ' g'
               END;
    -- Cada porção é um múltiplo exacto da porção base de 200 g (300 g = 1,5×,
    -- 1 kg = 5×): o "€/kg" do cartão (5 × base) é sempre igual ao preço do
    -- 1 kg, e o balcão/kg continua a sair ao cêntimo pela inversa.
    v_price_g := ROUND(v_price_200 * v_grams / 200.0, 2);
    INSERT INTO public.product_option_items (group_id, name, price_add, is_available, sort_order)
    VALUES (v_group_id, v_label, ROUND(v_price_g - v_price_200, 2), true, v_sort);
    v_items := v_items || jsonb_build_object('name', v_label, 'price', v_price_g, 'price_add', ROUND(v_price_g - v_price_200, 2));
    v_sort := v_sort + 1;
  END LOOP;

  IF v_is_admin THEN
    INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
    VALUES (v_uid, auth.jwt() ->> 'email', 'product_weight_pricing', 'product', p_product_id,
            jsonb_build_object('product_name', v_prod.name, 'restaurant_id', v_prod.restaurant_id,
                               'old_price', v_prod.price, 'new_price', v_price_200,
                               'shelf_price_per_kg', p_shelf_price_per_kg, 'reason', p_reason));
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'product_id', p_product_id, 'sold_by_weight', true,
    'shelf_price_per_kg', p_shelf_price_per_kg, 'price', v_price_200,
    'partner_shelf_price', CASE WHEN v_is_partner THEN v_shelf_200 ELSE NULL END,
    'group_id', v_group_id, 'portions', v_items
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.set_product_weight_pricing(text, boolean, numeric, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_product_weight_pricing(text, boolean, numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_product_weight_pricing(text, boolean, numeric, text) TO authenticated;
