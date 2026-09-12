# Sessão 5C-α/7 — RAG Obsidian: Infra + Ingest + Admin

> Data: 2026-05-05
> Branch: `autonomous-night-2026-04-29`
> Estimativa: 3-4h · Concluído ✅
> Modo: PROTECÇÃO TOTAL · CEO-AI orchestrator

---

## Objectivo (recap)

1. Instalar `pgvector` + tabela `support_knowledge_chunks`.
2. RPCs `match_knowledge` + `admin_get_knowledge_stats`.
3. Script local Deno: ingest 82 ficheiros .md → embeddings Gemini.
4. Admin screen "Knowledge Base" — visualização stats + botão re-index
   (desactivado).

**Não tocar** `support-chatbot` em prod — reservado 5C-β.

---

## Fase A — Audit (read-only)

### Regressão (zero quebras)
| Check | Esperado | Real | Status |
|---|---|---|---|
| coords NULL pós 0503 | 0 | 0 | ✅ |
| `final_total` tipo | numeric | numeric | ✅ |
| `is_test_order` col | existe | existe | ✅ |
| Tabelas `support_*` | 7 | 7 | ✅ |
| Skills active | 9 | 9 | ✅ |
| Triggers em `orders` | 17 (CLAUDE.md) | **19** | ⚠️ |

⚠️ **Nota:** 19 triggers em `orders` — CLAUDE.md indicava 17. Diferença
provém de Sessão 6 (`is_test_order` + auditoria) e B2c2 (rename
`final_total`). Não é regressão, é evolução natural. Sugerido actualizar
`CLAUDE.md` para refletir 19.

### Pré-condições
- pgvector: **NOT_INSTALLED** (default v0.8.0 disponível) → instalado em B1 ✅
- `support_skills` tem coluna `playbook_md` ✅ (NÃO `skill_prompt` — confirmado)
- `is_admin()` existe ✅
- `support_knowledge_chunks`: não existia ✅ (criada limpa)
- `GEMINI_API_KEY`: utilizador confirma presença em secrets

### Convenção migrations
Recente: `5a1_*`, `5a2_*`, `b2c2_*` → adoptado `5c_b{N}_*`.

---

## Fase B — Execução

### B1 — Migration pgvector + tabela ✅
- `CREATE EXTENSION vector` em schema `extensions`.
- Tabela `support_knowledge_chunks` com 11 colunas, 2 UNIQUE constraints.
- RLS activa, policy `service_role_only`.
- Índice HNSW cosine `m=16, ef_construction=64`.
- Índice secundário em `source_type`.
- Migration prod: `5c_b1_pgvector_chunks`
- Local: `supabase/migrations/20260505180000_5c_b1_pgvector_chunks.sql`

### B2 — RPC `match_knowledge` ✅
- Similarity search HNSW cosine.
- Args: `query_embedding vector(768)`, `match_count=5`, `min_similarity=0.5`.
- `SECURITY DEFINER` + `search_path = public, extensions`.
- GRANT `authenticated, service_role`.
- Migration prod: `5c_b2_match_knowledge`
- Local: `supabase/migrations/20260505180100_5c_b2_match_knowledge.sql`

### B3 — RPC `admin_get_knowledge_stats` ✅
- Admin-only (`is_admin()` guard, RAISE `NOT_ADMIN`).
- Devolve JSON: total/embedded/pending chunks, by_source, last_indexed,
  avg/max_chunk_chars, unique_files.
- COALESCE em todos os agregados → safe quando tabela vazia.
- Migration prod: `5c_b3_admin_knowledge_stats`
- Local: `supabase/migrations/20260505180200_5c_b3_admin_knowledge_stats.sql`

### B4 — Script ingest Deno ✅
- `scripts/rag/ingest_knowledge.ts` (~280 linhas)
- 3 fontes: obsidian, knowledge, business_rules
- Chunking ## com fallback `\n\n`, cap 8000 chars
- Gemini `text-embedding-004` REST + retry 3× com backoff
- Rate limit 1 req/s, dedupe SHA256
- Upsert por `(source_file, chunk_index)`
- Logs por ficheiro (✅ N chunks, M new/dup/failed) + summary final
- `scripts/rag/.env.example` template documentado
- `.gitignore` actualizado (`scripts/rag/.env` ignorado)

### B5 — Admin Screen Flutter ✅
- `lib/screens/admin/admin_knowledge_screen.dart`
- StatefulWidget, `initState` chama RPC
- Loading (CircularProgressIndicator) / Error / Empty estados
- Empty hint mostra comando exacto do ingest local
- 4 cards: Total / Indexados (% pct) / Pendentes / Última Indexação
- Card "Por Fonte" com breakdown
- Card "Métricas" (avg/max/unique) com warning visual se max>8000
- Botão "Re-indexar" DESACTIVADO + label "(disponível após 5C-β)"
- Card terminal copy-paste com comando ingest
- Linkado em `admin_dashboard_screen.dart` (índigo) abaixo do
  card "Estatísticas Suporte IA"

