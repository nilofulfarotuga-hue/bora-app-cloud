# Sessão 5C-β/7 — RAG injection support-chatbot · AUDIT

> Data: 2026-05-05
> Branch: `autonomous-night-2026-04-29`
> Modo: PROTECÇÃO TOTAL · Phase A read-only
> CEO-AI: aprovou Phase A · Phase B aguarda luz verde

---

## A0 — Regressão (zero quebras)

| Check | Esperado | Real | Status |
|---|---|---|---|
| `support_knowledge_chunks` total | 534 | 534 | ✅ |
| Embedded chunks (NOT NULL) | 534 | 534 | ✅ |
| `by_source` | obs:471, kn:26, br:37 | obs:471, kn:26, br:37 | ✅ |
| `final_total` tipo | numeric | numeric | ✅ |
| coords NULL pós 0503 | 0 | 0 | ✅ |
| skills active | 9 | 9 | ✅ |
| triggers em `orders` | ≥17 | 19 | ✅ (sem regressão vs 5C-α) |

## Versão actual `support-chatbot` (PARA ROLLBACK)

```
ID:     523cc860-52e2-4c7e-8c72-de727e7a786b
Slug:   support-chatbot
Version: 1   ← versão actual LIVE
Status: ACTIVE
verify_jwt: true
sha256: ac5327949a8db78a2e819c454df68199979f8c9c35f9bab243c2d07d406b26c4
created/updated: 2026-04-30 (timestamp 1777917483827)
```

**Em caso de necessidade rollback:** Supabase Dashboard → Edge Functions
→ support-chatbot → versions → restore v1.

---

## A1 — Análise `support-chatbot/index.ts`

**Total linhas:** 282 (single-file `index.ts`, sem deno.json/import_map).

### Pontos críticos identificados

| Função/var | Linha aprox. | Observação |
|---|---|---|
| `SYSTEM_DELIM_OPEN/CLOSE` | 23-24 | Anti-injection: queries com estes literais são rejeitadas |
| `sanitizeMessage()` | 39-49 | Strip control chars, cap em `max_user_message_chars`, valida não-vazio |
| `buildFunctionDeclarations()` | 51-60 | 5 tools whitelisted (já existem) |
| **`buildSystemPrompt()`** | 62-83 | **PONTO DE INJECÇÃO RAG** — recebe `skillsMd` e injecta no prompt |
| `callGemini()` | 92-110 | Endpoint `models/{settings.gemini_model}:generateContent` |
| **Settings fetch** | 137 | `from('support_settings').select('*').eq('id',1).single()` — sem cache, single SELECT por call. ✅ Adicionar `rag_enabled` é zero-cost |
| Quota check | 149-156 | rate_limit + max_messages_per_session |
| Session create/load | 158-180 | `support_chatbot_sessions` |
| **History fetch** | 184-187 | últimas 10 mensagens |
| **Skills fetch** | 189-190 | `from('support_skills').select('skill_name, playbook_md').eq('active', true)` ✅ confirma `playbook_md` (NÃO `skill_prompt`) |
| **System prompt build** | 192 | `buildSystemPrompt(userRole, payload.order_id, settings, skillsMd)` — **injectar `ragContext` aqui via parâmetro adicional** |
| Tool-calling loop | 207-241 | Whitelist + rpc + iter max — **NÃO MEXER** |

### Variáveis no scope da injecção (linha ~191)

| Variável | Tipo | Disponível? |
|---|---|---|
| `userMessage` | string sanitized | ✅ |
| `adminClient` | SupabaseClient (service_role) | ✅ |
| `userClient` | SupabaseClient (user JWT) | ✅ |
| `GEMINI_API_KEY` | string | ✅ |
| `settings` | row support_settings | ✅ (incluirá `rag_enabled` após B1) |
| `skillsMd` | string | ✅ |

### Estratégia injecção (B3)

1. Adicionar helper `sha256Hex()` no topo (Deno crypto.subtle).
2. Bloco RAG injectado **entre** linha 190 (skills fetch) e 192 (build prompt):
   - Lookup cache `support_embedding_cache` por `query_hash`
   - Cache miss → chamar `gemini-embedding-001` com `RETRIEVAL_QUERY` + `outputDimensionality:768`, timeout 1.5s via AbortController
   - `match_knowledge` RPC top-8, dedup max 2/source_file → top-5
   - Construir `ragContext` (header `=== CONHECIMENTO BORA APP ===`)
