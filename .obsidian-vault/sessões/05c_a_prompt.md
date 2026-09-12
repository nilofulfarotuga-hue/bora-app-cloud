# Sessão 5C-α/7 — Prompt original (cópia para Obsidian)

> Data: 2026-05-05
> Branch: `autonomous-night-2026-04-29`
> Modo: PROTECÇÃO TOTAL · Opus 4.7 obrigatório
> Estimativa real: ~3h (Audit + Execução + Smokes + Sync)

---

## Objectivo

1. Instalar pgvector + tabela support_knowledge_chunks
2. Criar RPCs match_knowledge + admin_get_knowledge_stats
3. Script local Deno: ingest 82 ficheiros .md → embeddings
4. Admin screen "Knowledge Base"

5C-β trata: reindex Edge Fn + RAG injection no support-chatbot
+ feature flag activation + smoke prod.

## Pré-requisito

Sessões 1-6 + B2 commit 2 fechadas em prod.

## NÃO MEXER

- dispatch engine, pricing_calculate, finalize_storeshopping
- create_order, wallet RPCs, Stripe core
- 6 RPCs agente IA (5A-1) + admin_resolve_ticket
- 2 Edge Fns suporte (support-chatbot, support-submit-ticket)
- TOKENS Batch D, 7 Reservation RPCs
- 17 (→19) triggers em orders
- pg_cron wallet_overdue_alerts
- 5 camadas defesa productId 4C
- BUG 35, BUG 38 — REGRESSÃO
- BUG 39 (Sessão 7)

## Fases

- **Fase A** — Audit read-only (A0-A10) → STOP
- **Fase B** — Execução (B1-B5) → smokes → relatório → STOP

## Commits atómicos por bloco lógico

- `feat(5c-a-b1): pgvector + support_knowledge_chunks table`
- `feat(5c-a-b2): match_knowledge RPC (HNSW cosine)`
- `feat(5c-a-b3): admin_get_knowledge_stats RPC`
- `feat(5c-a-b4): RAG ingest script (Deno + Gemini text-embedding-004)`
- `feat(5c-a-b5): AdminKnowledgeScreen + dashboard link`

## Resultado

✅ Fechada com sucesso. Relatório completo em
`.obsidian-vault/entregas/05c_a_rag_report.md`.

Próximo passo: Danilo corre o ingest local; quando OK, arrancar 5C-β.
