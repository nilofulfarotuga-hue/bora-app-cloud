# B2 commit 2 — Relatório Fase B (final_total DROP+RENAME — CONCLUÍDO)

**Data:** 2026-05-05
**Branch:** autonomous-night-2026-04-29
**Modelo:** Opus 4.7
**Modo:** PROTECÇÃO TOTAL
**Migration aplicada:** `b2c2_drop_rename_final_total`

---

## ✅ Resumo executivo

Sessão 4 C3 **FECHADA**. Migração final_total `double precision → numeric` concluída em prod (Supabase EU-West-1).

| Antes (2026-05-04) | Depois (2026-05-05) |
|---|---|
| `orders.final_total` double precision | `orders.final_total` **numeric** |
| `orders.final_total_numeric` numeric | (removida) |
| Trigger `trg_zz_final_total_dual_write` | (removido) |
| Função `fn_sync_final_total_numeric` | (removida) |
| RPC agent referencia `final_total_numeric` | RPC agent usa `final_total` (numeric) |
| 13 RPCs referenciam `final_total` (LIKE) | 12 RPCs referenciam `final_total` (real) |

---

## 📋 B1 — Dry-run (BEGIN/ROLLBACK)

### Tentativa 1: ❌ Falhou
```
ERROR: 2BP01: cannot drop column final_total of table orders 
because other objects depend on it
DETAIL: trigger orders_enforce_cash_limit on table orders depends on column final_total
```

**Achado adicional (não previsto na baseline Claude.ai):** trigger `orders_enforce_cash_limit` é `BEFORE INSERT OR UPDATE OF payment_method, price, final_total ON public.orders` — depende explicitamente da coluna.

### Tentativa 2: ✅ PASS

Plano ajustado para 7 passos (em vez de 4):
1. DROP `trg_zz_final_total_dual_write`
2. DROP `fn_sync_final_total_numeric`
3. **DROP `orders_enforce_cash_limit`** (novo)
4. DROP COLUMN `final_total` (double)
5. RENAME `final_total_numeric → final_total`
6. **RECREATE `orders_enforce_cash_limit`** (mesma definição, agora com final_total numeric)
7. CREATE OR REPLACE `agent_get_user_orders_summary` (versão fix sem `final_total_numeric`)

**Smokes intra-transacção:**

| Smoke | Resultado | Esperado | Status |
|---|---|---|---|
| 1 — type | numeric | numeric | ✅ |
| 2 — old col count | 0 | 0 | ✅ |
| 3a — total rows | 94 | 94 | ✅ |
| 3b — non-null rows | 50 | >0 | ✅ |
| 4 — runtime type | numeric | numeric | ✅ |
| 5 — agent RPC refs `_numeric` | no_good | no_good | ✅ |
| 6 — dual_write trigger | 0 | 0 | ✅ |
| 7 — fn_sync dropped | 0 | 0 | ✅ |
| 8 — cash_limit trigger | 1 | 1 | ✅ |

ROLLBACK aplicado. Estado restaurado.

---

## 🚀 B2 — Migration definitiva

**Aplicada via Supabase MCP `apply_migration`** (nome: `b2c2_drop_rename_final_total`).

Conteúdo: idêntico ao B1 (7 passos), com bloco `DO $$ ... $$` de verificação atómica em vez de smokes UNION.

`{"success": true}` retornado pelo MCP. Verificação inline `DO $$` passou sem `RAISE EXCEPTION`.

---

## 🔬 Smokes pós-migration (S1-S12)

| ID | Smoke | Resultado | Esperado | Status |
|---|---|---|---|---|
| S1a | `final_total` data_type | numeric | numeric | ✅ |
| S1b | `final_total` non-null rows | 50 | >0 | ✅ |
| S1c | `trg_zz_final_total_dual_write` count | 0 | 0 | ✅ |
| S1d | `fn_sync_final_total_numeric` count | 0 | 0 | ✅ |
| S1e | `final_total_numeric` col count | 0 | 0 | ✅ |
| S2 | RPCs com `final_total` (LIKE) | 12 | 12 | ✅ |
| S2 | RPCs com refs reais (`\m\M`) | 12 | 12 | ✅ |
| S3a | `create_order` definition | OK | OK | ✅ |
| S3b | `finalize_storeshopping_purchase` def | OK | OK | ✅ |
| S3c | `apply_order_financial_split` def | OK | OK | ✅ |
| S4 | `pg_typeof(final_total)` runtime | numeric | numeric | ✅ |
| S5 | agent RPC refs `final_total_numeric` | OK (zero) | OK | ✅ |
| S6 | `support_*` tables | 7 | ≥7 | ✅ Sessão 5A intacta |
| S7 | sample value | 170.24 | precisão preservada | ✅ |
| S8 | `enforce_cash_payment_limit` fn | 1 | 1 | ✅ |
| S8b | `is_test_order` col | 1 | 1 | ✅ Sessão 6 intacta |
| S9 | test orders | 4 | 4 | ✅ Sessão 6 intacta |
| S10 | `admin_get_support_stats` | 1 | 1 | ✅ Sessão 6-B3 intacta |
| S11 | (skipped — coluna `delivery_lat` não existe no schema; usado proxy via S6/S8/S10) | n/a | n/a | ⏭ |
| S12 | wallet CHECK -2000 | (validado em sessão anterior) | preservado | ✅ |

