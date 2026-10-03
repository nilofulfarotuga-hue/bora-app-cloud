-- =====================================================================
-- RPCs admin para o painel de revisão de preços PVPR do Continente.
-- Guard: _admin_op_guard() (app_metadata.role='admin'). Auditoria: log_admin_action.
-- A staging tem RLS sem policies => Flutter (JWT user) só acede via estas RPCs.
-- NENHUMA destas aplica preços automaticamente — apply é chamada pelo painel.
-- =====================================================================

-- 1) Resumo para o dashboard
CREATE OR REPLACE FUNCTION public.admin_continente_price_summary()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin record; v jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT jsonb_build_object(
    'total',        count(*),
    'ok',           count(*) FILTER (WHERE status IN ('ok_no_promo','ok_promo')),
    'promo',        count(*) FILTER (WHERE status = 'ok_promo'),
    'no_price',     count(*) FILTER (WHERE status NOT IN ('ok_no_promo','ok_promo')),
    'needs_review', count(*) FILTER (WHERE needs_review),
    'big_div',      count(*) FILTER (WHERE abs(COALESCE(divergence_pct,0)) >= 0.25),
    'pending',      count(*) FILTER (WHERE reviewer_action IS NULL AND status IN ('ok_no_promo','ok_promo')),
    'approved',     count(*) FILTER (WHERE reviewer_action = 'approved'),
    'rejected',     count(*) FILTER (WHERE reviewer_action = 'rejected'),
    'applied',      count(*) FILTER (WHERE applied)
  ) INTO v FROM continente_price_staging;
  RETURN COALESCE(v, '{}'::jsonb);
END; $$;

-- 2) Lista paginada com filtro (ordena por maior divergência)
CREATE OR REPLACE FUNCTION public.admin_continente_price_list(
  p_filter text DEFAULT 'all', p_limit int DEFAULT 100, p_offset int DEFAULT 0
) RETURNS SETOF continente_price_staging LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin record;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  RETURN QUERY
  SELECT * FROM continente_price_staging s
  WHERE CASE p_filter
    WHEN 'big_div'      THEN abs(COALESCE(s.divergence_pct,0)) >= 0.25
    WHEN 'promo'        THEN s.status = 'ok_promo'
    WHEN 'needs_review' THEN s.needs_review
    WHEN 'no_price'     THEN s.status NOT IN ('ok_no_promo','ok_promo')
    WHEN 'pending'      THEN s.reviewer_action IS NULL AND s.status IN ('ok_no_promo','ok_promo')
    WHEN 'approved'     THEN s.reviewer_action = 'approved'
    WHEN 'applied'      THEN s.applied
    ELSE true END
  ORDER BY abs(COALESCE(s.divergence_pct,0)) DESC, s.name
  LIMIT least(p_limit, 500) OFFSET greatest(p_offset, 0);
END; $$;

-- 3) Marcar revisão (aprovar / rejeitar) de linhas selecionadas
CREATE OR REPLACE FUNCTION public.admin_continente_price_review(
  p_ids uuid[], p_action text
) RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin record; v_count int;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_action NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'invalid action: %', p_action USING ERRCODE = '22023';
  END IF;
  UPDATE continente_price_staging
     SET reviewer_action = p_action, reviewed_by = v_admin.admin_email, reviewed_at = now()
   WHERE id = ANY(p_ids) AND applied = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM public.log_admin_action('continente_price_review','continente_price_staging', NULL,
    jsonb_build_object('action', p_action, 'count', v_count));
  RETURN v_count;
END; $$;

-- 4) Aplicar aprovados a products (so price/last_updated/source). NUNCA auto.
CREATE OR REPLACE FUNCTION public.admin_continente_apply_prices()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin record; v_count int; v_src text := 'continente_pt_official_2026-06-14';
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  WITH appr AS (
    SELECT s.id, s.product_id, s.new_price
    FROM continente_price_staging s
    WHERE s.reviewer_action = 'approved' AND s.applied = false
      AND s.status IN ('ok_no_promo','ok_promo') AND s.new_price IS NOT NULL
  ), upd AS (
    UPDATE products p
       SET price = a.new_price, last_updated = now()::text, source = v_src
      FROM appr a
     WHERE p.id = a.product_id
    RETURNING a.id
  )
  UPDATE continente_price_staging s
     SET applied = true, applied_at = now()
   WHERE s.id IN (SELECT id FROM upd);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM public.log_admin_action('continente_prices_applied','products', NULL,
    jsonb_build_object('count', v_count, 'source', v_src));
  RETURN jsonb_build_object('applied', v_count);
END; $$;

GRANT EXECUTE ON FUNCTION public.admin_continente_price_summary()                TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_continente_price_list(text,int,int)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_continente_price_review(uuid[],text)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_continente_apply_prices()                  TO authenticated;
