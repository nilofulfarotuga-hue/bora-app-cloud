# Sessão 5C-β/7 — Prompt original (cópia)

> Data: 2026-05-05
> Branch: `autonomous-night-2026-04-29`
> Estimativa: 2-3h · PROTECÇÃO TOTAL · Opus 4.7
> Toca PROD (support-chatbot Edge Fn LIVE)

## Objectivo
Activar RAG no support-chatbot:
1. Migration: `support_settings.rag_enabled` + `support_embedding_cache`
2. Edge Fn `reindex-knowledge` (modes pending/all)
3. Editar `support-chatbot` — RAG injection + cache + timeout + fallback
4. Smoke prod 1 cenário (Danilo manual) → activar flag manual
5. Activar botão re-index no AdminKnowledgeScreen com dropdown modo

## NÃO MEXER
- 5C-α infra (chunks/RPCs/admin screen)
- support-submit-ticket Edge Fn
- 6 RPCs agente IA (5A-1)
- Tool-calling logic em support-chatbot

## Versão actual rollback
support-chatbot version = 1 (sha256 ac532794...), deploy → versão 2.

## Fases
- **Fase A** — Audit (A0-A5) → STOP ✅
- **Fase B** — Execução (B1-B5) após luz verde

## Resultado Phase A
✅ Modelo `gemini-embedding-001` + `RETRIEVAL_DOCUMENT` (768 dims) compatível
com chunks 5C-α — REINDEX DESNECESSÁRIO. Ponto de injecção RAG identificado
em `support-chatbot/index.ts` entre L190 (skills fetch) e L192
(`buildSystemPrompt`). Variáveis no scope: `userMessage`, `adminClient`,
`GEMINI_API_KEY`, `settings`, `skillsMd`. ✅
