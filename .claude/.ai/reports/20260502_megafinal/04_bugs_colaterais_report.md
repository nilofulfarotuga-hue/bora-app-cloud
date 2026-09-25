# Sessão 4/7 — Bugs Colaterais / Housekeeping — Relatório Fase B

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Estado:** Fase B concluída. Aguarda luz verde Danilo para commit + push.
**Pré-requisito:** Fase A em `04_bugs_colaterais_analise.md` (corrigido `'settlement'`)

---

## Sumário executivo

| Bug | Estado | Migration / Commit | Notas |
|---|---|---|---|
| C1 — `confirm-mbway-payment` obsoleta | ✅ feito | CLI delete | Edge Fn apagada + 2 comentários `order_store.dart` actualizados |
| C2 — `create-mbway-payment-intent-debug` | ✅ feito | CLI delete | Edge Fn apagada |
| C3 — `final_total` dual-write commit 1 | ✅ feito | `b2_final_total_dual_write_commit1` | Trigger `trg_zz_final_total_dual_write` ENABLED; 94 orders OK; commit 2 sessão futura |
| C4 — `extra_charge` settlement marker | ✅ feito | `b3_extra_charge_settlement_marker` + `b3_finalize_storeshopping_extra_charge_settled` | 2 colunas + CHECK + finalize estendida wallet path |
| C5 — `quote_order_pricing` Caso A | ✅ feito | docs only | `business_rules.md` §29.5 |
| C6 — Flutter productId mitigação | ✅ feito (parcial) | code-only | Asserts dev/debug; fix transversal completo em Sessão 4C |

---

## 📊 Migrations / commits aplicadas (DB)

1. `b2_final_total_dual_write_commit1`
   - `ALTER TABLE orders ADD COLUMN final_total_numeric NUMERIC NULL`
   - Backfill 50 rows preenchidas (44 NULL preservados como NULL)
   - `CREATE FUNCTION fn_sync_final_total_numeric()`
   - `CREATE TRIGGER trg_zz_final_total_dual_write BEFORE INSERT OR UPDATE OF final_total`
   - COMMENTS coluna + função

2. `b3_extra_charge_settlement_marker`
   - `ALTER TABLE orders ADD COLUMN extra_charge_settled_at TIMESTAMPTZ NULL`
   - `ALTER TABLE orders ADD COLUMN extra_charge_settled_via TEXT NULL`
   - `CHECK CONSTRAINT orders_extra_charge_settled_via_check (NULL OR IN ('wallet','cash','none'))`
   - Backfill 0 rows (gate dry-run confirmou)

3. `b3_finalize_storeshopping_extra_charge_settled`
   - `CREATE OR REPLACE FUNCTION finalize_storeshopping_purchase` com 2 campos novos no UPDATE
   - Apenas wallet path: `extra_charge_settled_via='wallet'` quando `wallet_apply_post_delivery_adjustment` succeeds
   - Cash path diferido (sessão futura)

**Edge Functions deletadas via Supabase CLI 2.84.4:**
- `confirm-mbway-payment` (v11)
- `create-mbway-payment-intent-debug` (v1)
- Backups locais em `.claude/.ai/backups/edge_fns/`

---

## 📋 Análise transversal por bug

### B1 — Apagar Edge Fns
- **Cliente / estafeta / parceiro:** sem impacto (0 callers reais)
- **Admin:** `admin_edge_functions_screen` reflecte automaticamente via `list_edge_functions`
- **DB:** sem impacto
- **Comentários `order_store.dart:830, 2260`** actualizados para apontar `stripe-webhook`

### B2 — final_total dual-write
- **DB:** 24 callsites (11 RPCs + 1 trigger explícito + 9 Flutter + 3 Edge Fns + 0 views) continuam a ler `final_total` (double) — zero churn imediato
- **Cliente / estafeta / parceiro:** sem mudança (lêem `final_total` que continua a alimentar UI)
- **Admin:** sem mudança; `final_total_numeric` ainda invisível à UI até commit 2
- **Trigger `trg_zz_*`:** confirmado executa após todos os triggers `orders_*` ('o' < 't'); `trigger_credit_driver_on_delivery` é AFTER UPDATE OF status (não dispara em UPDATE de final_total) → zero conflito runtime

