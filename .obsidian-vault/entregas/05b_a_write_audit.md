# 5B-α/7 — Audit Skills WRITE Shadow + Grupo 1

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Último commit:** `7a4dd91`
**Modo:** PROTECÇÃO TOTAL (read-only audit)
**Próximo passo:** ⛔ STOP — aguardar luz verde Danilo para Fase B

---

## Sumário executivo

A auditoria detectou **5 desvios entre spec pré-validada e realidade** que exigem decisão antes de B0–B5. Nenhum mutation foi aplicado.

| # | Tópico | Spec assumiu | Realidade | Impacto |
|---|--------|--------------|-----------|---------|
| 1 | `orders.delivery_instructions` | Existe | **NÃO existe** — coluna real é `customer_notes` | 🔴 Bloqueador playbook + RPC B2 |
| 2 | `support_skills.mode` CHECK | Aceita ou alterar | CHECK actual: `('read_only','write','escalate')` — **'write' (não 'write_shadow')** | 🟡 B0 ALTER OBRIGATÓRIO |
| 3 | `pg_net` config | Verificar | `app.supabase_url` + `app.service_role_key` **AMBOS NULL** | 🔴 Path `pg_net.http_post` falha em runtime |
| 4 | OTP system no app | Existe | **NÃO existe** — só `_forgotPassword` (Supabase reset) | 🟡 OTP_RESEND propõe feature inexistente |
| 5 | "9 tools agent_get_*" | Whitelist tem 9 | Whitelist tem **5** tools (5A-1) | 🟢 Documentação spec — não bloqueia |

✅ Confirmado intacto: 9 skills (read_only/escalate, todas active), RAG `rag_enabled=true`, 534 chunks, `final_total numeric`, `is_admin()` existe, `pg_net` extension instalada, `support_chatbot_sessions.id` linkable (uuid), `support_pending_actions` ainda **não existe**.

---

## A0 — Regressão + Schema validation

### A0.1 Skills existentes (intactas)
9 skills, todas `active=true`, modes: 8× `read_only` + 1× `escalate`:
```
APP_TROUBLESHOOTING, GENERAL_FAQ, HUMAN_REQUEST (escalate),
ORDER_HISTORY, ORDER_STATUS, REFUND_STATUS,
TOKENS_INFO, WALLET_BLOCKED_HELP, WALLET_INFO
```

### A0.2 RAG / settings
- `support_settings.rag_enabled = true` ✓
- `support_knowledge_chunks count = 534` ✓
- `orders.final_total = numeric` ✓

### A0.3 Schema `support_skills`
```
id              uuid
skill_name      text
version         integer
category        text
mode            text
requires_human_handoff boolean
playbook_md     text
allowed_tools   jsonb       ← jsonb (não text[])
examples        jsonb
active          boolean
created_at      timestamptz
updated_at      timestamptz
```

### A0.4 ⚠️ CHECK constraint `mode` (CRÍTICO)
**Constraint actual:** `support_skills_mode_check`
```sql
CHECK (mode = ANY (ARRAY['read_only'::text, 'write'::text, 'escalate'::text]))
```
**Aceita:** `read_only`, `write`, `escalate`
**Não aceita:** `write_shadow`, `write_auto`

**Decisão B0:** ALTER constraint obrigatório (já estava previsto condicionalmente — agora confirmado).

### A0.5 ⚠️ pg_net settings (CRÍTICO para OTP_RESEND)
- `app.supabase_url` → **NULL**
- `app.service_role_key` → **NULL**
- `pg_net` extension instalada ✓ (mas params não populados)

**Implicação:** path `PERFORM pg_net.http_post(url := current_setting(...))` lança `EXCEPTION 'PG_NET_NOT_CONFIGURED'` em runtime → marca acção como `failed`.

**Opções para Danilo:**
- **Opção A (recomendada):** popular settings em B0 antes de seed
  ```sql
  ALTER DATABASE postgres SET app.supabase_url = '<url>';
  ALTER DATABASE postgres SET app.service_role_key = '<key>';
  ```
  ⚠️ Requer `service_role_key` em DB-level — risco segurança.
