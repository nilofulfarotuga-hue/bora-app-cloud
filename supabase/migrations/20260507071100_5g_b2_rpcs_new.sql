-- 5G B2: 4 RPCs novas

-- ═══ admin_skill_suggestions_stats ═══
CREATE OR REPLACE FUNCTION public.admin_skill_suggestions_stats()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  SELECT jsonb_build_object(
    'total', COUNT(*),
    'pending', COUNT(*) FILTER (WHERE status='pending'),
    'approved', COUNT(*) FILTER (WHERE status='approved'),
    'implemented', COUNT(*) FILTER (WHERE status='implemented'),
    'rejected', COUNT(*) FILTER (WHERE status='rejected'),
    'rolled_back', COUNT(*) FILTER (WHERE status='rolled_back'),
    'auto_archived', COUNT(*) FILTER (WHERE status='auto_archived'),
    'with_notes', COUNT(*) FILTER (WHERE admin_notes IS NOT NULL),
    'pct_approved',
      CASE WHEN COUNT(*) FILTER
            (WHERE status IN ('implemented','approved','rejected','rolled_back')) > 0
        THEN ROUND(
          100.0 * COUNT(*) FILTER (WHERE status IN ('implemented','approved')) /
          COUNT(*) FILTER (WHERE status IN ('implemented','approved','rejected','rolled_back')),
          1)
        ELSE 0
      END,
    'oldest_pending_days',
      COALESCE(
        EXTRACT(DAY FROM (now() - MIN(suggested_at) FILTER (WHERE status='pending')))::int,
        0
      )
  ) INTO v_result FROM skill_suggestions;

  RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.admin_skill_suggestions_stats() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_skill_suggestions_stats() TO authenticated;

-- ═══ admin_skill_suggestions_metrics ═══
CREATE OR REPLACE FUNCTION public.admin_skill_suggestions_metrics()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  WITH metrics AS (
    SELECT
      AVG(EXTRACT(EPOCH FROM (reviewed_at - suggested_at))/3600.0)
        FILTER (WHERE reviewed_at IS NOT NULL) AS avg_review_hours,
      (SELECT jsonb_agg(jsonb_build_object('category', cat, 'count', cnt))
       FROM (
         SELECT suggested_category AS cat, COUNT(*) AS cnt
         FROM skill_suggestions
         WHERE suggested_category IS NOT NULL
         GROUP BY suggested_category
         ORDER BY cnt DESC LIMIT 10
       ) t) AS top_categories,
      (SELECT jsonb_agg(jsonb_build_object('month', m, 'count', cnt) ORDER BY m)
       FROM (
         SELECT date_trunc('month', suggested_at)::date AS m, COUNT(*) AS cnt
         FROM skill_suggestions
         WHERE suggested_at > now() - interval '6 months'
         GROUP BY date_trunc('month', suggested_at)
       ) t) AS by_month,
      (SELECT jsonb_object_agg(proposal_type, cnt)
       FROM (
         SELECT proposal_type, COUNT(*) AS cnt
         FROM skill_suggestions
         WHERE proposal_type IS NOT NULL
         GROUP BY proposal_type
       ) t) AS by_type,
      (SELECT jsonb_object_agg(zone_type, cnt)
       FROM (
         SELECT zone_type, COUNT(*) AS cnt
         FROM skill_suggestions
         WHERE zone_type IS NOT NULL
         GROUP BY zone_type
       ) t) AS by_zone
  )
  SELECT jsonb_build_object(
    'avg_review_hours', COALESCE(avg_review_hours, 0),
    'top_categories', COALESCE(top_categories, '[]'::jsonb),
    'by_month', COALESCE(by_month, '[]'::jsonb),
    'by_type', COALESCE(by_type, '{}'::jsonb),
    'by_zone', COALESCE(by_zone, '{}'::jsonb)
  ) INTO v_result FROM metrics;

  RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.admin_skill_suggestions_metrics() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_skill_suggestions_metrics() TO authenticated;

-- ═══ admin_bulk_reject_skill_suggestions ═══
CREATE OR REPLACE FUNCTION public.admin_bulk_reject_skill_suggestions(
  p_ids    uuid[],
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  IF p_ids IS NULL OR array_length(p_ids,1) IS NULL OR array_length(p_ids,1) = 0 THEN
    RAISE EXCEPTION 'NO_IDS_PROVIDED';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  IF array_length(p_ids,1) > 50 THEN
    RAISE EXCEPTION 'TOO_MANY_IDS_MAX_50';
  END IF;

  UPDATE skill_suggestions
  SET status = 'rejected',
      rejection_reason = p_reason,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  WHERE id = ANY(p_ids) AND status = 'pending';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'rejected_count', v_count,
    'requested_count', array_length(p_ids,1)
  );
END; $$;

REVOKE ALL ON FUNCTION public.admin_bulk_reject_skill_suggestions(uuid[], text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_bulk_reject_skill_suggestions(uuid[], text) TO authenticated;

-- ═══ admin_update_skill_suggestion_note ═══
CREATE OR REPLACE FUNCTION public.admin_update_skill_suggestion_note(
  p_id   uuid,
  p_note text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  UPDATE skill_suggestions
  SET admin_notes =
    CASE WHEN p_note IS NULL OR length(trim(p_note))=0
         THEN NULL
         ELSE p_note
    END
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUGGESTION_NOT_FOUND';
  END IF;
END; $$;

REVOKE ALL ON FUNCTION public.admin_update_skill_suggestion_note(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_skill_suggestion_note(uuid, text) TO authenticated;
