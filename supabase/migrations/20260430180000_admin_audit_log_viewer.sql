-- ============================================================================
-- BORA — Admin Audit Log Viewer (Feature 3)
-- ============================================================================
-- RPC paginada para o ecrã admin_audit_log_screen.dart (UI Flutter).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_list_audit_log(
  p_search      TEXT        DEFAULT NULL,
  p_action_type TEXT        DEFAULT NULL,
  p_admin_id    UUID        DEFAULT NULL,
  p_date_from   TIMESTAMPTZ DEFAULT NULL,
  p_date_to     TIMESTAMPTZ DEFAULT NULL,
  p_limit       INT         DEFAULT 100,
  p_offset      INT         DEFAULT 0
)
RETURNS SETOF public.admin_audit_log
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT * FROM public.admin_audit_log
    WHERE
      (p_action_type IS NULL OR action ILIKE '%'||p_action_type||'%')
      AND (p_admin_id IS NULL OR admin_id = p_admin_id)
      AND (p_date_from IS NULL OR created_at >= p_date_from)
      AND (p_date_to   IS NULL OR created_at <= p_date_to)
      AND (p_search IS NULL OR
           action ILIKE '%'||p_search||'%' OR
           admin_email ILIKE '%'||p_search||'%' OR
           details::text ILIKE '%'||p_search||'%')
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_audit_log(TEXT,TEXT,UUID,TIMESTAMPTZ,TIMESTAMPTZ,INT,INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_audit_log(TEXT,TEXT,UUID,TIMESTAMPTZ,TIMESTAMPTZ,INT,INT) TO authenticated;

-- Lista de tipos de acção únicos para dropdowns
CREATE OR REPLACE FUNCTION public.admin_list_audit_action_types()
RETURNS TABLE (action TEXT, count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT al.action, COUNT(*)::bigint
    FROM public.admin_audit_log al
    GROUP BY al.action
    ORDER BY COUNT(*) DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_audit_action_types() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_audit_action_types() TO authenticated;

COMMIT;
