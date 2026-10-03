# 05b_b2b_audit — Skills info-only mercado + PARTNER_REJECTED (Fase A)

**Sessão:** 5B-β2b/7 (ÚLTIMA de 5B antes de 5D)
**Data:** 2026-05-06
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — STOP após A7
**MCP project_id:** `ojykpzwqrtusfeakzrna`

---

## A0 — Skills count + chatbot version

### Estado actual (16 skills active)

| Mode | Count | Skills |
|---|---|---|
| `escalate` | 1 | HUMAN_REQUEST |
| `read_only` | 8 | APP_TROUBLESHOOTING, GENERAL_FAQ, ORDER_HISTORY, ORDER_STATUS, REFUND_STATUS, TOKENS_INFO, WALLET_BLOCKED_HELP, WALLET_INFO |
| `write_shadow` | 7 | ACCOUNT_UPDATE, CANCEL_DURING_PURCHASE, CANCEL_PRE_PURCHASE, PASSWORD_RESET, RESERVATION_CANCEL, UPDATE_DELIVERY_ADDRESS, UPDATE_DELIVERY_INSTRUCTIONS |

**HUMAN_REQUEST:** `mode='escalate'`, `requires_human_handoff=true`, `allowed_tools=[]`. ✅ Confirma mecanismo escalate via empty array (sem tool dedicada).

### Edge Fns

- `support-chatbot` **v5** ACTIVE (sha256 `dc9a63df…7a5b6d04`)
- `admin-cancel-reservation` v1 ACTIVE (5B-β2a)
- `admin-cancel-order` v2 ACTIVE
- RAG: `rag_enabled=true`, **534 chunks** intactos

---

## A1 — `support_agent_actions` schema

| Coluna | Tipo | Nulo | Default |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `session_id` | uuid | YES | — |
| `user_id` | uuid | NO | — |
| `skill_name` | text | NO | — |
| `action_type` | text | NO | — |
| `action_payload` | jsonb | YES | — |
| `proposed_at` | timestamptz | YES | now() |
| **`shadow_status`** | text | NO | `'pending'` |
| `reviewed_by` | uuid | YES | — |
| `reviewed_at` | timestamptz | YES | — |
| `executed_at` | timestamptz | YES | — |
| `result` | jsonb | YES | — |
| `notes` | text | YES | — |

### CHECK constraint

```
shadow_status ∈ {'pending','approved','rejected','executed','auto_executed','not_applicable'}
```

✅ **`'not_applicable'` é aceite** — perfeito para skills info-only que não geram pending action.

⚠️ NB: tabela é distinta de `support_pending_actions`. As skills info-only escrevem aqui (`support_agent_actions`); as write_shadow escrevem em `support_pending_actions` via RPC `agent_propose_action`.

---

## A2 — Schema StoreShop

### orders (colunas relevantes)

| Coluna | Tipo |
|---|---|
| `order_type` | text |
| `items` | jsonb |
| `items_added` | jsonb |
| `estimated_total` | double precision |
| `final_total` | numeric |

⚠️ **NÃO existe** `items_unavailable` como coluna separada. Estado de unavailable está dentro de `items[].purchase_status` (jsonb interno).

### RPCs StoreShop

- `finalize_storeshopping_purchase` (CRÍTICO — NÃO TOCAR)
- `enforce_storeshopping_finalize_before_pickup`

---

## A3 — business_rules regras REAIS

### Localização das regras

- **§3.x** (linhas 160-170) — Reserva 15% anti-falta, trocas e refund
- **§10.6** — carryGroceries (cliente já fez compras; só transporte)
- **§27** (linha 1036+) — Catálogo produtos (qualidade, fotos, fontes)

### Regras descobertas (vs assunções do prompt)

**Reserva 15% (§3.x linha 163-164):**
> "Reservámos no teu cartão 15% a mais do valor estimado, por segurança.
> Se algum produto estiver em falta, o estafeta pode trocá-lo por outro de
> preço parecido. Pagas apenas o valor real — o extra é libertado do teu
> cartão."

**Trocas em caso de falta (§3.x linhas 166-169):**
- Estafeta pergunta ao cliente pelo chat primeiro
- Se cliente não responder, estafeta pode trocar sozinho por produto de
  preço parecido
- Estafeta usa os 15% de reserva para cobrir diferenças