- **Opção B (mais segura):** OTP_RESEND fica seedado mas marca `EXCEPTION` enquanto config ausente. Danilo configura mais tarde via dashboard. **Skill tecnicamente activa mas sempre falha** até config — má UX.
- **Opção C (mais limpa):** **adiar OTP_RESEND para 5B-β** + remover do scope desta sessão. Seedar só `UPDATE_DELIVERY_INSTRUCTIONS` + `UPDATE_DELIVERY_ADDRESS`.

---

## A1 — Colunas orders + users

### orders (todas address/notes/delivery)
```
pickup_address          text
dropoff_address         text       ← ✓ confirmado
apartment_delivery      boolean
customer_notes          text       ← ⚠️ É AQUI que vão "instruções", não delivery_instructions
delivery_fee            numeric
delivery_price          numeric
dropoff_street          text
dropoff_city            text
dropoff_postal_code     text
dropoff_lat             numeric
dropoff_lng             numeric
```

### ⚠️ `delivery_instructions` NÃO EXISTE
A pré-validação do prompt afirmou existir. Realidade: coluna é **`customer_notes`**.

**Decisão para Danilo:**
- **Opção A (recomendada):** renomear skill para `UPDATE_CUSTOMER_NOTES` + RPC escreve em `customer_notes`. Consistente com schema actual. Zero migrations adicionais.
- **Opção B:** adicionar coluna `delivery_instructions` em B0 (`ALTER TABLE orders ADD COLUMN delivery_instructions text;`). Cria coluna duplicada (também há `customer_notes`). Não recomendado.
- **Opção C:** manter nome lógico `UPDATE_DELIVERY_INSTRUCTIONS` (skill_name + action_type) mas RPC mapeia para `customer_notes`. Compromisso: skill tem nome bonito, DB column real está protegida.

### users (campos confirmados)
- `email` ✓
- `phone` ✓ (não `phone_number`)

### orders.status
- Valores observados: `cancelled, delivered, driverAccepted, rejected` (sample distinct na DB actual; enum cobre 8 valores em código).
- **Sem CHECK constraint** — é texto livre. RPC deve validar nomes via `IN (...)`.

---

## A2 — Sistema OTP no app

**Resultado grep `lib/` para `otp|verify_phone|sendOtp|verifyOtp|signInWithOtp|resendOtp`:**

```
client_login_screen.dart:213    _forgotPassword()
driver_login_screen.dart:332    _forgotPassword()
partner_login_screen.dart:125   _forgotPassword()
```

**Conclusão:** **NÃO há fluxo OTP no Bora App actualmente.** Apenas reset password via email (Supabase Auth nativo). Skill `OTP_RESEND` propõe feature inexistente.

**Recomendação:** **adiar OTP_RESEND para 5B-β** ou remover do scope. Não faz sentido seedar skill para feature que ainda não existe na app.

---

## A3 — support_agent_actions vs support_pending_actions

### support_agent_actions (já existe — provavelmente da sessão 5A-1)
```
id, session_id, user_id, skill_name, action_type, action_payload,
proposed_at, shadow_status, reviewed_by, reviewed_at, executed_at,
result, notes
```

CHECK constraint `support_agent_actions_shadow_status_check`:
```
('pending','approved','rejected','executed','auto_executed','not_applicable')
```

### support_pending_actions (proposta nova — ainda não existe)
Spec B1 propõe colunas similares mas distintas:
- `status` (em vez de `shadow_status`) — valores: `('pending','executed','failed','rejected')`
- `execution_result` (em vez de `result`)
- `rejection_reason` (não existe em agent_actions)
- `user_message` (não existe em agent_actions)
- `agent_reasoning` (em vez de `notes`)

**Decisão para Danilo:**
- **Opção A (recomendada):** criar `support_pending_actions` nova como spec — semântica clara (fila de aprovação) ≠ `support_agent_actions` (log histórico). Sem conflito.
- **Opção B:** reutilizar `support_agent_actions` — evita tabela duplicada mas requer renomear `shadow_status` → `status` e adicionar 3 colunas. Risco regressão se 5A-1 backend usa essa tabela.

Recomendado **Opção A** (separação limpa).

---

## A4 — Análise `support-chatbot/index.ts` v2

