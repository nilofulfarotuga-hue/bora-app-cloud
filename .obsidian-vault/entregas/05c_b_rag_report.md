# Sessão 5C-β/7 — RAG injection support-chatbot · REPORT

> Data: 2026-05-06
> Branch: `autonomous-night-2026-04-29`
> Modo: PROTECÇÃO TOTAL · CEO-AI orchestrator
> Estimativa: 2-3h · Concluído (Fase B + smokes + docs)
> ⚠️ B5 (smoke prod manual + activação flag) FICA com Danilo

---

## Resumo executivo

✅ RAG infraestrutura ligada à Edge Fn `support-chatbot` v2.
✅ Feature flag `rag_enabled DEFAULT false` → zero impacto até activação manual.
✅ Cache embedding queries + timeout 1.5s + fallback graceful.
✅ Botão re-index admin activo com dropdown pending/all.

⏳ Próximo passo: **Danilo executa B5** (smoke prod 1 cenário, activação SQL,
verificação logs).

---

## Fase B — Execução

### B1 — Migration `rag_enabled` + `support_embedding_cache` ✅
- `support_settings.rag_enabled BOOLEAN NOT NULL DEFAULT false`
- Tabela `support_embedding_cache` (query_hash PK, embedding vector(768),
  hit_count, last_used_at)
- RLS `service_role_only_cache`
- Index `idx_embedding_cache_last_used`
- Migration prod: `5c_b_b1_rag_settings_cache`
- Local: `supabase/migrations/20260506000000_5c_b_b1_rag_settings_cache.sql`

### B2 — Edge Fn `reindex-knowledge` v1 ✅
- Slug: `reindex-knowledge`, ACTIVE, verify_jwt=true
- POST body: `{ mode: 'pending'|'all', max_chunks?: int (default 100, cap 500) }`
- `is_admin()` guard via user-scoped RPC → 403 NOT_ADMIN se não-admin
- Embed via `gemini-embedding-001` `RETRIEVAL_DOCUMENT` 768 dims
- Rate-limit 1 req/s, retry 3× em 429 com backoff 5s
- Return `{ reindexed, errors, mode, max_chunks, elapsed_sec, error_ids }`
- sha256 `431a2228...`

### B3 — Editar `support-chatbot` v2 ✅ (PROD LIVE)
- Deploy via Supabase CLI v2.84.4 (Docker not required)
- **Versão prévia para rollback**: v1 sha256 `ac532794...`
- **Versão nova**: v2 sha256 `d3a0c9f4...`
- Mudanças cirúrgicas:
  - `+sha256Hex()` helper (Deno crypto.subtle, fail-soft)
  - `+RAG_*` constants (endpoint, dim 768, timeout 1500ms, match 8, dedup 2/file, top 5, min_sim 0.5)
  - `+rag_enabled: boolean` em `SupportSettings` interface
  - `+ragContext: string` parâmetro em `buildSystemPrompt()` — injectado **DEPOIS** de skillsMd
  - `+buildRagContext()` async function (~110 linhas)
  - `+` bloco RAG injection após skills fetch, before buildSystemPrompt call
  - try/catch wrapper → fallback graceful (chatbot sem RAG)
- **NÃO MEXIDO**: tool-calling loop, sanitização, quota, kill switch
  `support_agent_enabled`, history fetch, anti-injection delimiters

### B4 — Botão re-index activo no `AdminKnowledgeScreen` ✅
- Removido card "desactivado/(disponível após 5C-β)"
- Dropdown "Modo": `pending` (default) / `all`
- Botão **Re-indexar agora** verde Bora — `Supabase.functions.invoke('reindex-knowledge', body: {mode, max_chunks: 100})`
- Spinner + label dinâmica durante chamada
- Modal de confirmação para mode=`all` (warning custo Gemini ~36% quota/dia)
- SnackBar: "N chunks re-indexados, K erros" (verde sucesso, vermelho erro)
- Nota inferior: kill switch SQL documentado

### B5 — Smoke prod manual (Danilo) ⏳
Documentado em `.claude/.ai/todos/sessao_5c_b_pending.md`.

