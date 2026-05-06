# 5B-β1/7 — Audit Skills WRITE Grupo 2 + Push Admin

**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Último commit:** `b994f8b` (5B-α)
**Modo:** PROTECÇÃO TOTAL (read-only audit)
**Próximo passo:** ⛔ STOP — aguardar luz verde Danilo + decisões scope

---

## Sumário executivo

A auditoria detectou **4 desvios críticos entre spec pré-validada e realidade** que exigem decisões de scope antes de B1–B4.

| # | Tópico | Spec assumiu | Realidade | Impacto |
|---|--------|--------------|-----------|---------|
| 1 | `users.full_name` | Existe | **NÃO existe** — coluna real é `name` (text) | 🟡 Renomear no playbook + RPC |
| 2 | `notify-client` suporta email | Para `password_reset`/`otp_resend` | É **FCM-only** (push) — sem path para email | 🔴 PASSWORD_RESET inviável via notify-client |
| 3 | `client-cancel-order` chamável via service_role | Spec: pg_net + service_role | Função valida `auth.getUser()` + `order.user_id === user.id` → 403 | 🔴 CANCEL_PRE_PURCHASE inviável via pg_net |
| 4 | `users.email` populated | Sim | **NULL para muitos users** (incluindo admin) | 🟡 PASSWORD_RESET deve ler de `auth.users` |

✅ **Confirmado intacto e pronto:** RAG enabled, 534 chunks, `final_total numeric`, `support_pending_actions` (0 rows após cleanup smoke), 4 RPCs shadow, 11 skills, 2 skills WRITE 5B-α, support-chatbot v3 ACTIVE.
✅ **Bonus discovered:** Admin Danilo tem `fcm_token` populated → push admin **viável** se `pg_net` settings forem populados.

---

## A0 — Regressão check

### Skills (11 total)
- 8 read_only: APP_TROUBLESHOOTING, GENERAL_FAQ, ORDER_HISTORY, ORDER_STATUS, REFUND_STATUS, TOKENS_INFO, WALLET_BLOCKED_HELP, WALLET_INFO
- 1 escalate: HUMAN_REQUEST
- 2 write_shadow (5B-α): UPDATE_DELIVERY_INSTRUCTIONS, UPDATE_DELIVERY_ADDRESS — ambas `allowed_tools=["agent_propose_action"]`

### Estado infra 5B-α
- `support_pending_actions` CHECK status: `('pending','executed','failed','rejected')` ✓
- 4 RPCs shadow existem: `agent_propose_action`, `admin_approve_action`, `admin_reject_action`, `admin_list_pending_actions`
- Tabela vazia (0 rows após smoke cleanup) — pronta para uso real
- RAG: enabled=true, 534 chunks ✓
- `orders.final_total = numeric` ✓
- `support-chatbot v3` ACTIVE (rollback target) — sha `c4d734f0...`

---

## A1 — Schema users (CRÍTICO)

### Colunas reais de `public.users`
```
id, created_at, name, email, phone, role, fcm_token, photo_url
```

⚠️ **`full_name` NÃO existe** — coluna real é **`name`** (text).
Spec B1 ACCOUNT_UPDATE precisa usar `name` em todos os lados (RPC, playbook, tool description).

### users vs auth.users — caveat email
- `public.users.email` é **NULL para muitos registos** (incluindo admin Danilo)
- `auth.users.email` é fonte de verdade
- Para PASSWORD_RESET o RPC precisa fazer `SELECT email FROM auth.users WHERE id = v_action.user_id`

---

## A2 — Mecanismo PASSWORD_RESET (BLOQUEADOR)

### Análise `notify-client/index.ts`
- Função é **FCM-only** (push notifications via Firebase Cloud Messaging)
- Body esperado: `{clientId, orderId, status, title, body, vendorName, driverName, etaMinutes}`
- `statusMessage()` switch só para: `preparing | callingDriver | driverAccepted | pickedUp | onTheWay | delivered`
- **NÃO** suporta `type: 'password_reset'` ou `type: 'otp_resend'`
- Lookup `fcm_token` em `users` → envia push via Firebase

### Conclusão
Path proposto pelo spec (`pg_net → notify-client com type='password_reset'`) **NÃO funciona**.

### Opções para PASSWORD_RESET

| Opção | Descrição | Custo | Recomendação |
|-------|-----------|-------|--------------|
| **A** | Estender `notify-client` com case `password_reset` (envia email via SMTP) | Médio — mistura push+email num só fn | ❌ Confunde responsabilidades |
| **B** | Criar Edge Fn nova `support-password-reset` (usa `supabase.auth.resetPasswordForEmail` ou `auth.admin.generateLink`) | Médio — fn nova mas focada | ✅ Cleanest |
| **C** | Fechar 5B-β1 sem PASSWORD_RESET; abrir 5B-β1b dedicada | Baixo — simples split | ✅ Mais seguro |

