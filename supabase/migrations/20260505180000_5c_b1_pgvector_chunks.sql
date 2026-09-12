-- 5C-α B1: pgvector + support_knowledge_chunks (RAG infra)
-- Sessão 5C-α/7 — preparação para RAG no support-chatbot.
-- RAG só fica activo em 5C-β via feature flag rag_enabled.

CREATE EXTENSION IF NOT EXISTS vector
  WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.support_knowledge_chunks (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  source_file   text        NOT NULL,
  source_type   text        NOT NULL
                CHECK (source_type IN
                  ('obsidian','knowledge','business_rules')),
  chunk_index   integer     NOT NULL,
  section_title text,
  chunk_text    text        NOT NULL,
  char_count    integer     GENERATED ALWAYS AS
                            (length(chunk_text)) STORED,
  content_hash  text        NOT NULL,
  embedding     extensions.vector(768),
  indexed_at    timestamptz DEFAULT now(),
  UNIQUE (source_file, chunk_index),
  UNIQUE (content_hash)
);

ALTER TABLE public.support_knowledge_chunks
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_only"
  ON public.support_knowledge_chunks
  USING (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS support_knowledge_chunks_embedding_idx
  ON public.support_knowledge_chunks
  USING hnsw (embedding extensions.vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_knowledge_source_type
  ON public.support_knowledge_chunks (source_type);

COMMENT ON TABLE public.support_knowledge_chunks IS
  'RAG knowledge base for support-chatbot (5C-α). Embeddings via Gemini text-embedding-004 (768 dims). RAG NOT active until 5C-β feature flag.';
