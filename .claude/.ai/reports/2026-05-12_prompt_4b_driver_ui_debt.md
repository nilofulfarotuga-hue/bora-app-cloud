# PROMPT 4b — Driver UI debt_collected_cents + business_rules §54

**Data:** 2026-05-12
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** Sonnet 4.6
**Status:** ✅ EXECUTADO COMPLETO — **push NÃO efectuado** (aguarda Danilo)

---

## RESULTADO

### 3 ficheiros modificados

| # | Ficheiro | Tipo | Mudanças |
|---|----------|------|----------|
| 1 | `lib/models/order_model.dart` | Edit | 5 adições (field + constructor param + getter totalToCollectCash + getter hasCashDebt + fromSupabase + toSupabase) |
| 2 | `lib/screens/driver_home_screen.dart` | Edit | Substituição cirúrgica do bloco "COBRAR EM DINHEIRO" (linhas ~1208-1235) para mostrar `order.totalToCollectCash` + linha extra laranja `#E65100` quando `order.hasCashDebt` |
| 3 | `bora_app/.claude/.ai/business_rules.md` | Edit | §54 substituída pelo texto canónico PROMPT 4a/4b (mecanismos 1/2a/2b/3 + tabela idem-keys) + footer "Última atualização" |

---

## PRÉ-REQUISITOS — 3/3 ✅

| # | Check | Resultado |
|---|---|---|
| 1 | `orders.debt_collected_cents` existe | ✅ col_exists=1 |
| 2 | Zero pedidos com dívida em produção | ✅ total_orders=6, orders_com_divida=0 |
| 3 | Branch limpa, HEAD = `2f0b513` | ✅ |

---

## INVESTIGAÇÃO READ-ONLY

**Order model:** [lib/models/order_model.dart](lib/models/order_model.dart)
- Class declaration: linha 43
- Field declarations: linhas 117 (`walletAppliedCents`), 121 (`menuCreditAppliedCents`) — `debtCollectedCents` adicionado a seguir
- Constructor: linhas 180-254 — param `this.debtCollectedCents = 0` adicionado após `menuCreditAppliedCents`
- `fromSupabase`: linha 265-408 — adicionado mapping após `menuCreditAppliedCents`
- `toSupabase`: linhas 411+ — adicionado `if (debtCollectedCents > 0) 'debt_collected_cents': debtCollectedCents`

**Driver UI:** [lib/screens/driver_home_screen.dart:1208-1235](lib/screens/driver_home_screen.dart#L1208-L1235)
- Linha 1189: chip `"Pedido"` mostra `order.total` (preço pedido, sem dívida) — **MANTIDO** (label diferente, não é cobrança)
- Linhas 1208-1235: bloco `"COBRAR EM DINHEIRO"` quando `paymentMethod == cash` — **SUBSTITUÍDO** para mostrar total real + linha dívida

Hierarquia de cobrança identificada (cascata existente preservada):
`(cashTotalDue ?? finalTotal ?? total) + debtCollectedCents/100.0`

---

## DIFFS APLICADOS

### FIX 1 — `lib/models/order_model.dart`

**1a) Field declaration** (após linha 121 `menuCreditAppliedCents`):
```dart
/// BUG #1 frontend (§54 / 2026-05-12) — cents da dívida prévia da wallet
/// do cliente que é cobrada via este pedido. Populado pela RPC create_order
/// quando v_wallet_balance_pre<0. Default 0. Driver UI em CASH cobra:
/// totalToCollectCash = (cashTotalDue ?? finalTotal ?? total) + debtCollectedCents/100.
final int debtCollectedCents;
```

**1b) Constructor parameter** (após `this.menuCreditAppliedCents = 0,`):
```dart
this.debtCollectedCents = 0,
```

**1c) Getters** (após constructor terminar, antes do comentário do fromSupabase):
```dart
// BUG #1 frontend (§54 / 2026-05-12) — Driver UI helpers em CASH
double get totalToCollectCash =>
    (cashTotalDue ?? finalTotal ?? total) + debtCollectedCents / 100.0;
bool get hasCashDebt => debtCollectedCents > 0;
```

**1d) fromSupabase** (após `menuCreditAppliedCents:`):
```dart
debtCollectedCents:
    (data['debt_collected_cents'] as num?)?.toInt() ?? 0,
```

**1e) toSupabase** (após `if (menuCreditAppliedCents > 0) ...`):
```dart
if (debtCollectedCents > 0) 'debt_collected_cents': debtCollectedCents,
```

### FIX 2 — `lib/screens/driver_home_screen.dart:1208-1235`

Bloco "COBRAR EM DINHEIRO" passou de `Row` simples para `Column` com 2 linhas:
- Linha 1: `'COBRAR EM DINHEIRO: €${order.totalToCollectCash.toStringAsFixed(2)}'` (laranja escuro)
- Linha 2 (condicional `if (order.hasCashDebt)`): `'↳ inclui €${(order.debtCollectedCents / 100).toStringAsFixed(2)} de dívida anterior'` em laranja `#E65100`, fontStyle italic, fontSize 12, padding-left 28

### FIX 3 — `business_rules.md` §54

Texto canónico PROMPT 4a/4b com mecanismos 1/2a/2b/3 explícitos + tabela idem-keys + footer "Última atualização" actualizado.

---

## ÁREAS PROIBIDAS RESPEITADAS

✅ Zero SQL/triggers/RPCs/Edge Functions tocadas.
✅ Zero migrations.
✅ Apenas: order_model.dart (aditivo, sem breaking changes), driver_home_screen.dart (substituição cirúrgica de bloco existente), business_rules.md §54 (doc).

---

## VALIDAÇÃO FLUTTER ANALYZE

[a anexar após terminar background]

---

## 3 COMMITS A FAZER

1. `feat(flutter): order_model add debtCollectedCents + totalToCollectCash getter`
2. `feat(flutter): driver UI show total to collect in CASH with debt line`
3. `docs(business_rules): §54 update - lifecycle settle por payment_method + tabela idem-keys`

---

*Relatório gerado pelo Claude Code Sonnet 4.6 — 2026-05-12*