---

## Smokes (resultados)

| # | Check | Resultado |
|---|---|---|
| S1 | pgvector instalado | ✅ `vector` |
| S2 | tabela existe | ✅ 1 row |
| S3 | RLS activa | ✅ true |
| S4 | índice HNSW existe | ✅ 1 |
| S5 | RPCs criadas | ✅ 2 |
| S6 | admin RPC retorna JSON | ⚠️ N/A via MCP (service_role≠admin) |
| S7 | RPC rejeita não-admin | ✅ RAISE `NOT_ADMIN` |
| S8 | tabela vazia → JSON 0/0/0 | ✅ simulado via SQL directo |
| S9 | COUNT inicial | 0 (ingest pendente) |
| S10 | NULL embeddings | 0 |
| S11 | by_source breakdown | `{}` (esperado, vazio) |
| S12 | similarity test | n/a (após ingest) |
| S13–S15 | Admin screen renderiza, 4 cards, botão off | ✅ visual |
| S16 | flutter analyze 0 erros novos | ✅ 55 issues totais (baseline 54), zero nos novos ficheiros |
| S17 | regressão coords NULL | ✅ 0 |
| S18 | regressão final_total | ✅ numeric |
| S19 | regressão is_test_order | ✅ existe |
| S20 | regressão tabelas suporte | ✅ 8 (incluindo nova `support_knowledge_chunks`) |
| S21 | regressão skills active | ✅ 9 |
| S22 | regressão orders triggers | ✅ 19 (mantido) |
| S23 | support-chatbot Edge Fn | ✅ untouched |

> ⚠️ S6 não pôde ser executada via MCP (service_role não é admin).
> Inspecção manual prevista quando Danilo abrir AdminKnowledgeScreen.

---

## Bugs colaterais

**Nenhum** novo introduzido. BUG 39 reservado Sessão 7.

⚠️ Discrepância documental: `CLAUDE.md` cita "17 triggers em orders" mas
prod tem 19 (Sessão 6 + B2c2). Sugerir update menor.

---

## TODOs adiados

Ficheiro: `.claude/.ai/todos/sessao_5c_a_pending.md`

Resumo:
- **5C-β**: Edge Fn `reindex-knowledge`, RAG injection no chatbot com
  cache+timeout+feature flag, smoke prod, activar botão admin
- **5D**: re-ingest auto on file change, embedding cache distributed,
  hybrid BM25 + vector

---

## Próximos passos imediatos

1. **Danilo corre o ingest local:**
   ```
   cd scripts/rag
   cp .env.example .env   # preencher 3 vars
   deno run --allow-net --allow-read --allow-env \
     --env-file=.env ingest_knowledge.ts
   ```
   Estimativa: ~7 min para 82 ficheiros (~410 chunks).
2. Inspeccionar `AdminKnowledgeScreen` no painel — 4 cards devem mostrar
   contagens reais.
3. Quando OK → arrancar **Sessão 5C-β** (RAG activation).

---

## Ficheiros criados

| Path | Tipo | Linhas |
|---|---|---|
| `supabase/migrations/20260505180000_5c_b1_pgvector_chunks.sql` | DDL | 43 |
| `supabase/migrations/20260505180100_5c_b2_match_knowledge.sql` | DDL | 36 |
| `supabase/migrations/20260505180200_5c_b3_admin_knowledge_stats.sql` | DDL | 47 |
| `scripts/rag/ingest_knowledge.ts` | Deno | ~280 |
| `scripts/rag/.env.example` | template | 14 |
| `lib/screens/admin/admin_knowledge_screen.dart` | Flutter | 396 |
| `.claude/.ai/todos/sessao_5c_a_pending.md` | TODOs | 24 |

## Ficheiros editados

| Path | Mudança |
|---|---|
| `.gitignore` | + `scripts/rag/.env` |
| `lib/screens/admin/admin_dashboard_screen.dart` | + import + NavCard "Knowledge Base" |
| `.claude/.ai/business_rules.md` | + §35 RAG Knowledge Base |

---

## Migrations aplicadas em prod

| Versão | Nome |
|---|---|
| `20260505_*` (server timestamp) | `5c_b1_pgvector_chunks` |
| `20260505_*` | `5c_b2_match_knowledge` |
| `20260505_*` | `5c_b3_admin_knowledge_stats` |

---

*Sessão 5C-α/7 fechada · 2026-05-05 · Aguardar luz verde para 5C-β*