3. Modificar `buildSystemPrompt()` para aceitar `ragContext` opcional e
   appendá-lo **DEPOIS** do `skillsMd` (skills primeiro = ordem de prioridade).
4. Try/catch envolve TODO o bloco RAG → falha graceful = chatbot sem RAG (comportamento actual mantido).

---

## A2 — Estado `support_settings`

```
Colunas actuais: id, whatsapp_number, support_email, chatbot_welcome_text,
sla_hours, gemini_model, rate_limit_per_user_day, max_messages_per_session,
max_output_tokens_per_call, max_user_message_chars, max_tool_iterations,
shadow_mode, support_agent_enabled, updated_at
```

- `rag_enabled` **NÃO existe** → criar em B1 (DEFAULT false)
- `support_embedding_cache` **NÃO existe** → criar em B1

---

## A3 — VALIDAÇÃO CRÍTICA modelo embedding ✅

### a) `scripts/rag/ingest_knowledge.ts` (commit `847574f`)

```typescript
const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent";
const EMBED_DIM = 768;

body: JSON.stringify({
  content: { parts: [{ text }] },
  taskType: "RETRIEVAL_DOCUMENT",
  outputDimensionality: EMBED_DIM,
}),
```

### b) Verificação DB

| Check | Resultado |
|---|---|
| `vector_dims(embedding)` sample | **768** ✅ |
| `unique_files` | 65 |
| chunk metrics (avg/max/min chars) | 792 / 7 475 / 23 |

### Decisão

✅ **COMPATÍVEL.** Modelo `gemini-embedding-001` + `outputDimensionality:768` em
ingest. 5C-β usará o **mesmo modelo** mas com `taskType: RETRIEVAL_QUERY` para
queries (par correcto query↔doc).

🚫 **REINDEX DESNECESSÁRIO.** Os 534 chunks são reutilizáveis directamente.

---

## A4 — Análise impacto

### Latência

| Caso | Custo extra | Total estimado |
|---|---|---|
| RAG OFF (flag false) | +0 ms (try/catch wrapping skip) | igual ao actual (~2-3s) |
| RAG ON / cache HIT | ~50ms (SELECT cache + match_knowledge) | ~2-3s + ~50ms |
| RAG ON / cache MISS | +1-1.5s (embedding query) | ~3-4s 1ª vez |
| RAG ON / Gemini timeout | 1.5s (abort) → fallback sem RAG | ~3.5-4.5s mas RAG ausente |

### Tokens

System prompt cresce até ~5K chars com 5 chunks dedup × ~1K avg → ~1.25K tokens
extra input. Gemini Flash custo: €0.067/M input → ~€0.000084/call extra.

### UX

- **Risco**: 1ª pergunta após cold-start sente +1.5s. Aceitável em chat suporte (não tempo-real).
- **Mitigação**: cache pós-1ª query elimina latência para queries repetidas.

### Riscos PROD

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Embedding API down | Baixa | timeout 1.5s + fallback sem RAG |
| Cache miss storm na 1ª hora | Médio | cache populado rapidamente; 1.5s tolerável |
| Quota Gemini esgotada | Baixa | quota grande comparada a uso suporte |
| Chunks irrelevantes top-5 | Médio | min_similarity=0.5 + dedup por source_file |
| Tool-calling quebra (regressão) | **Mitigado** | injecção é APENAS no system prompt, NÃO no loop de tools |

---

## A5 — Próximos passos + Skill identification

### Aguarda luz verde Danilo para:
- B1 migration (rag_enabled + support_embedding_cache)
- B2 Edge Fn `reindex-knowledge`
- B3 edição cirúrgica `support-chatbot` (versão actual = 1, deploy → versão 2)
- B4 botão re-index no AdminKnowledgeScreen
- B5 smoke prod manual + activação flag (Danilo)

### Skill identification

Nenhuma skill nova identificada nesta fase A.

### Sync Obsidian

- `.claude/.ai/reports/20260502_megafinal/05c_b_rag_audit.md` (este ficheiro)
- Cópia → `.obsidian-vault/entregas/05c_b_rag_audit.md`
- Prompt sessão → `.obsidian-vault/sessões/05c_b_prompt.md`

---

## Resumo executivo (1 linha)

✅ Fase A limpa, modelo gemini-embedding-001 compatível com chunks 5C-α
(zero reindex), versão `support-chatbot` LIVE = 1 anotada para rollback,
ponto injecção RAG identificado entre skills fetch (L190) e
`buildSystemPrompt` (L192). Pronto para Fase B após luz verde.
