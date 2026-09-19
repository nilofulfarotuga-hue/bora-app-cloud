# Sessão 2/7 — Fase A · Análise discrepâncias regra vs código

**Data:** 2026-05-03
**Branch:** `autonomous-night-2026-04-29`
**Pré-requisito:** Sessão 1 fechada (commit `114a8ff`).
**Modo:** PROTECÇÃO TOTAL — análise SEM mexer código.

---

## TL;DR

| Item | Verdict | Acção Fase B |
|------|---------|--------------|
| Regressão BUG 1 Sessão 1 (coords NULL) | ✅ OK (0 rows) | nenhuma |
| D1 — service_fee Flutter vs RPC | ✅ Já correcto | nenhuma |
| D2 — driver_earnings Flutter vs RPC | ✅ Já correcto | nenhuma |
| D3 — enum `OrderServiceType` / `foodDelivery` | ✅ Nada quebrado | nenhuma |
| D4 — Reservation RPCs prod vs git | ❌ Divergência | **sync git ← prod** |
| D5 — `orders.delivered_at` NULL backfill | ✅ 0 gaps | nenhuma |

**Decisão:** **NÃO early-exit.** Apenas D4 requer trabalho em Fase B (sync `pg_get_functiondef` → migration consolidada, ZERO mudanças funcionais).

---

## 0. Regressão check — Sessão 1 BUG 1

```sql
SELECT COUNT(*) FROM orders
WHERE created_at > '2026-05-03'
  AND (dropoff_lat IS NULL OR dropoff_lng IS NULL);
-- → 0
```

✅ Fix `create_order` v2.1 mantém-se sólido. Sem regressão.

---

## 1. D1 — `service_fee` Flutter

### Classificação X/Y → **[X] PREVIEW-ONLY**

