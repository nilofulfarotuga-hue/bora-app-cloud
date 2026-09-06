-- BLOCO 7.2 — RPCs admin para gerir a tabela guarda_businesses (RLS trancada).
-- Replica EXACTAMENTE o padrão dos RPCs admin existentes:
--   • guard via public._admin_op_guard() (app_metadata.role='admin')
--   • auditoria via public.log_admin_action(action, entity_type, entity_id, details)
--     (envolvida em EXCEPTION para nunca bloquear a operação — padrão driver RPCs)
-- guarda_businesses.id é UUID → usa entity_id (não entity_id_text).
-- NÃO toca dinheiro, pricing, dispatch nem create_order.

-- 1) Listar (pesquisa + paginação) ----------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_businesses(
  p_search text DEFAULT NULL,
  p_limit  int  DEFAULT 50,
  p_offset int  DEFAULT 0
) RETURNS TABLE (
  id          uuid,
  osm_id      text,
  name        text,
  category    text,
  address     text,
  lat         double precision,
  lng         double precision,
  is_visible  boolean,
  source      text,
  created_at  timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id    uuid;
  v_admin_email text;
BEGIN
  SELECT a.admin_id, a.admin_email INTO v_admin_id, v_admin_email
  FROM public._admin_op_guard() a;

  RETURN QUERY
    SELECT b.id, b.osm_id, b.name, b.category, b.address, b.lat, b.lng,
           b.is_visible, b.source, b.created_at
    FROM public.guarda_businesses b
    WHERE p_search IS NULL
       OR p_search = ''
       OR b.name ILIKE '%' || p_search || '%'
       OR COALESCE(b.address, '') ILIKE '%' || p_search || '%'
    ORDER BY b.is_visible DESC, b.name ASC
    LIMIT GREATEST(p_limit, 1)
    OFFSET GREATEST(p_offset, 0);
END;
$$;

-- 2) Criar (manual) ou actualizar -----------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_business(
  p_id         uuid,
  p_name       text,
  p_category   text,
  p_address    text,
  p_lat        double precision,
  p_lng        double precision,
  p_is_visible boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id    uuid;
  v_admin_email text;
  v_id          uuid;
BEGIN
  SELECT a.admin_id, a.admin_email INTO v_admin_id, v_admin_email
  FROM public._admin_op_guard() a;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'name_required';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.guarda_businesses
      (name, category, address, lat, lng, is_visible, source)
    VALUES
      (btrim(p_name), p_category, p_address, p_lat, p_lng,
       COALESCE(p_is_visible, true), 'manual')
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.guarda_businesses
       SET name       = btrim(p_name),
           category   = p_category,
           address    = p_address,
           lat        = p_lat,
           lng        = p_lng,
           is_visible = COALESCE(p_is_visible, is_visible),
           updated_at = now()
     WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'business_not_found';
    END IF;
  END IF;

  BEGIN
    PERFORM public.log_admin_action(
      'guarda_business_upsert', 'guarda_business', v_id,
      jsonb_build_object('name', btrim(p_name), 'category', p_category,
                         'manual', p_id IS NULL));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_upsert_business: audit log failed: %', SQLERRM;
  END;

  RETURN v_id;
END;
$$;

-- 3) Esconder / mostrar ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_business_visibility(
  p_id      uuid,
  p_visible boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id    uuid;
  v_admin_email text;
  v_found       uuid;
BEGIN
  SELECT a.admin_id, a.admin_email INTO v_admin_id, v_admin_email
  FROM public._admin_op_guard() a;

  UPDATE public.guarda_businesses
     SET is_visible = p_visible, updated_at = now()
   WHERE id = p_id
  RETURNING id INTO v_found;
  IF v_found IS NULL THEN
    RAISE EXCEPTION 'business_not_found';
  END IF;

  BEGIN
    PERFORM public.log_admin_action(
      'guarda_business_visibility', 'guarda_business', p_id,
      jsonb_build_object('is_visible', p_visible));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_set_business_visibility: audit log failed: %', SQLERRM;
  END;
END;
$$;

-- 4) Apagar ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_business(
  p_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id    uuid;
  v_admin_email text;
  v_name        text;
BEGIN
  SELECT a.admin_id, a.admin_email INTO v_admin_id, v_admin_email
  FROM public._admin_op_guard() a;

  DELETE FROM public.guarda_businesses WHERE id = p_id
  RETURNING name INTO v_name;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'business_not_found';
  END IF;

  BEGIN
    PERFORM public.log_admin_action(
      'guarda_business_delete', 'guarda_business', p_id,
      jsonb_build_object('name', v_name));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_delete_business: audit log failed: %', SQLERRM;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_businesses(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_business(uuid, text, text, text, double precision, double precision, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_business_visibility(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_business(uuid) TO authenticated;
