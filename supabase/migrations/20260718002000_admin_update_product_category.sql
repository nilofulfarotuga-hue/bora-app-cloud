-- MEGA-FIX 2026-07-18 Parte 5 — admin edita a categoria de um produto.
-- Espelha admin_update_product_price (guard + audit) mas para `products.category`
-- (texto, não-financeiro → sem exigência de motivo). SECURITY DEFINER para passar RLS.

CREATE OR REPLACE FUNCTION public.admin_update_product_category(p_product_id text, p_new_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_old   RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_new_category IS NULL OR length(trim(p_new_category)) = 0 THEN
    RAISE EXCEPTION 'category required';
  END IF;
  SELECT id, restaurant_id, name, category INTO v_old FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'product not found'; END IF;

  IF v_old.category IS NOT DISTINCT FROM trim(p_new_category) THEN
    RETURN jsonb_build_object('success', true, 'no_change', true);
  END IF;

  UPDATE public.products SET category = trim(p_new_category) WHERE id = p_product_id;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'product_category_update', 'product', p_product_id,
    jsonb_build_object('product_name', v_old.name, 'restaurant_id', v_old.restaurant_id,
                       'old_category', v_old.category, 'new_category', trim(p_new_category)));

  RETURN jsonb_build_object('success', true, 'product_id', p_product_id,
    'old_category', v_old.category, 'new_category', trim(p_new_category));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_update_product_category(text, text) TO authenticated;
