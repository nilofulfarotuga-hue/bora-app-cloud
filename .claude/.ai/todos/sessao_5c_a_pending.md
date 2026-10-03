# TODOs adiados — Sessão 5C-α/7 (RAG Obsidian)

> Criado: 2026-05-05
> Branch: autonomous-night-2026-04-29

## 5C-β (próxima sessão) — Activar RAG em produção

- [ ] **Edge Fn `reindex-knowledge`** — wrapper server-side para corrida do
  ingest sem precisar de Deno local. Reutiliza lógica de
  `scripts/rag/ingest_knowledge.ts`. Trigger admin via screen.
- [ ] **Edição `support-chatbot`** — RAG injection ao prompt:
  - chamar `match_knowledge(query_embedding, 5, 0.5)` antes do LLM
  - cache local in-memory (TTL 5 min) para queries idênticas
  - timeout 2 s; fallback graceful para chatbot sem contexto
  - feature flag `rag_enabled` em `support_settings` DEFAULT `false`
- [ ] **Smoke prod** — 1 cenário real (pedido suporte com pergunta cobrada
  em RAG) antes de activar a flag para todos.
- [ ] **Admin botão re-index activate** — desbloquear botão na
  `AdminKnowledgeScreen` chamando `reindex-knowledge`.

## 5D (futuro)

- [ ] Re-ingest automático on file change (file watcher / Git hook).
- [ ] Embedding cache distributed (Redis/Postgres).
- [ ] Hybrid search vector + keyword BM25 (complementa similarity baixa).
- [ ] Métricas RAG: hit-rate, latência média match_knowledge,
  top chunks usados.