### Esclarecimento S2 (12 vs 11 esperado)

Danilo previu 11 RPCs com `list_driver_orders_in_week` como falso positivo. **Realidade:** essa RPC tem 3 referências reais a `o.final_total` na lógica (`COALESCE(o.final_total, o.price, 0)::numeric`). Não é falso positivo — funciona após RENAME porque:
- Coluna `final_total` mantém o nome
- Era cast `::numeric` antes (redundante mas inofensivo); agora também é numeric
- Casts redundantes `::numeric` continuam válidos

12 RPCs reais = lista correcta após DROP de `fn_sync_final_total_numeric`.

---

## 🔍 flutter analyze

```
55 issues found. (ran in 57.3s)
```

Todos pré-existentes (`info`/`warning` deprecated_member_use, unused vars). **Zero erros novos** relacionados com a migração.

⚠️ Validação runtime SDK Supabase só em device (5A-2-γ). Padrão `(data['final_total'] as num?)?.toDouble()` é safe contractualmente.

---

## 🐛 Bugs colaterais

**1 bug encontrado e corrigido na mesma transacção:**

- **agent_get_user_orders_summary** referenciava `o.final_total_numeric` na expressão `COALESCE(o.final_total_numeric, o.final_total::numeric, 0)`. Sem fix, RPC quebraria após RENAME.
- **Resolução:** `CREATE OR REPLACE` dentro da mesma transacção, simplificando para `COALESCE(o.final_total, 0)`.

**1 dependência não prevista pela baseline Claude.ai:**

- **orders_enforce_cash_limit** trigger depende explicitamente de `final_total` na cláusula `BEFORE INSERT OR UPDATE OF`. Forçou DROP+RECREATE.
- **Resolução:** ambos passos incluídos na mesma migration.

**Zero bugs novos em produção.** Todos os achados eram pré-existentes mas não documentados na baseline.

---

## 📝 Update business_rules.md §29.1

Adicionado bloco "**§29.1 actualização (B2 commit 2, 2026-05-05)**":
- Migração concluída.
- Trigger + função removidos.
- Achados laterais documentados.
- Próximo passo: `extra_charge_amount` → numeric (futuro).

---

## 📦 Artefactos criados/modificados

| Ficheiro | Tipo |
|---|---|
| `.claude/.ai/reports/20260502_megafinal/b2c2_final_total_audit.md` | Fase A |
| `.claude/.ai/reports/20260502_megafinal/b2c2_final_total_report.md` | Fase B (este) |
| `.claude/.ai/backups/b2c2_pre_migration_20260505.sql` | Backup pré-migration |
| `.claude/.ai/business_rules.md` | §29.1 actualização |
| `.obsidian-vault/entregas/b2c2_final_total_audit.md` | Sync Obsidian |
| `.obsidian-vault/backups/b2c2_pre_migration.sql` | Sync Obsidian |
| Supabase migration `b2c2_drop_rename_final_total` | Aplicada em prod |

---

## ⏭ Próximos passos

1. ⛔ **NÃO push automático** — Danilo aprova via Claude.ai validação
2. Validação runtime device (criar order, ler `final_total`, confirmar precisão)
3. Future housekeeping: `extra_charge_amount` → numeric (mesmo padrão)
4. Sync Obsidian Fase B

---

## 📊 Análise sessões intactas

| Sessão | Item | Status |
|---|---|---|
| 5A-1 | 7 tabelas suporte | ✅ |
| 5A-2 | 22 screens FAB suporte | n/a (não tocado) |
| 5A-2-β | UX suporte chat IA | n/a |
| 4C | productId integrity 5 camadas | n/a |
| 6-B1 | `is_test_order` col | ✅ |
| 6-B1 | 4 pedidos teste | ✅ |
| 6-B2 | UX suporte chat IA | n/a |
| 6-B3 | `admin_get_support_stats` | ✅ |

Todas as sessões anteriores **intactas**. Zero regressões detectadas.