### Localização tools[]
- `TOOL_WHITELIST` (Set, linhas 13–19): **5 tools** atualmente
  ```
  agent_get_user_orders_summary, agent_get_order_status,
  agent_get_user_wallet_summary, agent_get_user_tokens_summary,
  agent_get_refund_status
  ```
  ⚠️ Spec mencionou "9 tools" — incorrecto. São 5.

- `buildFunctionDeclarations()` (linha ~75): function declarations Gemini, paralelas ao whitelist.

### Onde inserir `agent_propose_action`
1. Adicionar string `'agent_propose_action'` ao Set `TOOL_WHITELIST` (linha 19, antes do `])`)
2. Adicionar declaração no array de `buildFunctionDeclarations()` (após o último item)
3. Tratar handler **ANTES** do `callRpc` standard — porque:
   - `callRpc()` actual usa **userJwt** (line ~145)
   - `agent_propose_action` é **`service_role` only** (per spec B2: GRANT EXECUTE TO service_role)
   - Logo: handler especial via `adminClient.rpc('agent_propose_action', ...)` em vez de `callRpc()` normal

### Variáveis disponíveis no scope handler
- `sessionId: string` ✓
- `userId: string` ✓
- `userMessage: string` (mensagem actual sanitizada — já existe, **não precisa scan messages[]**) ✓
- `adminClient` (createClient com service_role_key) ✓
- `userClient` (com userJwt)

### Tool-calling loop (linha ~340)
- Estrutura: `gemRes.data.candidates[0].content.parts.find(p => p.functionCall)`
- Após executar tool, faz `contents.push(functionCall + functionResponse)` e re-itera.
- Limite: `settings.max_tool_iterations` (config).
- **Não há "messages: tool_calls/tool_results"** — Gemini usa `parts[].functionCall` / `functionResponse`.

### Mensagens DB
- Tabela: `support_chatbot_messages` com colunas `role, content, tool_name, tool_input, tool_output`.
- Após `agent_propose_action`, deve gravar mensagem `role='tool'` com `tool_output: {proposed: true, action_id: <uuid>}`.

### Padrão handler proposto (revisão da spec B4)
```typescript
if (fnName === 'agent_propose_action') {
  const { skill_name, action_type, action_payload, agent_reasoning }
    = fnArgs as { ... };

  // Validação básica
  if (typeof action_payload !== 'object' || action_payload === null) {
    rpcRes = { ok: false, error: 'action_payload must be object' };
  } else {
    const { data: actionId, error } = await adminClient.rpc(
      'agent_propose_action',
      {
        p_session_id:      sessionId,
        p_user_id:         userId,
        p_skill_name:      skill_name,
        p_action_type:     action_type,
        p_action_payload:  action_payload,
        p_user_message:    userMessage,   // ← já existe no scope
        p_agent_reasoning: agent_reasoning,
      }
    );
    rpcRes = error
      ? { ok: false, error: error.message }
      : { ok: true, data: { proposed: true, action_id: actionId,
            message: 'Proposta criada. Aguarda aprovação do admin.' }};
  }
  // continuar com fluxo normal de gravar message tool + push contents
}
```

⚠️ Diferença vs spec B4: usar `userMessage` (já sanitizada) em vez de scan reverse de `messages` — é mais simples e correcto.

---

## A5 — Versão actual Edge Fn + impacto + riscos

### Rollback target
- **support-chatbot v2** ACTIVE
- `id`: `523cc860-52e2-4c7e-8c72-de727e7a786b`
- `sha256`: `d3a0c9f40c48f5b619b4e88c0fe357db1a1cd720453e77bf8d1d492bb6725f7e`
- `updated_at`: ~2026-04-25 (5C-β deploy)
- Rollback strategy: re-deploy source actual com `version=3` se v3 falhar.

### Migrations propostas
1. **B0** (NOVO obrigatório): `20260506_5b_b0_alter_mode_constraint` — DROP + ADD CHECK incluindo `'write_shadow'` + `'write_auto'`
2. **B1**: `20260506_5b_b1_support_pending_actions` — CREATE TABLE + RLS + indexes + publication realtime
3. **B2**: `20260506_5b_b2_shadow_rpcs` — 4 RPCs (`agent_propose_action`, `admin_approve_action`, `admin_reject_action`, `admin_list_pending_actions`)
4. **B3**: `20260506_5b_b3_seed_write_skills` — INSERT 2 ou 3 skills (depende decisão OTP_RESEND)

