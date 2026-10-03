# TODOs adiados — Sessão 5C-β/7 (RAG activation)

> Criado: 2026-05-06
> Branch: `autonomous-night-2026-04-29`

## 5C-β follow-ups (smoke prod manual — Danilo)

- [ ] **Smoke 1**: pós-deploy v2, `rag_enabled=false` (default) — chat
  responde sem `[RAG]` nos logs Edge Fn
- [ ] **Activar flag**: `UPDATE support_settings SET rag_enabled=true WHERE id=1`
- [ ] **Smoke 2**: pergunta "Qual a comissão dos parceiros?" — logs devem
  mostrar `[RAG] cache MISS → embedded + cached` + `chunks: 8 | after dedup: 5`
- [ ] **Smoke 3**: mesma pergunta repetida — `[RAG] cache HIT`
- [ ] **Smoke 4**: pergunta off-topic ("Que tempo está hoje?") — `[RAG] no chunks above threshold`
- [ ] **Kill switch**: `UPDATE support_settings SET rag_enabled=false` + verificar próxima query sem `[RAG]`
- [ ] **Rollback**: se necessário, Supabase Dashboard → Edge Fn → support-chatbot → restore v1 (sha256 ac532794...)

## 5D (futuro)

- [ ] **Cron cleanup `support_embedding_cache`**: DELETE WHERE `last_used_at` < now() - 7 days
- [ ] **Métricas RAG**:
  - cache hit rate (%)
  - top queries (frequência)
  - latência média `match_knowledge`
  - cobertura: % perguntas com chunks above threshold
- [ ] **Re-ingest automático on file change** (file watcher / Git hook)
- [ ] **Hybrid search**: vector + keyword BM25 (complementa similarity baixa)
- [ ] **Re-ranking layer**: cross-encoder (e.g., mxbai-rerank) sobre top-N
- [ ] **Embedding batch**: processar múltiplos chunks numa só chamada Gemini
  (`batchEmbedContents`) para acelerar reindex

## Notas técnicas para 5D

- `support_embedding_cache` cresce indefinidamente sem cleanup. Espera-se
  ~50-200 entries/dia em prod. Cron mensal deve chegar.
- `match_knowledge` HNSW retorna top-N rapidamente; latência ~50ms para
  534 chunks. Escalável até ~50K chunks sem rebuild do índice.
- Custo embedding query (RETRIEVAL_QUERY): ~€0.000084/call. Free tier
  Gemini suporta 100 RPD para `gemini-embedding-001`. Cache mitiga
  exhaustion.
