# B2 commit 2 — Audit Fase A (final_total DROP+RENAME)

**Data:** 2026-05-05
**Branch:** autonomous-night-2026-04-29
**Modelo:** Opus 4.7
**Modo:** PROTECÇÃO TOTAL (aprovação por tarefa)
**Pré-validação MCP:** Claude.ai 2026-05-05 (refresh)

---

## 📊 A0 — Regressão Check (estado actual)

| Validação | Esperado | Actual | Status |
|---|---|---|---|
| `trg_zz_final_total_dual_write` | 1 | 1 | ✅ |
| `fn_sync_final_total_numeric` | 1 | 1 | ✅ |
| `orders.final_total` (double precision) | exists | exists | ✅ |
| `orders.final_total_numeric` (numeric) | exists | exists | ✅ |
| Drift entre colunas | 0 | 0 | ✅ |
| `is_test_order` col | 1 | 1 | ✅ Sessão 6 intacta |
| `is_test_order=true` rows | 4 | 4 | ✅ Sessão 6 intacta |
| `support_*` tables | ≥7 | 7 | ✅ Sessão 5A intacta |
| `admin_get_support_stats` RPC | 1 | 1 | ✅ Sessão 6-B3 intacta |
| `orders` total rows | >0 | 94 | ✅ |

**Conclusão A0:** Sessões 1-6 intactas. Estado pronto para migração.

---

## 📋 A1 — RPCs com referências `final_total`

13 RPCs encontradas — **idêntico à baseline Claude.ai 2026-05-05** ✅

| # | RPC | Cast `final_total::tipo`? | Ref `final_total_numeric`? |
|---|---|---|---|
| 1 | `agent_get_user_orders_summary` | ⚠️ **HAS_CAST** | ⚠️ **REFS_NUMERIC** |
| 2 | `apply_driver_cash_settlement` | no_cast | no |
| 3 | `apply_order_financial_split` | no_cast | no |
| 4 | `compute_driver_settlement` | no_cast | no |
| 5 | `create_order` | no_cast | no |
| 6 | `enforce_cash_payment_limit` | no_cast | no |
| 7 | `enforce_financial_immutability` | no_cast | no |
| 8 | `finalize_storeshopping_purchase` | no_cast | no |
| 9 | `fn_award_cashback_on_delivery` | no_cast | no |
| 10 | `fn_referral_reward_on_first_delivery` | no_cast | no |
| 11 | `fn_sync_final_total_numeric` (será dropada) | HAS_CAST (esperado) | REFS_NUMERIC (esperado) |
| 12 | `list_driver_orders_in_week` | no_cast | no |
| 13 | `post_order_to_ledger` | no_cast | no |

### 🐛 DIVERGÊNCIA BASELINE (CRÍTICA)

A pré-validação Claude.ai 2026-05-05 dizia:
> "ZERO casts explícitos final_total::tipo em qualquer RPC"

**Realidade:** `agent_get_user_orders_summary` contém:
```sql
ROUND((COALESCE(o.final_total_numeric, o.final_total::numeric, 0))*100)::int
```

**Impacto:** após DROP `final_total` (double) + RENAME `final_total_numeric → final_total`:
- `o.final_total_numeric` deixa de existir → erro `column does not exist`
- A RPC quebra para todas as queries do agente IA (chat IA)

**Decisão:** B2 PARTE 1 e PARTE 2 incluirão **CREATE OR REPLACE** desta RPC para usar a coluna renomeada (numeric).

### Auditoria objectos não-RPC

| Tipo | Refs `final_total` | Resultado |
|---|---|---|
| Views | 0 | ✅ |
| Materialized views | 0 | ✅ |
| Indexes | 0 | ✅ |
| Triggers (não-internos) | 2 (`orders_enforce_cash_limit`, `trg_zz_final_total_dual_write`) | ✅ ambos OK |

`orders_enforce_cash_limit` chama `enforce_cash_payment_limit` (no_cast) — funciona após RENAME automaticamente.

---

## 🔍 A2 — Flutter Analysis (read-only)

