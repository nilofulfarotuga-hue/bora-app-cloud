-- ============================================================================
-- BORA — Admin catalog/product management RPCs (T7)
-- ============================================================================
-- Allows admin to:
--   1. List products of a specific partner (paginated + search).
--   2. Activate/deactivate a product (toggle is_available).
--   3. Edit product price (with audit log including old/new diff).
--   4. List partners with product counts (overview dashboard).
--
-- All RPCs use _admin_op_guard. products.id is TEXT (legacy).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. admin_list_products_by_partner
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_products_by_partner(
  p_restaurant_id TEXT,
  p_search        TEXT DEFAULT NULL,
  p_only_inactive BOOLEAN DEFAULT FALSE,
  p_limit         INT  DEFAULT 100,
  p_offset        INT  DEFAULT 0
)
RETURNS TABLE (
  id              TEXT,
  name            TEXT,
  description     TEXT,
  price           FLOAT8,
  photo_url       TEXT,
  is_available    BOOLEAN,
  category_root   TEXT,
  taxonomy_section TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 100; END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.description,
    p.price,
    p.photo_url,
    p.is_available,
    p.category_root,
    p.taxonomy_section
  FROM public.products p
  WHERE p.restaurant_id = p_restaurant_id
    AND (p_search IS NULL
         OR p.name ILIKE '%' || p_search || '%'
         OR p.description ILIKE '%' || p_search || '%')
    AND (NOT p_only_inactive OR p.is_available = false)
  ORDER BY p.is_available DESC, p.name
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_products_by_partner(TEXT, TEXT, BOOLEAN, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_products_by_partner(TEXT, TEXT, BOOLEAN, INT, INT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. admin_set_product_availability
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_product_availability(
  p_product_id  TEXT,
  p_available   BOOLEAN,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_old   RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_set_product_availability: reason required (>= 3 chars)';
  END IF;

  SELECT id, restaurant_id, name, is_available INTO v_old
    FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_product_availability: product % not found', p_product_id;
  END IF;

  IF v_old.is_available = p_available THEN
    RETURN jsonb_build_object('success', true, 'no_change', true);
  END IF;

  UPDATE public.products SET is_available = p_available WHERE id = p_product_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email,
    CASE WHEN p_available THEN 'product_activate' ELSE 'product_deactivate' END,
    'product', p_product_id,
    jsonb_build_object(
      'product_name',  v_old.name,
      'restaurant_id', v_old.restaurant_id,
      'reason',        trim(p_reason),
      'old_available', v_old.is_available,
      'new_available', p_available
    )
  );

  RETURN jsonb_build_object('success', true, 'product_id', p_product_id, 'is_available', p_available);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_product_availability(TEXT, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_product_availability(TEXT, BOOLEAN, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. admin_update_product_price
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_product_price(
  p_product_id TEXT,
  p_new_price  FLOAT8,
  p_reason     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_old   RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_new_price IS NULL OR p_new_price < 0 OR p_new_price > 9999 THEN
    RAISE EXCEPTION 'admin_update_product_price: price must be 0..9999';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_update_product_price: reason required (>= 3 chars)';
  END IF;

  SELECT id, restaurant_id, name, price INTO v_old
    FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_product_price: product % not found', p_product_id;
  END IF;

  IF abs(v_old.price - p_new_price) < 0.001 THEN
    RETURN jsonb_build_object('success', true, 'no_change', true);
  END IF;

  UPDATE public.products SET price = p_new_price WHERE id = p_product_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'product_price_update', 'product', p_product_id,
    jsonb_build_object(
      'product_name',  v_old.name,
      'restaurant_id', v_old.restaurant_id,
      'old_price',     v_old.price,
      'new_price',     p_new_price,
      'delta',         p_new_price - v_old.price,
      'reason',        trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'product_id', p_product_id,
    'old_price', v_old.price, 'new_price', p_new_price
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_product_price(TEXT, FLOAT8, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_product_price(TEXT, FLOAT8, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. admin_partners_with_counts — overview list
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_partners_with_counts(
  p_search TEXT DEFAULT NULL,
  p_limit  INT  DEFAULT 100,
  p_offset INT  DEFAULT 0
)
RETURNS TABLE (
  id            TEXT,
  name          TEXT,
  category      TEXT,
  is_partner    BOOLEAN,
  is_online     BOOLEAN,
  total_products  BIGINT,
  active_products BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 100; END IF;

  RETURN QUERY
  SELECT
    r.id, r.name, r.category, r.is_partner, r.is_online,
    COALESCE(c.total, 0)  AS total_products,
    COALESCE(c.active, 0) AS active_products
  FROM public.restaurants r
  LEFT JOIN LATERAL (
    SELECT count(*) AS total,
           count(*) FILTER (WHERE is_available) AS active
    FROM public.products WHERE restaurant_id = r.id
  ) c ON true
  WHERE p_search IS NULL OR r.name ILIKE '%' || p_search || '%'
  ORDER BY r.name
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_partners_with_counts(TEXT, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_partners_with_counts(TEXT, INT, INT) TO authenticated;


COMMIT;
