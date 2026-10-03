-- BUG 24: admin can reset a product photo back to placeholder.
-- Sets photo_url=NULL, image_source=NULL, needs_photo=true so the next
-- ingest run (or manual edit) picks the product up again.

CREATE OR REPLACE FUNCTION public.admin_reset_product_photo(p_product_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
  v_product RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin
  FROM auth.users WHERE id = v_caller;

  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT id, name, photo_url, image_source, needs_photo INTO v_product
  FROM public.products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found: %', p_product_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.products
  SET photo_url    = NULL,
      image_source = NULL,
      needs_photo  = true,
      updated_at   = now()
  WHERE id = p_product_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller, v_caller_email, 'product_photo_reset', 'product', p_product_id,
      jsonb_build_object(
        'product_name', v_product.name,
        'previous_photo_url', v_product.photo_url,
        'previous_image_source', v_product.image_source,
        'previous_needs_photo', COALESCE(v_product.needs_photo, false)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_reset_product_photo audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'product_id', p_product_id,
    'product_name', v_product.name,
    'photo_url', NULL,
    'needs_photo', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_reset_product_photo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_product_photo(text) TO authenticated;
