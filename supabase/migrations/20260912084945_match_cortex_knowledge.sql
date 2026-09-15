-- Busca vetorial restrita ao Córtex curado. A tabela continua privada por RLS;
-- somente o service_role usado pelo servidor MCP pode executar esta função.
CREATE OR REPLACE FUNCTION public.match_cortex_knowledge(
  query_embedding extensions.vector(768),
  match_count integer DEFAULT 6,
  min_similarity double precision DEFAULT 0.42
)
RETURNS TABLE (
  id uuid,
  source_file text,
  source_type text,
  section_title text,
  chunk_text text,
  similarity double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    k.id,
    k.source_file,
    k.source_type,
    k.section_title,
    k.chunk_text,
    1 - (k.embedding OPERATOR(extensions.<=>) query_embedding) AS similarity
  FROM public.support_knowledge_chunks AS k
  WHERE k.source_type = 'knowledge'
    AND (
      k.source_file IN (
        '.claude/.ai/knowledge/INDEX.md',
        '.claude/.ai/knowledge/PROTOCOLO.md'
      )
      OR k.source_file LIKE '.claude/.ai/knowledge/permanente/%'
    )
    AND k.embedding IS NOT NULL
    AND 1 - (k.embedding OPERATOR(extensions.<=>) query_embedding) >= min_similarity
  ORDER BY k.embedding OPERATOR(extensions.<=>) query_embedding
  LIMIT LEAST(GREATEST(match_count, 1), 10);
$$;

REVOKE ALL ON FUNCTION public.match_cortex_knowledge(extensions.vector, integer, double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_cortex_knowledge(extensions.vector, integer, double precision)
  TO service_role;

COMMENT ON FUNCTION public.match_cortex_knowledge IS
  'Busca semântica privada somente no INDEX, PROTOCOLO e memória permanente do Córtex.';

