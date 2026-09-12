-- ============================================================================
-- BORA — admin_update_partner_data RPC (T15)
-- ============================================================================
-- Allows admin to edit partner data: name, address, category, phone.
-- Each parameter is OPTIONAL (NULL = don't update). Atomic update with
-- audit log diff.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_update_partner_data(
  p_restaurant_id TEXT,
  p_name          TEXT DEFAULT NULL,
  p_address       TEXT DEFAULT NULL,
  p_category      TEXT DEFAULT NULL,
  p_phone         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_old      RECORD;
  v_changes  JSONB := '{}'::jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_category IS NOT NULL
     AND p_category NOT IN ('restaurant', 'supermarket', 'store', 'pharmacy') THEN
    RAISE EXCEPTION 'admin_update_partner_data: invalid category "%". Must be restaurant|supermarket|store|pharmacy.', p_category;
  END IF;

  -- Validate non-empty trimmed for provided values
  IF p_name IS NOT NULL AND length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'admin_update_partner_data: name too short';
  END IF;
  IF p_address IS NOT NULL AND length(trim(p_address)) < 3 THEN
    RAISE EXCEPTION 'admin_update_partner_data: address too short';
  END IF;
  IF p_phone IS NOT NULL AND length(trim(p_phone)) < 7 THEN
    RAISE EXCEPTION 'admin_update_partner_data: phone too short';
  END IF;

  -- Snapshot for diff
  SELECT id, name, address, category, phone INTO v_old
    FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_partner_data: restaurant % not found', p_restaurant_id;
  END IF;

  -- Build diff (only fields that change)
  IF p_name IS NOT NULL AND p_name != v_old.name THEN
    v_changes := v_changes || jsonb_build_object('name',
      jsonb_build_object('old', v_old.name, 'new', trim(p_name)));
  END IF;
  IF p_address IS NOT NULL AND p_address != v_old.address THEN
    v_changes := v_changes || jsonb_build_object('address',
      jsonb_build_object('old', v_old.address, 'new', trim(p_address)));
  END IF;
  IF p_category IS NOT NULL AND p_category != v_old.category THEN
    v_changes := v_changes || jsonb_build_object('category',
      jsonb_build_object('old', v_old.category, 'new', p_category));
  END IF;
  IF p_phone IS NOT NULL AND p_phone != v_old.phone THEN
    v_changes := v_changes || jsonb_build_object('phone',
      jsonb_build_object('old', v_old.phone, 'new', trim(p_phone)));
  END IF;

  IF v_changes = '{}'::jsonb THEN
    RETURN jsonb_build_object('success', true, 'no_changes', true, 'restaurant_id', p_restaurant_id);
  END IF;

  -- Atomic UPDATE (only fields explicitly provided)
  UPDATE public.restaurants
     SET name     = COALESCE(NULLIF(trim(p_name), ''),    name),
         address  = COALESCE(NULLIF(trim(p_address), ''), address),
         category = COALESCE(p_category,                  category),
         phone    = COALESCE(NULLIF(trim(p_phone), ''),   phone)
   WHERE id = p_restaurant_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'partner_data_updated', 'restaurant',
    p_restaurant_id, v_changes
  );

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', p_restaurant_id,
    'changes', v_changes
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_partner_data(TEXT, TEXT, TEXT, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_partner_data(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_update_partner_data(TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Admin updates partner identity fields (name, address, category, phone). NULL means do not change. Returns diff in audit log.';

COMMIT;