⚠️ **CORRECÇÃO DO PROMPT** — o prompt B1 ITEM_UNAVAILABLE assume:

> "Bora NÃO faz substituições (regra Bora)"

Mas BR §3.x diz o **OPOSTO**: estafeta TROCA por produto de preço parecido.
Playbook ITEM_UNAVAILABLE precisa de adaptar:
- Item totalmente indisponível e estafeta NÃO trocou → não cobrado
  (refund automático via 15% reserva)
- Item indisponível + estafeta trocou → o item de substituição foi
  cobrado, NÃO o original
- Cliente paga apenas valor real comprado

**ITEM_ADDED — fórmula confirmada:**
- Cliente pede item extra via ➕ no app
- Preço calculado pelo Flutter (extracto BUG38):
  ```dart
  i.price * (1 + 0.15) * i.quantity
  ```
- 15% = `_nonPartnerMarkupRate` (`pricing_service.dart`)
- Server faz mesmo cálculo autoritativo em `finalize_storeshopping_purchase`

**PRICE_DIFFERENCE:**
- Estimativa = sum(items × preço scraper actual)
- Cobrança Stripe inicial = `estimated_total × 1.15` (reserva 15%)
- Final = `bought_total + bag_fee + items_added × 1.15`
- Diferença → `extra_to_charge` (se diff > 0) OU `refund_due` (se diff < 0)
- Cliente paga **apenas valor real**; reserva 15% existe só para absorver
  variações
- Se diff > 15% reserva → admin é envolvido (impossible to charge more
  than reserved)

### Numeração §36 disponível

- §36.10 = Limitações conhecidas
- §36.11 = Skills Grupo 3a (5B-β2a)
- §36.12 = Pattern EXTERNAL_DISPATCH_REQUIRED (5B-β2a)
- **§36.13 = PRÓXIMO disponível** ← Skills Grupo 3b
- **§36.14 = 5B COMPLETO** (resumo total)
- **§36.15 = Tool agent_explain_event**

---

## A4 — Mecanismo escalate confirmado

`HUMAN_REQUEST` (5A-1):
- `mode='escalate'`
- `requires_human_handoff=true`
- `allowed_tools=[]` (array vazio)

**Mecanismo de execução em `support-chatbot` v5** (confirmado no audit
5B-β2a):

1. Marker `[HANDOFF_HUMAN]` colocado pelo agente no fim da resposta:
   ```typescript
   if (finalText.includes('[HANDOFF_HUMAN]')) {
     escalated = true;
     finalText = finalText.replace('[HANDOFF_HUMAN]', '').trim();
   }
   ```
2. Quando `escalated=true`, código cria automaticamente
   `support_tickets` row + actualiza session com `escalated=true,
   escalation_reason, ticket_id`.

✅ **Mecanismo a usar para PARTNER_REJECTED_ORDER:**
- `allowed_tools=[]` (igual ao HUMAN_REQUEST — consistência)
- Playbook instrui agente a terminar com `[HANDOFF_HUMAN]`
- **NÃO** criar tool `agent_create_ticket` (não existe; ticket é
  automático no finalText handling)

---

## A5 — `support-chatbot` v5 — pontos de edição

| Item | Localização | Acção |
|---|---|---|
| Variável service_role | `adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)` | Reusar (existe no scope handler) |
| Variável user JWT | `userClient` | Não tocada |
| `TOOL_WHITELIST` | linha ~28-36 (Set) | += `'agent_explain_event'` |
| `buildFunctionDeclarations()` | linha ~117+ (returns array) | += novo tool def |
| Tool dispatch | `if (PROPOSE_ACTION_TOOL_NAMES.has(fnName)) { ... } else { callRpc(...) }` | Adicionar branch `else if (fnName === 'agent_explain_event') { ... insert via adminClient ... }` antes do else genérico |
| `PROPOSE_ACTION_TOOL_NAMES` | linha ~38-43 | NÃO tocar (skill é read_only, não propose) |
| `WRITE_SHADOW_ACTION_TYPES` | linha ~46-54 | NÃO tocar (skills info-only não usam) |

### Comportamento `agent_explain_event` proposto