### Riscos identificados
| # | Risco | Mitigação |
|---|-------|-----------|
| R1 | UPDATE silent zero rows | `GET DIAGNOSTICS v_rows_affected = ROW_COUNT; IF =0 THEN RAISE EXCEPTION 'NO_ROWS_AFFECTED'` (spec B2 já tem) |
| R2 | Cast UUID inválido | `BEGIN/EXCEPTION WHEN OTHERS` em torno do cast (spec B2 já tem) |
| R3 | OTP_RESEND fire-and-forget falha | Documentar limitação + EXCEPTION se settings NULL (spec B2 já tem) — mas ver A0.5 |
| R4 | Tool confusion Gemini com 6 tools | Playbooks com few-shot (spec B3 já tem) + descrição explícita de quando usar cada |
| R5 | RLS leak — user vê acções de outro user | RLS policy `client_own_actions` filtra por `user_id = auth.uid()` (spec B1 OK) |
| R6 | service_role escrita não autorizada | RPC `agent_propose_action` é `SECURITY DEFINER` + GRANT só a `service_role`. Edge Fn usa adminClient. ✓ |
| R7 | Realtime channel sobrecarga | Publication apenas para `pending_actions` table — volume baixo. ✓ |
| R8 | **NEW** — `customer_notes` reescrita destrutiva | RPC actualiza coluna SEM merge (substitui texto antigo). Documentar em playbook + perguntar cliente confirmação no chat. |

### Impacto Flutter
- 1 ficheiro novo: `lib/screens/admin/admin_pending_actions_screen.dart`
- 1 rota nova: `/admin/pending-actions` (provavelmente em `main.dart` ou router)
- 1 link no menu admin existente (precisa identificar — `admin_dashboard_screen.dart`?)
- 0 breaking changes esperados em código existente

---

## A6 — Skill identification + recomendações

### Skill identificada (candidata)
Não há skill nova para extrair desta sessão. Padrão de auditoria multi-camada (DB schema + RLS + Edge Fn + Flutter) já estabelecido em sessões anteriores (5A, 5C).

Ficheiro `.claude/skills/identified_during_5b_a_*.md` → **não criado** (nada novo).

### Recomendações para luz verde Fase B

**Pergunta principal a Danilo:**

> Quais opções escolhes para os 4 desvios bloqueadores?

1. **`delivery_instructions` ausente** → Opção A (renomear skill para `UPDATE_CUSTOMER_NOTES`) ou Opção C (manter nome lógico, RPC mapeia)?
2. **`pg_net` settings NULL** → Opção C (adiar OTP_RESEND para 5B-β)?
3. **OTP system inexistente** → confirma Opção C acima?
4. **`support_pending_actions` separada vs reutilizar `support_agent_actions`** → Opção A (criar nova tabela)?

### Scope ajustado proposto (caso Opção A+C+C+A)

**Manter em 5B-α:**
- B0 ALTER mode CHECK constraint
- B1 CREATE support_pending_actions
- B2 4 RPCs (sem `OTP_RESEND` no CASE — ou com EXCEPTION explícito)
- B3 seed **2 skills** (`UPDATE_CUSTOMER_NOTES` + `UPDATE_DELIVERY_ADDRESS`)
- B4 edição support-chatbot (1 tool decl + 1 handler — usar `userMessage` em vez de scan)
- B5 AdminPendingActionsScreen

**Adiar para 5B-β (já listado em TODOs adiados):**
- OTP_RESEND skill + playbook + spec
- Configuração `app.supabase_url` / `app.service_role_key` (decisão arquitectural)
- Decisão final sobre custom OTP flow vs Supabase Auth nativo

---

## ⛔ STOP — A aguardar luz verde

Phase B inicia **só após** decisões nos 4 pontos acima.

Próximo prompt esperado: `"ok B com Opções [A/B/C…] — prossegue"` ou variantes.
