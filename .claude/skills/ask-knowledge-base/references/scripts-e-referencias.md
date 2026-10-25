# ask-knowledge-base — scripts, pré-requisitos, limitações, referências

## Scripts (em `scripts/crosstalk/`)

### `check_pending.ts`
Lista `direction='a_to_b' status='pending'` por `created_at DESC`: `id`, `created_at`, `question`, `question_context`, `skill_triggered`.
```bash
deno run --allow-env --allow-read --allow-net scripts/crosstalk/check_pending.ts
```
Saída esperada:
```
[2026-05-06T10:23:00Z] id=abc-123
  question: "App fecha quando abre o mapa, sempre reproduzivel"
  context: {"screen_name":"map","frequency":"always"}
  skill: ASK_ROBOT_B
```
Sem perguntas: `Sem perguntas pendentes do Robô A.`

### `query_knowledge.ts`
Consulta a RAG (534 chunks em `support_knowledge_chunks`) via Gemini embedding + RPC `match_knowledge`. Devolve top-N por similarity (≥0.5 por defeito).
```bash
deno run --allow-env --allow-read --allow-net scripts/crosstalk/query_knowledge.ts "como resolver crash mapa"
```

### `respond.ts`
Responde via RPC `robot_b_respond`. Marca `status='answered'`, `answered_by='robot_b'`; aceita `rag_chunks_used` (JSON array) para auditoria.
```bash
deno run --allow-env --allow-read --allow-net scripts/crosstalk/respond.ts <crosstalk_id> "texto"
deno run --allow-env --allow-read --allow-net scripts/crosstalk/respond.ts <crosstalk_id> < resposta.md
```

## Pré-requisitos
- `scripts/rag/.env` com `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (bypass RLS), `GEMINI_API_KEY` (embedding).
- Deno instalado.
- Sem `SERVICE_ROLE_KEY`: os scripts saem com mensagem clara + exit 1.

## Limitações conhecidas (5F)
- Comunicação assíncrona; sem auto-resposta.
- Sem push admin: `AdminCrosstalkScreen` tem badge realtime, push é TODO 5F-β.
- Admin é só observador: sem botão reply; RPC `admin_respond_to_crosstalk` é TODO 5F-β.
- Drift de anonimização: `_anonymize_pii` PG corrigido em 5F; o JS 5D mantém o bug — TODO 5F-β.

## Referências
- Tabela `robot_crosstalk`; RPCs `agent_ask_robot_b`, `robot_b_respond` (service_role only), `admin_list_crosstalk` (admin only), `match_knowledge`.
- Skill chatbot `ASK_ROBOT_B` mode='escalate'.
- Embedding: `gemini-embedding-001`, taskType `RETRIEVAL_QUERY`, dim 768.
- business_rules.md §39.
