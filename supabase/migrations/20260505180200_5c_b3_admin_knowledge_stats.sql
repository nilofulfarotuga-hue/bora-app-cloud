-- 5C-α B3: RPC admin_get_knowledge_stats (admin painel)

CREATE OR REPLACE FUNCTION public.admin_get_knowledge_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  SELECT jsonb_build_object(
    'total_chunks',    COUNT(*),
    'embedded_chunks', COUNT(*) FILTER
                       (WHERE embedding IS NOT NULL),
    'pending_chunks',  COUNT(*) FILTER
                       (WHERE embedding IS NULL),
    'by_source', COALESCE((
      SELECT jsonb_object_agg(source_type, cnt)
      FROM (
        SELECT source_type, COUNT(*) AS cnt
        FROM public.support_knowledge_chunks
        GROUP BY source_type
      ) s
    ), '{}'::jsonb),
    'last_indexed',    MAX(indexed_at),
    'avg_chunk_chars', COALESCE(ROUND(AVG(char_count)), 0),
    'max_chunk_chars', COALESCE(MAX(char_count), 0),
    'unique_files',    COUNT(DISTINCT source_file)
  )
  INTO result
  FROM public.support_knowledge_chunks;

  RETURN COALESCE(result, '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_knowledge_stats()
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_knowledge_stats()
  TO authenticated;

COMMENT ON FUNCTION public.admin_get_knowledge_stats IS
  'Admin-only RAG stats for AdminKnowledgeScreen (5C-α). Throws NOT_ADMIN if caller is not admin.';