**Recomendação:** Opção C (split). Mantém 5B-β1 focado em ACCOUNT_UPDATE + scope reduzido.

---

## A3 — admin_approve_action — estrutura para extender

### Top-level DECLARE actual (5B-α)
```plpgsql
DECLARE
  v_action        support_pending_actions;
  v_result        jsonb;
  v_rows_affected int;
  v_order_id      text;
  v_target_status text := 'executed';
BEGIN
  IF NOT public.is_admin() ...
  SELECT * INTO v_action ... FOR UPDATE;
  ...
  BEGIN
    CASE v_action.action_type
      WHEN 'UPDATE_DELIVERY_INSTRUCTIONS' THEN ...
      WHEN 'UPDATE_DELIVERY_ADDRESS' THEN ...
      ELSE RAISE EXCEPTION 'UNKNOWN_ACTION_TYPE: %', v_action.action_type;
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    v_target_status := 'failed';
    v_result := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE);
  END;
  ...
END;
```

### Estratégia para novos WHEN
- DECLARE top-level já tem `v_order_id text`, `v_rows_affected int`, `v_action`, `v_result`
- Variáveis novas (`v_user_email`, `v_new_name`, `v_new_phone`, `v_updated jsonb`) → **adicionar ao top-level** (mais simples) OU usar **sub-blocos** `BEGIN DECLARE ... BEGIN ... END;` dentro de cada WHEN (idiomatic mas mais verboso)
- Recomendação: top-level (3-4 vars extra, sem overhead)

---

## A4 — support-chatbot v3 (já analisado em 5B-α)

### Pontos de inserção
- `TOOL_WHITELIST`: adicionar 3 tool names novos (uma linha por tool)
- `WRITE_SHADOW_ACTION_TYPES`: adicionar 3 action_types novos
- `buildFunctionDeclarations()`: adicionar 3 declarações (com enums restritos a 1 valor cada)
- Handler switch: `case 'agent_propose_action':` actual já reusa lógica — extender com 3 `case` extra dispatch para mesma branch

### Decisão de design
Spec sugere **3 tools especializadas** (uma por skill) em vez de 1 tool genérica. Tradeoff:
- **Pros**: Gemini tem mais clareza sobre quando usar cada tool (descrição focada por skill)
- **Cons**: ~50 linhas extra em `buildFunctionDeclarations()` + 3 cases extra no switch

Vou seguir spec (3 tools especializadas).

---

## A5 — fcm_token admin Danilo

### Resultado SQL
```
auth.users.email = nilofulfarotuga@gmail.com
auth.uid = c9fccf85-03ee-4efc-83bf-613f211a78ff
public.users.fcm_token = SET ✓
public.users.email = NULL (mas auth tem)
public.users.name = NULL
public.users.role = NULL
```

### Implicação para B2 (trigger push admin)
- Push **viável** — fcm_token populated
- `notify-client` precisa `clientId` (= admin user_id) → o trigger pode chamar `notify-client` com `clientId = c9fccf85-...`
- ⚠️ **MAS** `pg_net` settings (`app.supabase_url`, `app.service_role_key`) ainda **NULL** (validado em 5B-α A0.5)
- Sem essas settings o trigger faz `IF current_setting(...) IS NOT NULL` → skip silently → log only fallback

### Recomendação
Implementar trigger **com guard `IS NOT NULL`** (sem RAISE EXCEPTION para não bloquear INSERT). Quando `pg_net` settings forem configuradas (futura sessão), o trigger passa a enviar push automaticamente.

---

## A6 — Análise impacto + riscos (CRÍTICO)

### `client-cancel-order` chamável via pg_net? **NÃO** (revelação)

Análise da função `client-cancel-order` (NÃO MEXER per spec):
```ts
const userClient = createClient(supabaseUrl, anonKey, {
  global: { headers: { Authorization: `Bearer ${token}` } },
});
const { data: userData, error: authError } = await userClient.auth.getUser();
if (authError || !user) return jsonResponse({ error: 'unauthorized' }, 401);
...
if (order.user_id !== user.id) return jsonResponse({ error: 'not_your_order' }, 403);
```

**Conclusão:** Se `pg_net` chamar com `Authorization: Bearer <service_role_key>`, `auth.getUser()` retorna o principal service_role (não user), e `order.user_id !== user.id` → **403**.