### B3 — extra_charge settlement marker
- **Cliente:** sem mudança (UI não mostra estado settlement)
- **Estafeta:** sem mudança
- **Parceiro:** sem mudança
- **Admin:** colunas `extra_charge_settled_at/via` disponíveis para queries (UI futura)
- **DB:** `finalize_storeshopping_purchase` agora marca settlement automaticamente quando wallet debit succeeds

### B4 — quote_order_pricing
- **Cliente:** sem mudança (cliente continua a calcular distance_km e enviar para quote + create_order)
- **Estafeta / parceiro / admin:** sem mudança
- **DB:** documentação apenas; signature `(p_input jsonb)` preservada
- **business_rules.md §29.5** documenta caller responsibility
- ⚠️ Anti-fraud (validação server-side) diferido para sessão dedicada

### B5 — Flutter productId (mitigação dev/debug)
- **Cliente:** assert protegido em DEV builds; release continua igual (assert strip)
- **Estafeta / parceiro / admin:** sem mudança directa
- **`cart_item.dart`:** construtor com 3 asserts; `_raw` privado para deserialização legacy via `fromJson`
- **4 call sites corrigidos** (errors fatais flutter analyze):
  - `restaurant_menu_screen.dart:187` — `item.productId ?? item.name`
  - `cart_store.dart:392, 477` — adicionado `productId: item.productId`
  - `order_store.dart:1732` — adicionado `productId: line.product.id` (PartnerProduct)

---

## 🛡️ Painel admin actualizado

- **B1:** `admin_edge_functions_screen` reflecte 19 fns ACTIVE (sem as 2 apagadas)
- **B2:** `admin_orders` / `admin_order_detail` continuam a usar `final_total` durante dual-write (transparente)
- **B3:** colunas `extra_charge_settled_at/via` disponíveis para queries SQL — UI futura mostrará "Liquidado em" / "Via" + filtro pendente/liquidado
- **B4:** documentação centralizada — admin pricing simulator usa mesma RPC
- **B5:** `admin_orders` lookup produto por ID continua a falhar em 86% dos orders legacy (Sessão 4C limpa)

---

## ✅ Smokes executados

### Funcionais novos (B1-B5)
- **S1** ✅ `list_edge_functions` retorna 19 fns ACTIVE, sem as 2 apagadas
- **S2** ✅ mismatches=0 entre `final_total` e `final_total_numeric` (94 orders)
- **S3** ✅ Trigger `trg_zz_final_total_dual_write` funcional via DO block UPDATE (sem erro = pass)
- **S4** ✅ Trigger ENABLED (`tgenabled='O'`)
- **S5** ✅ Colunas `extra_charge_settled_at/via` existem com CHECK constraint
- **S6** ✅ DO block sintético — UPDATE manual + CHECK rejeita valor inválido
- **S7** ⏭ diferido (RPC exige `auth.uid()`, MCP não tem)
- **S8** ✅ flutter analyze 52 issues, **0 errors** (paridade com baseline)
- **S9** ⏭ manual dev (não automatizado)

### Regressão
- **S10** ✅ coords NULL pós-0503 = 0
- **S11** ✅ 10 non-partner approved (markets)
- **S12** ✅ 7 reservation fns (incluindo `partner_mark_arrival`)
- **S13** ✅ cap 5 sacos enforced em `finalize_storeshopping_purchase`
- **S14-S18** ⏭ wallet flows (operacional — diferido smoke prod)
- **S19** ✅ bag_fee €0.30 restaurante non-partner
- **S20** ✅ partner saco 0€
- **S21** ⚠️ `promotional_balance_cents` CHECK NÃO encontrado (anomalia menor — anotada)
- **S22-S23** ⏭ visuais (diferidos para smoke prod)

**Triggers em orders pós-B2:** 18 (era 17, +1 = `trg_zz_final_total_dual_write`)

---

## 🐛 Colaterais novos descobertos / consolidados

