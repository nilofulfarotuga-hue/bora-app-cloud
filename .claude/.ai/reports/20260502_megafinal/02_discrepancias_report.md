# Sessão 2/7 — Fase B · Discrepâncias regra vs código · RELATÓRIO FINAL

**Data:** 2026-05-03
**Branch:** `autonomous-night-2026-04-29`
**Modo:** PROTECÇÃO TOTAL — fix aprovado item-a-item.
**Pré-requisito:** Sessão 1 fechada (`114a8ff`).

---

## TL;DR

| Item | Verdict | Trabalho Fase B |
|------|---------|-----------------|
| Regressão BUG 1 Sessão 1 | ✅ 0 rows | nenhum |
| **D1** service_fee Flutter | ✅ Já correcto (PREVIEW-ONLY) | nenhum (só docs) |
| **D2** driver_earnings Flutter | ✅ Já correcto (PREVIEW-ONLY) | nenhum (só docs) |
| **D3** enum `OrderServiceType` | ✅ Sem `foodDelivery`, sem código quebrado | nenhum |
| **D4** Reservation RPCs prod vs git | ❌ → ✅ **SYNC APLICADO** | 1 commit |
| **D5** `delivered_at` NULL backfill | ✅ 0 gaps | nenhum |

**1 commit atómico** (D4). **Flutter analyze:** 52 issues = baseline (0 errors). **0 colaterais**.

---

## D4 · Reservation RPCs — Git ← Prod sync

### Antes
6 RPCs descobertos por grep `reservation|reserva|booking` + 1 omissão detectada na validação MCP do Danilo (`partner_mark_arrival`, sem keyword no nome). **Total 7 RPCs em prod, 0 definições em git.**

`supabase/migrations/20260430240000_reservations_split_v2.sql` chega a admitir:
> All RPCs (partner_mark_arrival v2, …) — definitions complete em prod via MCP.

### Depois
Nova migration `supabase/migrations/20260503020000_reservation_rpcs_sync.sql` (15 855 bytes, 415 linhas) com 7 `CREATE OR REPLACE FUNCTION` extraídos byte-a-byte de `pg_get_functiondef()`.

### Validação byte-equivalence (replay-safety)

Pre-replay e post-replay hashes comparados em prod:

| RPC | def_hash (md5) | def_len | match |
|-----|---------------|---------|-------|
| `admin_reservations_metrics` | `f0254edeec1833f06e5d4289df7e20ed` | 1990 | ✅ |
| `admin_reservations_today` | `5d0c42046ddeaaa0443c2af03b478f68` | 1003 | ✅ |
| `auto_close_no_show_reservations` | `463bc92ae71d51856f50eb5abcb70a20` | 1259 | ✅ |
| `client_cancel_reservation` | `3609a4a291d38b29c59b4d971743e3f0` | 2359 | ✅ |
| `client_confirm_reservation_payment` | `e52f212e03458760171ee2d742c135c0` | 1357 | ✅ |
| `partner_decide_reservation` | `5bf1c297f4136cca19f5c08d14054c06` | 1772 | ✅ |
| `partner_mark_arrival` | `185b8626abd8a2cee757d14adac8bda4` | 3041 | ✅ |

**Todos idênticos pré/pós-replay** → migration é replay-safe e ZERO mudanças funcionais.

### Smoke S1-S7 (só execução, não regras)

| # | RPC | Resposta esperada | Resposta real |
|---|-----|-------------------|---------------|
| S1 | `client_confirm_reservation_payment(uuid)` | `auth_required` | ✅ `auth_required` |
| S2 | `partner_decide_reservation(uuid, true)` | `auth_required` | ✅ `auth_required` |
| S3 | `partner_mark_arrival(uuid)` | `auth_required` | ✅ `auth_required` |
| S4 | `client_cancel_reservation(uuid)` | `auth_required` | ✅ `auth_required` |
| S5 | `admin_reservations_metrics(7)` | `_admin_op_guard` | ✅ `admin_required: not authenticated` |
| S6 | `auto_close_no_show_reservations()` | ok (sem auth) | ✅ `ok` |
| S7 | `admin_reservations_today()` | `_admin_op_guard` | ✅ `admin_required: not authenticated` |

Todos os 7 RPCs parseiam, executam, atingem o auth check. Sem syntax errors. Zero regressão.

### Não-incluído (escopo Sessão futura)
- `admin_list_partner_payouts` — domínio payouts
- `admin_mark_partner_payouts_paid` — domínio payouts
- `admin_partner_payout_summary` — domínio payouts

---

## D1 · service_fee Flutter — VERIFICADO ✅

