-- 5C-β B1: feature flag rag_enabled + cache embedding queries

ALTER TABLE public.support_settings
  ADD COLUMN IF NOT EXISTS rag_enabled BOOLEAN
    NOT NULL DEFAULT false;

COMMENT ON COLUMN public.support_settings.rag_enabled IS
  'Feature flag (5C-β). Quando true, support-chatbot injecta RAG context vindo de support_knowledge_chunks. Kill switch: UPDATE support_settings SET rag_enabled=false WHERE id=1';

CREATE TABLE IF NOT EXISTS public.support_embedding_cache (
  query_hash    text PRIMARY KEY,
  query_text    text NOT NULL,
  embedding     extensions.vector(768) NOT NULL,
  created_at    timestamptz DEFAULT now(),
  last_used_at  timestamptz DEFAULT now(),
  hit_count     int NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_embedding_cache_last_used
  ON public.support_embedding_cache(last_used_at);

ALTER TABLE public.support_embedding_cache
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_only_cache"
  ON public.support_embedding_cache
  USING (auth.role() = 'service_role');

COMMENT ON TABLE public.support_embedding_cache IS
  'Cache de embeddings de queries de suporte (5C-β). query_hash = SHA256(lower(trim(query)).slice(0,500)). TTL informal: cleanup periódico de entries last_used_at > 7 days (5D).';