---

## Smokes (resultados)

| # | Check | Resultado |
|---|---|---|
| S1 | `rag_enabled` column default false | ✅ value=false em id=1 |
| S2 | `support_embedding_cache` + RLS | ✅ table=1, RLS=true |
| S3 | `reindex-knowledge` ACTIVE | ✅ v1 |
| S4 | `support-chatbot` v2 ACTIVE | ✅ sha256 `d3a0c9f4...` |
| S5 | reindex como admin → 200 | ⚠️ inspecção manual via app |
| S6 | reindex como user → 403 NOT_ADMIN | ⚠️ inspecção manual via app |
| S7 | `match_knowledge` RPC ainda existe | ✅ |
| S8 | AdminKnowledgeScreen botão activo | ⚠️ inspecção visual |
| S9 | Dropdown mode pending/all | ⚠️ inspecção visual |
| S10 | flutter analyze 0 erros novos | ✅ 55 issues totais (igual baseline 5C-α), 0 no novo ficheiro |
| S11 | 534 chunks intactos, 534 embedded | ✅ |
| S12 | Skills active=9, settings rows=1 | ✅ |
| S13 | BUG 35/38/39 não regridem | ✅ (não tocados) |
| S14 | `support-submit-ticket` intacta | ✅ v1 unchanged |
| S15 | `final_total` tipo numeric | ✅ |

⚠️ S5/S6/S8/S9 dependem de UI/auth admin — Danilo testa via app.

---

## Bugs colaterais

**Nenhum** novo. BUG 39 reservado Sessão 7.

---

## Ficheiros criados

| Path | Tipo | Linhas |
|---|---|---|
| `supabase/migrations/20260506000000_5c_b_b1_rag_settings_cache.sql` | DDL | ~30 |
| `supabase/functions/reindex-knowledge/index.ts` | Edge Fn | ~155 |
| `.claude/.ai/todos/sessao_5c_b_pending.md` | TODOs adiados | 38 |

## Ficheiros editados

| Path | Mudança |
|---|---|
| `supabase/functions/support-chatbot/index.ts` | +RAG injection (~150 linhas, total 609) |
| `lib/screens/admin/admin_knowledge_screen.dart` | botão activo + dropdown + modal + handler `_reindex()` |
| `.claude/.ai/business_rules.md` | §35.4 reescrito + §35.6 actualizado + §35.7 novo |

---

## Migrations + Edge Functions em prod

| Tipo | Nome | Versão |
|---|---|---|
| Migration | `5c_b_b1_rag_settings_cache` | applied 2026-05-06 |
| Edge Fn | `reindex-knowledge` | v1 ACTIVE |
| Edge Fn | `support-chatbot` | v2 ACTIVE (era v1) |

---

## Próximos passos imediatos

1. **Danilo** — abrir `AdminKnowledgeScreen` no painel admin:
   - Confirmar 4 cards mostram 534 / 534 / 0 / data
   - Carregar botão "Re-indexar agora" (mode=pending, deve dizer "0 chunks
     re-indexados" pois não há pendentes)
   - Testar mode=all → modal warning aparece, cancelar
2. **Danilo** — smoke prod chatbot pré-activação:
   - App → FAB suporte → "Olá" → resposta normal sem RAG
   - Logs Edge Fn (Supabase Dashboard) → SEM linhas `[RAG]`
3. **Danilo** — activar flag via SQL:
   ```sql
   UPDATE support_settings SET rag_enabled=true WHERE id=1;
   ```
4. **Danilo** — smoke pós-activação:
   - "Qual é a comissão dos parceiros?" → resposta menciona 10%+5%+5%
   - Logs: `[RAG] cache MISS → embedded + cached` + `chunks: 8 | after dedup: 5`
   - Repetir mesma pergunta → `[RAG] cache HIT`
5. **Rollback se necessário**: Supabase Dashboard → Edge Functions → support-chatbot → restore v1.

---

*Sessão 5C-β fechada · 2026-05-06 · Aguarda Danilo para B5*