### `admin-cancel-order` via pg_net? **TAMBÉM NÃO**
- Mesma estrutura: `caller.app_metadata.role !== 'admin'` → 403
- service_role principal não tem `role: 'admin'` em metadata

### `admin_cancel_order` SQL function existe ✓
- Signature: `admin_cancel_order(p_order_id uuid, p_reason_code cancellation_reason_code, p_reason text) RETURNS jsonb`
- SECURITY DEFINER ✓
- **MAS:** só faz status update + audit. Stripe refund é feito DENTRO do `admin-cancel-order` Edge Fn (TS), depois de chamar este RPC.
- Chamar este RPC directamente do `admin_approve_action` resulta em: order cancelled + `refund_status='pending'` mas NUNCA é feito refund Stripe → **manual reconciliation eternal**.

### Opções para CANCEL_PRE_PURCHASE

| Opção | Descrição | Custo | Recomendação |
|-------|-----------|-------|--------------|
| **A** | RPC chama `admin_cancel_order` SQL → status cancelled mas refund Stripe nunca acontece | Baixo código mas DÍVIDA financeira | ❌ Inseguro |
| **B** | Flutter `AdminPendingActionsScreen.approve()` faz dispatch: para `CANCEL_PRE_PURCHASE` chama `admin-cancel-order` Edge Fn (com admin JWT do Flutter), não `admin_approve_action` RPC. Marca pending row como executed via RPC à parte. | Médio — Flutter logic | ✅ Funcional |
| **C** | Fechar 5B-β1 sem CANCEL_PRE_PURCHASE; abrir 5B-β1c dedicada | Baixo | ✅ Mais seguro |

**Recomendação:** Opção C (split) — manter 5B-β1 simples.

### Outros riscos
| Risco | Mitigação |
|-------|-----------|
| ACCOUNT_UPDATE escreve campos não autorizados | RPC bloqueia explicitamente: `IF payload ? 'email' OR 'password' OR 'role' OR 'wallet' OR 'tokens' THEN RAISE EXCEPTION` |
| `name` curto/longo | RPC valida 2-100 chars |
| `phone` malformado | RPC valida E.164 regex `^\+?[1-9][0-9]{6,14}$` |
| `pg_net` settings NULL → trigger push falha silently | OK — trigger usa `IS NOT NULL` guard, não bloqueia INSERT |

---

## Recomendação para Danilo

### Cenário recomendado: **Triple split** (mais seguro)

**5B-β1 (esta sessão) — scope reduzido:**
- 1 skill: `ACCOUNT_UPDATE` (com `name`, não `full_name`)
- Trigger push admin (`pg_net` opcional, guard `IS NOT NULL`)
- support-chatbot v4 (1 nova tool `agent_propose_action_account`)

**5B-β1b (próxima):**
- `PASSWORD_RESET` skill + Edge Fn dedicada `support-password-reset` (usa `supabase.auth.resetPasswordForEmail`)

**5B-β1c (depois):**
- `CANCEL_PRE_PURCHASE` skill + Flutter dispatch logic em `AdminPendingActionsScreen` (rota condicional para `admin-cancel-order` Edge Fn quando action_type=CANCEL_PRE_PURCHASE)

### Cenário alternativo: **Single split** (PASSWORD_RESET only)

Se Danilo aceitar Opção B do CANCEL_PRE_PURCHASE (Flutter dispatch logic):
- 5B-β1: `ACCOUNT_UPDATE` + `CANCEL_PRE_PURCHASE` (com Flutter dispatch)
- 5B-β1b: `PASSWORD_RESET`

### Cenário ambicioso: **Tudo em 5B-β1**

Se Danilo aceitar criar Edge Fn nova `support-password-reset` agora:
- 3 skills: ACCOUNT_UPDATE + PASSWORD_RESET + CANCEL_PRE_PURCHASE (com Flutter dispatch)
- 1 Edge Fn nova
- Estimativa real: 6-8h vs 4-6h spec

---

## ⛔ STOP — Aguardar decisões

**Pergunta principal:**

> Qual cenário escolhes para 5B-β1?

1. **Triple split** (ACCOUNT_UPDATE only) — mais seguro
2. **Single split** (ACCOUNT_UPDATE + CANCEL com Flutter dispatch, PASSWORD_RESET split)
3. **Ambicioso** (3 skills + Edge Fn nova) — 6-8h

E se cenário 2 ou 3 — confirma:
- Para CANCEL_PRE_PURCHASE: Flutter dispatch para `admin-cancel-order` ✅?
- Para PASSWORD_RESET: criar Edge Fn `support-password-reset` ✅ ou adiar?

Aguardo: `"ok cenário X com Y/Z"`.