**28 hits** `final_total`/`finalTotal` em **9 ficheiros**:

- `lib/models/order_model.dart` (3 hits — fromSupabase, toSupabase, declaração `double? finalTotal`)
- `lib/stores/order_store.dart` (4 hits — write/update operations)
- `lib/widgets/weekly_settlement_card.dart` (3 hits)
- `lib/screens/admin/admin_order_detail_screen.dart` (4 hits)
- `lib/screens/admin/admin_driver_detail_screen.dart` (2 hits — SELECT explícito)
- `lib/screens/admin/_admin_cancel_order_dialog.dart` (1 hit)
- `lib/screens/orders_screen.dart` (2 hits)
- `lib/screens/driver_map_screen.dart` (8 hits)
- `lib/screens/driver_home_screen.dart` (1 hit)

### Padrão único usado para deserialização

```dart
(data['final_total'] as num?)?.toDouble()
```

✅ **Safe para numeric:** SDK Supabase Flutter converte `numeric` PostgreSQL → `num` Dart automaticamente. `as num?` aceita ambos `int` e `double`.

### Auditoria casts/refs `final_total_numeric`

| Pattern | Hits |
|---|---|
| `final_total_numeric` ou `finalTotalNumeric` | **0** ✅ |
| Casts explícitos `final_total::tipo` | **0** ✅ |
| `(num?)?.toDouble()` deserialization | universal ✅ |

**Conclusão A2:** Flutter NÃO precisa de mudanças. Todas as operações são name-based via column `final_total` (que continua a existir após RENAME, agora numeric).

⚠️ **CAVEAT:** `flutter analyze` valida sintaxe, não runtime SDK. Validação real do round-trip numeric→num só em device (5A-2-γ).

---

## 🛠 A3 — Plano Dry-Run (ajustado para incluir FIX RPC)

### Ordem das operações (atómica)

```sql
BEGIN;
  -- 1. Drop trigger dual-write
  DROP TRIGGER IF EXISTS trg_zz_final_total_dual_write
    ON public.orders;

  -- 2. Drop função sync
  DROP FUNCTION IF EXISTS public.fn_sync_final_total_numeric();

  -- 3. Drop coluna double
  ALTER TABLE public.orders DROP COLUMN IF EXISTS final_total;

  -- 4. Rename coluna numeric → final_total
  ALTER TABLE public.orders
    RENAME COLUMN final_total_numeric TO final_total;

  -- 5. FIX agent_get_user_orders_summary (DIVERGÊNCIA A1)
  CREATE OR REPLACE FUNCTION public.agent_get_user_orders_summary(p_limit integer DEFAULT 5)
   RETURNS TABLE(order_id text, status text, created_at timestamp with time zone, partner_name text, total_cents integer, can_be_cancelled boolean)
   LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path TO 'public'
  AS $function$
  BEGIN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'NOT_AUTHENTICATED';
    END IF;
    RETURN QUERY
    SELECT
      o.id, o.status, o.created_at,
      COALESCE(r.name, 'N/D'),
      ROUND(COALESCE(o.final_total, 0) * 100)::int,
      o.status IN ('pending','accepted')
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.user_id = auth.uid()
    ORDER BY o.created_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 20);
  END$function$;

  -- Smokes 1-4 (validação dentro da transação)
  -- ...

ROLLBACK;  -- PARTE 1
-- ou COMMIT em PARTE 2 (substituído por verificação inline DO $$ ... $$)
```

### Smokes intra-transacção

1. `data_type` de `final_total` = `numeric`
2. `final_total_numeric` count = 0 (coluna sumiu)
3. `COUNT(*)` orders preservado (94)
4. `pg_typeof(final_total)` runtime = `numeric`
5. `pg_get_functiondef(agent_get_user_orders_summary)` não contém `final_total_numeric`

**Janela crítica:** ≤60s entre PARTE 1 ROLLBACK e PARTE 2 COMMIT (concorrência writes).

---

## 💾 A4 — Backup Pre-Migration