```typescript
else if (fnName === 'agent_explain_event') {
  const skillName = (fnArgs.skill_name as string) ?? '';
  const orderId   = (fnArgs.order_id as string | undefined) ?? null;
  const ctx       = (fnArgs.context as Record<string, unknown>) ?? {};
  const allowed = new Set([
    'ITEM_UNAVAILABLE','ITEM_ADDED','PRICE_DIFFERENCE',
  ]);
  if (!allowed.has(skillName)) {
    rpcRes = { ok: false, error: `skill_name not allowed: ${skillName}` };
  } else {
    const { error: insErr } = await adminClient
      .from('support_agent_actions')
      .insert({
        session_id:     sessionId,
        user_id:        userId,
        skill_name:     skillName,
        action_type:    skillName,
        action_payload: { order_id: orderId, ...ctx },
        shadow_status:  'not_applicable', // confirmado A1
      });
    if (insErr) {
      rpcRes = { ok: false, error: insErr.message };
    } else {
      rpcRes = { ok: true, data: { logged: true, skill_name: skillName } };
    }
  }
}
```

---

## A6 — Análise transversal: impacto + riscos

### Riscos

**🟢 BAIXO 1 — Aditivo:** seed 4 skills + 1 tool no chatbot. Sem refactor
de fluxos existentes. Não toca `WRITE_SHADOW_ACTION_TYPES`,
`PROPOSE_ACTION_TOOL_NAMES`, RAG, kill switch.

**🟡 MÉDIO 2 — Playbook ITEM_UNAVAILABLE inicial do prompt está incorrecto.**
Regra real BR §3.x: estafeta TROCA por produto similar se cliente não
responder. Playbook adaptado conforme A3 acima (não "Bora não substitui").

**🟢 BAIXO 3 — `'not_applicable'` é valor válido em CHECK constraint
shadow_status.** Sem migração necessária.

**🟢 BAIXO 4 — `agent_explain_event` falha silenciosamente** (try/catch +
console.warn) — não bloqueia o fluxo conversacional.

**🟢 BAIXO 5 — Numeração §36.13/14/15 disponível** (não há colisão).

### Impacto

- **Migrations:** 1 seed (4 skills, sem DDL).
- **Edge Fn:** 1 edit `support-chatbot` v6.
- **Flutter:** ZERO. AdminPendingActionsScreen não tocada (skills não geram pending rows).
- **Documentação:** §36.13 + §36.14 + §36.15 + sync Obsidian.

---

## A7 — Skill identification + plano Fase B

### Skills identificadas

Nenhum skill helper novo necessário. Apenas:
- 4 skills seed (SQL)
- 1 tool nova `agent_explain_event` no chatbot v6

### Plano Fase B (após luz verde)

| Bloco | Acção |
|---|---|
| **B1** | Migration `20260506_5b_b2b_b1_seed_grupo3b_skills` — INSERT 4 skills (3 read_only + 1 escalate) com playbooks adaptados conforme A3/A4 |
| **B2** | Deploy `support-chatbot` v6 — TOOL_WHITELIST += `agent_explain_event`; tool def; handler insert directo em `support_agent_actions` com `shadow_status='not_applicable'` |
| Smokes | S1–S6 SQL + S5/S6 chatbot ACTIVE; S10 flutter analyze (baseline 55); S11–S18 regressão |
| Docs | business_rules §36.13/14/15 |

### Decisões pendentes (luz verde Danilo)

| # | Item | Proposta |
|---|---|---|
| D1 | Playbook ITEM_UNAVAILABLE | Adaptar para regras BR §3.x reais (estafeta substitui se cliente não responder; Bora NÃO recusa substituição como prompt assumia) |
| D2 | Mecanismo escalate PARTNER_REJECTED_ORDER | `[HANDOFF_HUMAN]` marker (consistência com HUMAN_REQUEST), sem tool nova |
| D3 | shadow_status para info-only logs | `'not_applicable'` (confirmado válido em CHECK) |
| D4 | Numeração BR | §36.13 (Grupo 3b), §36.14 (5B COMPLETO), §36.15 (tool agent_explain_event) |
| D5 | tool agent_explain_event scope | Apenas 3 skills info-only (ITEM_UNAVAILABLE/ITEM_ADDED/PRICE_DIFFERENCE); NÃO usada por PARTNER_REJECTED |

---

## ⛔ STOP — aguardar luz verde Danilo

Decisões pendentes: **D1–D5**.

Risco principal: **D1** (playbook ITEM_UNAVAILABLE diverge do prompt).
Sem confirmação não prossigo com Fase B.