1. **A4 / Fase B** — `orders.extra_charge_amount` é `double precision` (mesmo padrão C3) — sessão futura housekeeping
2. **A5** — `distance_km` server-side sem validação anti-fraud — sessão dedicada
3. **A6** — Bug-B fix 2026-04-30 não eliminou productId=name (67% pós-fix ainda têm bug) — Sessão 4C
4. **A6** — 11/30 orders recentes com `payment_status='failed'` — investigar correlação com productId=name
5. **A6** — 1 order `E2E2daa86` com productId NULL — caso edge a investigar
6. **S21** — `promotional_balance_cents` sem CHECK constraint — confirmar com Danilo se intencional (provável: promotional só admite >=0 logo CHECK redundante)
7. **B5** — Flutter call sites com legacy fallback ainda dispersos pelos 107 sites — Sessão 4C

---

## ⚠️ AVISOS PROD EXPLÍCITOS

### B5 — Mitigação NÃO protege produção

Asserts em `cart_item.dart` são **strip pelo compilador Dart em release/profile mode**. Significam:
- Em **dev/debug** (Android Studio Emulator, `flutter run`): asserts disparam → exception → app crash (detector funcionando)
- Em **release** (Play Store APK, App Store IPA): asserts são removidos → comportamento idêntico ao código pre-mitigação → cliente continua a poder gerar `productId=name` em call sites legacy

**Acção obrigatória:** Sessão 4C deve fazer fix transversal nos 107 call sites + limpeza retroactiva orders.items históricos.

### B2 commit 2 — Ordem obrigatória após +24h smoke prod

DROP TRIGGER → DROP FUNCTION → DROP COLUMN final_total → RENAME final_total_numeric → final_total. **Não desviar.**

### B3 — Cash settlement path

Arquitectura actual não atribui `extra_charge_amount > 0` em pagamentos cash (sistema paralelo `cash_total_due`). Settlement marker `'cash'` nunca é atribuído pela função actual — fica para sessão futura quando arquitectura for unificada.

---

## ⏭ TODOs adiados

Ver `.claude/.ai/todos/sessao_4_pending.md` (criado nesta sessão).

Itens-chave:
- C3 commit 2 (ordem obrigatória)
- B5 completo Sessão 4C (107 call sites + limpeza retroactiva)
- Sessão 4B push notifications geo-aware
- Sessão 5 Botão Suporte FAB
- Wallet split 80/20 promocional
- Anti-fraud distance_km
- Housekeeping financeiro `extra_charge_amount` double → numeric
- BUG 34 orders.id TEXT (Sessão 7)

---

## 📁 Ficheiros tocados

### Modificações Flutter
- `lib/models/cart_item.dart` — refactor com `_raw` constructor + 3 asserts
- `lib/screens/restaurant_menu_screen.dart` (linha 187)
- `lib/stores/cart_store.dart` (linhas 392, 477)
- `lib/stores/order_store.dart` (linhas 830-833, 2260, 1732)

### Documentação
- `.claude/.ai/business_rules.md` — §29 adicionado (housekeeping financeiro Sessão 4)
- `.claude/.ai/todos/sessao_4_pending.md` — criado
- `.claude/.ai/reports/20260502_megafinal/04_bugs_colaterais_analise.md` — Fase A (criado em sessão anterior, corrigido `'settlement'` literal)
- `.claude/.ai/reports/20260502_megafinal/04_bugs_colaterais_report.md` — este ficheiro

### Migrations Supabase (3)
- `b2_final_total_dual_write_commit1`
- `b3_extra_charge_settlement_marker`
- `b3_finalize_storeshopping_extra_charge_settled`

### Backups Edge Fns
- `.claude/.ai/backups/edge_fns/confirm-mbway-payment_v11.ts`
- `.claude/.ai/backups/edge_fns/create-mbway-payment-intent-debug_v1.ts`

---

## ⛔ Aguardando luz verde Danilo

Próximos passos pendentes:
1. **Commit atómico** dos changes Flutter + business_rules.md + reports + backups
2. **Push** para branch `autonomous-night-2026-04-29`
3. Confirmar arrancar Sessão 4B / 4C / 5

⚠️ NÃO foi feito commit ainda. Migrations DB já estão APLICADAS em prod (não rolláveis sem migration nova).