**Ficheiro:** `.claude/.ai/backups/b2c2_pre_migration_20260505.sql`

Contém:
- ✅ `pg_get_triggerdef` de `trg_zz_final_total_dual_write`
- ✅ `pg_get_functiondef` de `fn_sync_final_total_numeric`
- ✅ `pg_get_functiondef` de `agent_get_user_orders_summary` (versão original com `final_total_numeric`)
- ✅ Comentário com restore manual da coluna double

---

## 🧠 A5 — Análise Impacto + Rollback Plan

### Impacto esperado

| Componente | Impacto | Mitigação |
|---|---|---|
| 11 RPCs sem refs a `final_total_numeric` | RENAME → continuam OK por nome | Nenhuma |
| 1 RPC `agent_get_user_orders_summary` | Quebraria sem fix | **CREATE OR REPLACE em PARTE 1+2** |
| 1 RPC `fn_sync_final_total_numeric` | DROP intencional | Esperado |
| Trigger `trg_zz_final_total_dual_write` | DROP intencional | Esperado |
| Trigger `orders_enforce_cash_limit` | Continua a funcionar | Cast implícito numeric→numeric |
| Flutter (28 hits, 9 ficheiros) | Continua a funcionar | SDK converte numeric→num |
| Painel admin (SELECT final_total) | Continua a funcionar | Nome igual |
| Realtime channel `orders` | Continua a funcionar | Coluna mesmo nome, payload JSON same |
| Drift entre colunas | Impossível (single column) | Estrutural |
| Downtime | Zero esperado | DDL rápida (DROP+RENAME ms) |

### Plano Rollback

**Se PARTE 1 dry-run falha:**
- ROLLBACK automático da transacção
- Estado original preservado (zero impacto)
- Reportar smoke que falhou
- Não prosseguir para PARTE 2

**Se PARTE 2 falha após apply_migration:**
1. `ALTER TABLE orders RENAME COLUMN final_total TO final_total_numeric;`
2. `ALTER TABLE orders ADD COLUMN final_total double precision;`
3. `UPDATE orders SET final_total = final_total_numeric::double precision;`
4. Reaplicar trigger + função do A4 backup
5. Reaplicar versão original de `agent_get_user_orders_summary` do A4 backup

**Risco residual:** baixo. DDL é atómica em PostgreSQL; falha-tudo-ou-nada.

---

## 📦 A6 — Skill Identification + Sync

**Skills identificadas durante audit:** nenhuma nova. Tooling existente suficiente:
- MCP Supabase (`execute_sql`, `apply_migration`)
- Grep nativo Flutter
- Write/Edit nativos para artefactos

**Sync Obsidian:** programado para após Fase B (relatório b2c2_final_total_report.md + cópia do prompt + backup).

---

## ⛔ STOP — Aguardar Luz Verde Danilo

**Resumo executivo:**
- ✅ A0: estado actual confirmado (trigger+função+2 colunas+drift=0+sessões intactas)
- ⚠️ A1: **1 divergência crítica** baseline — `agent_get_user_orders_summary` referencia `final_total_numeric` directamente
- ✅ A2: Flutter safe (zero refs `final_total_numeric`, padrão `as num?` universal)
- ✅ A3: plano dry-run **ajustado** para incluir CREATE OR REPLACE da RPC quebrada
- ✅ A4: backup capturado em `.claude/.ai/backups/b2c2_pre_migration_20260505.sql`
- ✅ A5: análise impacto + rollback documentados

**Pergunta para Danilo:**

> A baseline Claude.ai 2026-05-05 estava errada — `agent_get_user_orders_summary` referencia `final_total_numeric` na expressão `COALESCE(o.final_total_numeric, o.final_total::numeric, 0)`. **Aprovas o plano ajustado** que adiciona `CREATE OR REPLACE` desta RPC dentro da mesma transacção (PARTE 1 + PARTE 2)?

Sem aprovação: STOP (não prossegue Fase B).
Com aprovação: Fase B executa B1 (dry-run) → B2 (migration) → smokes → commit atómico.
