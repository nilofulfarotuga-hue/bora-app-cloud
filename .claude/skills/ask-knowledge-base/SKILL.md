---
name: ask-knowledge-base
description: Skill do Robô B (Claude Code) para responder perguntas técnicas registadas pelo Robô A (chatbot Bora App) na tabela `robot_crosstalk` (a_to_b/pending). Use esta skill quando o utilizador pedir para verificar perguntas pendentes, consultar a knowledge base RAG (534 chunks), responder a perguntas crosstalk, ou quando referir o sistema de comunicação Robô A↔B (5F). Triggers comuns: "ver perguntas pendentes", "responder à pergunta crosstalk X", "consulta RAG sobre Y", "robot crosstalk", "ask-knowledge-base".
---

# ASK-KNOWLEDGE-BASE — Robô B (Claude Code)

Skill complementa a skill chatbot `ASK_ROBOT_B` (5F). Cliente reporta
problema técnico → tool `agent_ask_robot_b` regista em
`robot_crosstalk(direction='a_to_b', status='pending')`. Esta skill
permite ao Danilo + Claude Code consultar e responder.

## Triggers

- "ver / listar perguntas pendentes do Robô A"
- "consultar knowledge base sobre X"
- "responder à pergunta crosstalk `<id>`"
- "robot crosstalk", "ask-knowledge-base"

## Scripts disponíveis (em `scripts/crosstalk/`)

### `check_pending.ts`

Lista todas as perguntas `direction='a_to_b' status='pending'` ordenadas
por `created_at DESC`. Mostra `id`, `created_at`, `question`,
`question_context`, `skill_triggered`.

```bash
deno run --allow-env --allow-read --allow-net \
  scripts/crosstalk/check_pending.ts
```

Saída esperada:

```
[2026-05-06T10:23:00Z] id=abc-123
  question: "App fecha quando abre o mapa, sempre reproduzivel"
  context: {"screen_name":"map","frequency":"always"}
  skill: ASK_ROBOT_B
```

Se não há perguntas: `Sem perguntas pendentes do Robô A.`

### `query_knowledge.ts`

Consulta a knowledge base RAG (534 chunks indexados em
`support_knowledge_chunks`) via Gemini embedding +
`match_knowledge` RPC.

```bash
deno run --allow-env --allow-read --allow-net \
  scripts/crosstalk/query_knowledge.ts "como resolver crash mapa"
```

Saída: top-N chunks ordenados por similarity (≥0.5 default).

Use para investigar perguntas pendentes antes de responder.

### `respond.ts`

Submete resposta a uma pergunta pendente via RPC `robot_b_respond`.

```bash
# inline answer
deno run --allow-env --allow-read --allow-net \
  scripts/crosstalk/respond.ts <crosstalk_id> "Sim, é um bug conhecido. Limpa cache."

# stdin (heredoc / pipe)
deno run --allow-env --allow-read --allow-net \
  scripts/crosstalk/respond.ts <crosstalk_id> < resposta.md
```

Marca status='answered', answered_by='robot_b'. Pode incluir
`rag_chunks_used` (JSON array) para auditoria.

## Workflow típico

1. **Receber notificação** (manual ou via push admin futura 5F-β):
   Danilo / Claude Code abre `AdminCrosstalkScreen` ou corre
   `check_pending.ts`.

2. **Investigar** com `query_knowledge.ts`:
   ```bash
   query_knowledge.ts "<question>"
   ```
   Consulta RAG. Lê chunks relevantes (CLAUDE.md, business_rules.md,
   skills, etc.).

3. **Compor resposta** em markdown:
   - Resposta directa ao problema técnico
   - Soluções práticas
   - Se for bug confirmado, criar issue / nota interna

4. **Submeter** com `respond.ts`:
   ```bash
   respond.ts <id> < resposta.md
   ```

5. **Verificar** via `AdminCrosstalkScreen` que status='answered'.

## Pré-requisitos

- `scripts/rag/.env` com:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY` (bypass RLS via service_role)
  - `GEMINI_API_KEY` (para embedding em query_knowledge)
- Deno instalado

Se `SERVICE_ROLE_KEY` ausente: scripts saem com mensagem clara
+ exit 1.

## Limitações conhecidas (5F)

- **Comunicação assíncrona**: sem auto-resposta; Danilo decide
  responder manualmente.
- **Sem push admin**: AdminCrosstalkScreen tem realtime badge
  pending mas não há push notification; TODO 5F-β.
- **Admin observador apenas**: sem botão reply na UI;
  `admin_respond_to_crosstalk` RPC é TODO 5F-β.
- **Anonymization PG vs JS drift**: `_anonymize_pii` PG corrigido
  em 5F (UUID antes phone genérico); JS 5D mantém bug — TODO 5F-β.

## Referências

- Tabela: `robot_crosstalk` (Sessão 5F B1)
- RPC ask: `agent_ask_robot_b` (Sessão 5F B1)
- RPC respond: `robot_b_respond` (Sessão 5F B1, service_role only)
- RPC list: `admin_list_crosstalk` (Sessão 5F B1, admin only)
- Skill chatbot: `ASK_ROBOT_B` mode='escalate' (Sessão 5F B2)
- RPC RAG: `match_knowledge` (Sessão 5C-α)
- Embedding model: `gemini-embedding-001` taskType='RETRIEVAL_QUERY' dim=768
- business_rules.md §39 (Sessão 5F)