Classificação `pricing_service.dart` → **[X] PREVIEW-ONLY**.
Evidência: [lib/stores/order_store.dart:714-769](lib/stores/order_store.dart#L714-L769) — `OrderModel` é populado integralmente a partir de `rpcData` (`service_fee`, `driver_earnings`, `platform_commission`, `bag_fee`, `payment_buffer_total`).

| Caso | Flutter ([:145, :159, :163](lib/services/pricing_service.dart#L145)) | RPC `pricing_calculate` | Match |
|------|----------------------------------|-------------------------|-------|
| PARTNER | `subtotal × 0.05` | `client_service_fee_pct = 0.05` | ✅ |
| NON-PARTNER | `_nonPartnerPurchaseFee = €2.50` (constante) | `delivery_base_fee_cents = 250` | ✅ |
| LOGISTICS | sem service_fee separado | sem service_fee separado | ✅ |

**Diff esperado UI vs RPC:** €0,00. Bug D1 do relatório antigo (5% genérico não-parceiro) NÃO existe neste branch.

---

## D2 · driver_earnings Flutter — VERIFICADO ✅

| Caso | Flutter ([:150-185, :194-197](lib/services/pricing_service.dart#L150-L197)) | Match com regra |
|------|---|---|
| PARTNER | `€3.80 + €0.20×km + apt + (stack? €3 : 0)` (SEM €0.80, SEM 30%) | ✅ |
| NON-PARTNER **storeShopping** | `€3.80 + €0.80 + €0.20×km + apt + 30%×boraNet` | ✅ |
| NON-PARTNER **restaurant** | `€3.80 + €0.20×km + apt + 30%×boraNet` (`shoppingBonus = 0`) | ✅ |
| LOGISTICS | `€4.00 + €0.50×km + €0.80 + apt` | ✅ |

Discriminador correcto em [:171-172](lib/services/pricing_service.dart#L171-L172):
```dart
final shoppingBonus =
    serviceType == OrderServiceType.storeShopping ? _shoppingDriverBonus : 0.0;
```

→ €0.80 só `storeShopping` não-parceiro. Restaurant não-parceiro NÃO recebe. Conforme regras.

---

## D3 · enum `OrderServiceType` — VERIFICADO ✅

`lib/models/order_service_type.dart`: 4 valores (`restaurant`, `storeShopping`, `carryGroceries`, `sendPackage`). Zero referências a `foodDelivery`. Todos os 4 cases aparecem em `label`, `iconKey`, `DriverModel.supportsService`. 12 ficheiros consomem o enum sem branches inalcançáveis.

→ Sem código quebrado. Diferenciação restaurant ↔ storeShopping continua via `isPartnerStore`.

---

## D5 · `orders.delivered_at` NULL backfill — VERIFICADO ✅

```sql
SELECT COUNT(*) FROM orders WHERE status='delivered' AND delivered_at IS NULL;
-- → 0
```

0 gaps. Sem TODO em `sessao_2_pending.md`.

---

## Regressão Sessão 1 — VERIFICADO ✅

```sql
SELECT COUNT(*) FROM orders
WHERE created_at > '2026-05-03'
  AND (dropoff_lat IS NULL OR dropoff_lng IS NULL);
-- → 0
```

Fix BUG 1 (`create_order` v2.1) mantém-se sólido.

---

## Outputs

### Ficheiros tocados
- ➕ `supabase/migrations/20260503020000_reservation_rpcs_sync.sql` (415 linhas, 7 RPCs)
- ✏ `.claude/.ai/business_rules.md` (§2.2 explícita partner/non-partner; §2.2.1 driver_earnings table; §2.6 fonte autoritativa + classificação PREVIEW-ONLY)
- ➕ `.claude/.ai/reports/20260502_megafinal/02_discrepancias_analise.md` (relatório Fase A)
- ➕ `.claude/.ai/reports/20260502_megafinal/02_discrepancias_report.md` (este ficheiro)

### Commits
- 1 commit atómico: D4 sync git ← prod (BUG D4)

### Validações
- `flutter analyze`: **52 issues = baseline** (0 errors). ✅
- Replay-safety: 7/7 hashes idênticos pré/pós-replay. ✅
- Smoke S1-S7: 7/7 RPCs executam correctamente. ✅

### 🐛 Colaterais detectados
**Nenhum.** Análise Fase A não detectou bugs novos fora do escopo D1-D5.

---

## Sumário negocial

A Sessão 2 resolveu uma **dívida técnica de devops** (D4: 7 RPCs do domínio reservas existiam em prod sem ficheiros git, aplicados via MCP sem registo). Risco para utilizador final actual = baixo (prod tinha as funções); risco para CI replay / novo ambiente = alto (rebuild from-scratch falharia). Agora migration consolidada garante reproducibilidade.

D1, D2, D3, D5 e regressão BUG 1 — todos verificados como já correctos. Sem código a alterar. Apenas documentação reforçada em `business_rules.md` capturando a regra confirmada via MCP (service_fee não-parceiro €2,50 fixo, driver_earnings tabela completa, classificação Flutter PREVIEW-ONLY).
