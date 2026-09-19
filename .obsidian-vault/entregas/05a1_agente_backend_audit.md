# Sessão 5A-1/7 — Agente IA Suporte: Backend Foundation

## Fase A — AUDIT (read-only)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m] (Opus 4.7)
**Modo:** PROTECÇÃO TOTAL — aprovação por fase
**Pré-condição:** GEMINI_API_KEY confirmada por Danilo ✅

---

## A0 — Regressão Sessões 1-4

| # | Check | Resultado | Estado |
|---|-------|-----------|--------|
| A0.1 | coords NULL pós 2026-05-03 | 0 rows | ✅ |
| A0.2 | `finalize_storeshopping_purchase` cap 5 sacos | source contém check (16293 chars) | ✅ |
| A0.3 | `client_wallets` CHECK | `CHECK (free_balance_cents >= -2000)` | ✅ |
| A0.4 | trigger `trg_zz_final_total_dual_write` | enabled (`O`) | ✅ |
| A0.5 | `orders.extra_charge_settled_at/_via` cols | 2 rows | ✅ |

**Sessões 1-4 íntegras.** Zero regressão detectada.

---

## A1 — `support_tickets` schema legacy

**10 colunas confirmadas, exact match com pré-validação Claude.ai 2026-05-04:**

| col | type | NOT NULL | default |
|-----|------|----------|---------|
| id | uuid | YES | gen_random_uuid() |
| user_id | uuid | NO | — |
| user_role | text | YES | — |
| question | text | YES (NOT NULL) | — |
| bot_answer | text | NO | — |
| human_answer | text | NO | — |
| satisfaction | int | NO | — |
| status | text | YES | `'open'` |
| created_at | timestamptz | YES | now() |
| answered_at | timestamptz | NO | — |

**Decisão B7:** ALTER aditivo. Mapear `question ↔ body` no `support-submit-ticket` Edge Fn.

---

## A2 — Análise rows backfill

```
total=0  bot_rows=0  human_rows=0  earliest=NULL  latest=NULL
```

**Tabela vazia → backfill `channel='chatbot'` é no-op real.** Mantemos UPDATE por idempotência.

---

## A3 — ChatStore namespace

**Tabelas DB com 'chat' no nome:** `0` (zero).
**Tabela operacional cliente↔estafeta:** `messages` (id uuid, order_id uuid, sender_type, message, read).

**Conclusão:**
- `messages` (operacional) ≠ `support_chatbot_messages` (suporte) → **isolamento total**.
- Não há colisão de nomes nem de RLS.

🐛 **BUG colateral 39 (reportar, não fixar):** `messages.order_id` é UUID
mas `orders.id` é TEXT — joins exigem cast (igual a `bora_tokens.source_order_id`).
Sessão 7 dedicada a `orders.id` UUID refactor (`decisions/2026-04-29-...md`).

---

## A4 — `bora_tokens` detail

| col | type | NOT NULL | nota |
|-----|------|----------|------|
| id | uuid | YES | PK |
| user_id | uuid | YES | — |
| role | text | YES | CHECK IN ('client','driver') |
| amount | int | YES | CHECK > 0 (unidades, não cents) |
| created_at | timestamptz | NO | now() |
| **expires_at** | timestamptz | **YES (NOT NULL)** | ⚠️ corrige B8.4 |
| source_order_id | uuid | NO | UUID vs orders.id TEXT (BUG 39) |
| is_used | bool | NO | false |
| used_at | timestamptz | NO | — |

**RLS policies (1):** `tokens_select_own` (cmd=`r`, qual `user_id = auth.uid()`).
Sem policies INSERT/UPDATE/DELETE → escritas só via SECURITY DEFINER (consistente).

**⚠️ Ajuste obrigatório B8.4:** simplificar predicado de `(expires_at IS NULL OR expires_at > now())` para `expires_at > now()` (NOT NULL).

**Skill TOKENS_INFO active=true em B17 (5A-2):** confirmado.

---

## A5 — pgvector

```
SELECT extname FROM pg_extension WHERE extname='vector' → 0 rows
```

