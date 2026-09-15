-- 5C-α B2: RPC match_knowledge (similarity search HNSW cosine)

CREATE OR REPLACE FUNCTION public.match_knowledge(
  query_embedding extensions.vector(768),
  match_count     int   DEFAULT 5,
  min_similarity  float DEFAULT 0.5
)
RETURNS TABLE (
  id            uuid,
  source_file   text,
  source_type   text,
  section_title text,
  chunk_text    text,
  similarity    float
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    k.id, k.source_file, k.source_type,
    k.section_title, k.chunk_text,
    1 - (k.embedding <=> query_embedding) AS similarity
  FROM public.support_knowledge_chunks k
  WHERE k.embedding IS NOT NULL
    AND 1 - (k.embedding <=> query_embedding) >= min_similarity
  ORDER BY k.embedding <=> query_embedding
  LIMIT match_count;
$$;

REVOKE ALL ON FUNCTION public.match_knowledge(extensions.vector, int, float) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.match_knowledge(extensions.vector, int, float)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.match_knowledge IS
  'RAG similarity search (5C-α). Returns top match_count chunks by cosine similarity ≥ min_similarity. Used by support-chatbot Edge Fn in 5C-β.';