Evidência ([lib/stores/order_store.dart:714-769](lib/stores/order_store.dart#L714-L769)):

```dart
final dynamic rpcResult =
    await supabase.rpc('create_order', params: {'p_input': rpcInput});
final rpcData = Map<String, dynamic>.from(rpcResult as Map);
serverOrder = OrderModel(
  …
  serviceFee: (rpcData['service_fee'] as num).toDouble(),       // ← RPC
  driverEarnings: (rpcData['driver_earnings'] as num).toDouble(), // ← RPC
  platformCommission: (rpcData['platform_commission'] as num).toDouble(),
  bagFee: (rpcData['bag_fee'] as num? ?? 0).toDouble(),
  …
);
```

→ Fluxo principal cliente: **RPC autoritativo**. `PricingService.calculateBreakdown` é só preview UX (cart, payment_method).
→ Excepção: `OrderStore.createPartnerDeliveryRequest` ([:1656](lib/stores/order_store.dart#L1656)) calcula localmente e grava via `_saveOrderToDatabase`. **Mas:** este path é só usado pelo parceiro a criar request manual (sem RPC `create_order`); valores são identicos à RPC.

### Estado actual `pricing_service.dart`

| Caso | Linha | Fórmula Flutter | Regra (RPC) | Match |
|------|-------|-----------------|-------------|-------|
| PARTNER (rest. + retail) | [:145](lib/services/pricing_service.dart#L145) | `subtotal × 0.05` | `subtotal × 0.05` | ✅ |
| NON-PARTNER (rest. + storeShopping) | [:159, :163](lib/services/pricing_service.dart#L159) | `purchaseFee = €2.50` (constante) | `delivery_base_fee_cents = 250` | ✅ |
| sendPackage / carryGroceries | [:186-197](lib/services/pricing_service.dart#L186-L197) | sem service_fee separado (incluído em `packageFee`) | idem | ✅ |

**Diff esperado UI checkout vs RPC:** €0.00 nominal. Bug D1 do relatório antigo (5% genérico não-parceiro) **NÃO existe** neste branch — `_nonPartnerPurchaseFee = 2.5` está hard-coded como service_fee.

→ **Verdict D1: ✅ VERIFICADO. Sem fix.**

---

## 2. D2 — `driver_earnings` Flutter

### Classificação X/Y → **[X] PREVIEW-ONLY** (mesmo argumento de D1)

### Estado actual `pricing_service.dart`

| Caso | Linhas | Fórmula Flutter | Regra | Match |
|------|--------|-----------------|-------|-------|
| PARTNER (rest. + retail) | [:150-153](lib/services/pricing_service.dart#L150-L153) | `€3.80 + €0.20×km + apt + (stack? €3 : 0)` | base + per_km×km + apt + stack (SEM €0.80, SEM 30%) | ✅ |
| NON-PARTNER **storeShopping** | [:171-185](lib/services/pricing_service.dart#L171-L185) | `€3.80 + €0.80 + €0.20×km + apt + 30%×boraNet` | base + €0.80 + per_km×km + apt + 30%×boraNet | ✅ |
| NON-PARTNER **restaurant** | [:171-185](lib/services/pricing_service.dart#L171-L185) | `€3.80 + €0.20×km + apt + 30%×boraNet` (`shoppingBonus = 0`) | base + per_km×km + apt + 30%×boraNet (sem €0.80) | ✅ |
| LOGISTICS (carry/sendPackage) | [:194-197](lib/services/pricing_service.dart#L194-L197) | `€4.00 + €0.50×km + €0.80 + apt` | idem | ✅ |

Discriminador `shoppingBonus` (linhas [:171-172](lib/services/pricing_service.dart#L171-L172)):

```dart
final shoppingBonus =
    serviceType == OrderServiceType.storeShopping ? _shoppingDriverBonus : 0.0;
```

→ €0.80 aplicado **apenas** em `storeShopping` não-parceiro. Restaurant não-parceiro NÃO recebe €0.80. Conforme regras.

**Diff esperado tela ganhos estafeta vs `compute_driver_settlement` RPC:** €0.00 nominal — `OrderModel.driverEarnings` é populado pela RPC `create_order`, não pelo cálculo local.

→ **Verdict D2: ✅ VERIFICADO. Sem fix.**

---

## 3. D3 — enum `OrderServiceType` / `foodDelivery`

### Definição ([lib/models/order_service_type.dart:1-6](lib/models/order_service_type.dart#L1-L6))

```dart
enum OrderServiceType {
  restaurant,
  storeShopping,
  carryGroceries,
  sendPackage,
}
```

### Findings

- **Zero referências a `foodDelivery`** em todo o `lib/`.
- 4 valores; todos os 4 ramos `case` aparecem em `label`, `iconKey`, `DriverModel.supportsService`.
- Diferenciação restaurant ↔ storeShopping no checkout/dispatch via `isPartnerStore` (campo TEXT em `orders`, bool em models).
- 12 ficheiros consomem o enum; nenhum branch unreachable nem referência a símbolo inexistente.

### Definição "código quebrado" (compile error / runtime exception / branch nunca executa)

→ **Nenhum critério satisfeito.** Não há código quebrado.

→ **Verdict D3: ✅ VERIFICADO. Sem fix.**

---

## 4. D4 — Reservation RPCs · prod vs git

### Prod (6 RPCs)

| `proname` | args | def_hash (md5) | def_len |
|-----------|------|----------------|---------|
| `admin_reservations_metrics` | `p_days integer` | `f0254ede…` | 1990 |
| `admin_reservations_today` | — | `5d0c4204…` | 1003 |
| `auto_close_no_show_reservations` | — | `463bc92a…` | 1259 |
| `client_cancel_reservation` | `p_reservation_id uuid, p_reason text` | `3609a4a2…` | 2359 |
| `client_confirm_reservation_payment` | `p_reservation_id uuid` | `e52f212e…` | 1357 |
| `partner_decide_reservation` | `p_reservation_id uuid, p_accept boolean, p_reason text` | `5bf1c297…` | 1772 |

Total: **6 funções, ~10 KB de definições.**

### Git — `supabase/migrations/`

3 ficheiros tocam reservas:

```
supabase/migrations/20260418030000_restaurant_reservations_enabled.sql      16 linhas
supabase/migrations/20260430230000_categories_reservations_session.sql      57 linhas
supabase/migrations/20260430240000_reservations_split_v2.sql                37 linhas
```

`grep -E 'CREATE\s+(OR\s+REPLACE\s+)?FUNCTION'` em cada um → **0 matches**. Apenas DDL de tabelas/colunas/índices.

`reservations_split_v2.sql` tem comentário explícito:

> All RPCs (partner_mark_arrival v2, create_order v3 with menu credit, …, client_get_active_menu_credit) — **definitions complete em prod via MCP**.

### Diff

**6 RPCs em prod, 0 definições em git.** Schema declarativo (`supabase/schema.sql`) não cobre funções — só tabelas. Significa qualquer rebuild from-scratch (CI replay, novo ambiente) **não recriaria as 6 RPCs**, partindo o painel admin de reservas e os RPCs cliente/parceiro.

### Acção Fase B

Migration consolidada `supabase/migrations/<TIMESTAMP>_reservation_rpcs_sync.sql`:

- `CREATE OR REPLACE FUNCTION` para cada uma das 6, copiada literalmente de `pg_get_functiondef(oid)`.
- Idempotente (replay-safe).
- ZERO mudanças funcionais (só captura prod actual).
- Validação: re-aplicar em prod (`apply_migration`) deve devolver `def_hash` identico antes/depois.
- Smoke MCP S1-S6 (criar/confirmar/arrival/cancel pré-2h/cancel pós-2h/no-show) apenas para confirmar que continuam a executar — sem testar regras de negócio em si.

**Esforço:** 30-40 min (incluindo smoke).

→ **Verdict D4: ❌ DIVERGÊNCIA. Sync obrigatório em Fase B.**

---

## 5. D5 — `orders.delivered_at` NULL backfill

```sql
SELECT COUNT(*) FROM orders WHERE status='delivered' AND delivered_at IS NULL;
-- → 0
SELECT MIN(created_at), MAX(created_at) FROM …;
-- → NULL, NULL
```

→ **Verdict D5: ✅ 0 gaps.** Não criar TODO em `sessao_2_pending.md`. Sem trabalho.

---

## Análise impacto

| Item | Risco se NÃO fixar | Esforço fix |
|------|--------------------|-------------|
| D1 / D2 / D3 / D5 | **0** — já correctos | 0 |
| D4 | CI replay falha; novo ambiente sem RPCs reservas; rollback de prod fica inviável (não há código a reaplicar). Risco médio para devops, baixo para utilizador final actual (prod tem as funções). | ~40 min |

---

## Decisão Fase B

**Não early-exit** (D4 tem trabalho real).

**Ordem fixa:** apenas D4 → 1 commit atómico:
- `feat(db): sync reservation RPCs git ← prod (BUG D4)` — migration consolidada com 6 `CREATE OR REPLACE FUNCTION` extraídas de `pg_get_functiondef`.
- `flutter analyze`: nenhum impacto (só DB).
- Smoke MCP S1-S6 em prod **apenas a confirmar execução**.
- Push após commit.

**Sem trabalho:** D1, D2, D3, D5, regression check.

**Atualização `business_rules.md`:** confirmar regras (já correctas no código), documentar que `pricing_service.dart` é preview-only [X] e RPC `pricing_calculate` / `create_order` são fonte autoritativa.

---

## ⛔ STOP — aguardar luz verde Danilo para Fase B