**Ausente.** RAG diferido para 5C conforme planeado.

---

## A6 — `is_admin()` signature

```
proname=is_admin  args=""  returns=boolean  security_definer=true
```

**⚠️ Diferença vs prompt:** prompt assumia `is_admin(uuid)`. Real é **`is_admin()`** sem args (usa `auth.uid()` internamente). Único overload.

**Impacto:** B16 `admin_resolve_ticket` (5A-2) e RLS escrita em `support_settings`/`support_skills` usam `is_admin()` directo.

---

## A7 — GEMINI_API_KEY

**Confirmado por Danilo:** "chave OK" (mensagem 2026-05-04).
→ B9 deploy `support-chatbot` Edge Fn pode prosseguir em Fase B.

---

## A8 — Análise impacto + rollback

### Ficheiros novos (Fase B)
- 7 migrations em `supabase/migrations/`:
  - `20260504_5a1_support_settings.sql`
  - `20260504_5a1_support_skills.sql`
  - `20260504_5a1_support_chatbot_sessions.sql`
  - `20260504_5a1_support_chatbot_messages.sql`
  - `20260504_5a1_support_chatbot_quota.sql`
  - `20260504_5a1_support_agent_actions.sql`
  - `20260504_5a1_alter_support_tickets.sql`
- 5 RPCs (uma migration adicional ou inline na migration agent_rpcs):
  - `20260504_5a1_agent_rpcs.sql` (5 fns whitelisted)
- 2 Edge Functions:
  - `supabase/functions/support-chatbot/index.ts`
  - `supabase/functions/support-submit-ticket/index.ts`

### Análise transversal (cliente/estafeta/parceiro/admin/DB)
- **Cliente:** ainda sem UI (5A-2). Backend recebe/responde mas nada visível.
- **Estafeta:** mesmo. Backend agnóstico de role.
- **Parceiro:** mesmo.
- **Admin:** sem UI 5A-1. RPC `admin_resolve_ticket` chega em 5A-2.
- **DB:** zero conflito com tabelas existentes (`messages`, `bora_tokens`, `orders`, `client_wallets`).

### Riscos críticos: **zero**
- Tabelas novas isoladas
- ALTER aditivo idempotente (`ADD COLUMN IF NOT EXISTS`)
- RPCs whitelisted sem `p_user_id` (defesa impersonation)
- Edge Fns autónomas; sem tocar dispatch/pricing/Stripe/wallet/reservas

### Plano rollback
1. **Switch off rápido:** `UPDATE support_settings SET support_agent_enabled=false;`
   → app cliente (5A-2) detecta e esconde FAB.
2. **Edge Fns retornam 503/handoff** se KEY ausente ou config off.
3. **Migrations reversíveis** (DROP TABLE ... CASCADE) sem afetar dados pré-existentes (apenas `support_tickets` ALTER aditivo permanece, sem perda).

---

## A9 — Skills identificadas

**Nenhuma skill nova além das 9 aprovadas.** Registo em
`.claude/skills/identified_during_5a1_NONE.md`.

---

## A10 — Status final Fase A

✅ **Todos os 10 checks (A0-A9) passaram. Sem bloqueios.**
✅ GEMINI_API_KEY confirmada → B9 verde.
⚠️ Ajustes obrigatórios na Fase B antes de aplicar:
   - B8.3: usar `free_balance_cents` (não `balance_cents`).
   - B8.4: predicado `expires_at > now()` (NOT NULL).
   - RLS migrations: `is_admin()` sem args (não `is_admin(auth.uid())`).

🐛 **Colateral BUG 39:** mismatch UUID/TEXT entre `messages.order_id`,
`bora_tokens.source_order_id` e `orders.id`. **Reportar, não fixar** (Sessão 7 dedicada).

📦 **Sync Obsidian:** copiar este audit para `C:\Users\danil\Desktop\Bora\entregas\05a1_agente_backend_audit.md`.

⛔ **STOP — Aguardar luz verde Danilo para Fase B (B1–B10 + 24 smokes + relatório + sync final).**
