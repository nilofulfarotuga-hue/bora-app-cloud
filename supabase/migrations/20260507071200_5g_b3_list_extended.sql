-- 5G B3: REPLACE admin_list_skill_suggestions com 6 params
-- (DROP da versão antiga 2-param + CREATE com defaults backward-compat)

DROP FUNCTION IF EXISTS public.admin_list_skill_suggestions(text, int);
DROP FUNCTION IF EXISTS public.admin_list_skill_suggestions(text, text, text, text, text, int);

CREATE OR REPLACE FUNCTION public.admin_list_skill_suggestions(
  p_status   text DEFAULT 'pending',
  p_type     text DEFAULT 'all',
  p_zone     text DEFAULT 'all',
  p_category text DEFAULT 'all',
  p_search   text DEFAULT NULL,
  p_limit    int  DEFAULT 50
)
RETURNS TABLE (
  id uuid, suggested_at timestamptz, status text,
  pattern_summary text, sample_messages jsonb,
  message_count int, suggested_skill_name text,
  suggested_category text, suggested_mode text,
  suggested_playbook_md text, suggested_allowed_tools jsonb,
  reviewed_at timestamptz, reviewed_by uuid,
  rejection_reason text, implemented_skill_id uuid,
  implemented_at timestamptz, gemini_model text,
  proposal_type text, zone_type text,
  target_skill_id uuid, target_setting_key text,
  target_setting_value text, previous_value text,
  admin_notes text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  RETURN QUERY
  SELECT s.id, s.suggested_at, s.status,
         s.pattern_summary, s.sample_messages,
         s.message_count, s.suggested_skill_name,
         s.suggested_category, s.suggested_mode,
         s.suggested_playbook_md, s.suggested_allowed_tools,
         s.reviewed_at, s.reviewed_by,
         s.rejection_reason, s.implemented_skill_id,
         s.implemented_at, s.gemini_model,
         s.proposal_type, s.zone_type,
         s.target_skill_id, s.target_setting_key,
         s.target_setting_value, s.previous_value,
         s.admin_notes
  FROM skill_suggestions s
  WHERE (p_status = 'all' OR s.status = p_status)
    AND (p_type = 'all' OR s.proposal_type = p_type)
    AND (p_zone = 'all' OR s.zone_type = p_zone)
    AND (p_category = 'all' OR s.suggested_category = p_category)
    AND (p_search IS NULL OR
         to_tsvector('portuguese', coalesce(s.pattern_summary,''))
         @@ plainto_tsquery('portuguese', p_search))
  ORDER BY
    CASE s.status
      WHEN 'pending'       THEN 1
      WHEN 'implemented'   THEN 2
      WHEN 'approved'      THEN 3
      WHEN 'rejected'      THEN 4
      WHEN 'rolled_back'   THEN 5
      WHEN 'auto_archived' THEN 6
      ELSE 7
    END,
    CASE s.zone_type
      WHEN 'critical' THEN 1
      WHEN 'safe'     THEN 2
      ELSE 3
    END,
    s.suggested_at DESC
  LIMIT p_limit;
END; $$;

REVOKE ALL ON FUNCTION public.admin_list_skill_suggestions(text, text, text, text, text, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_skill_suggestions(text, text, text, text, text, int) TO authenticated;
