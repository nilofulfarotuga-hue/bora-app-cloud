---
date: 2026-04-25
type: pricing
files_affected:
  - supabase/migrations/20260425000010_fix_bag_fee.sql
  - lib/services/notification_service.dart
  - lib/stores/order_store.dart
commit: 1b7030f
ceo_ai_section: "Estado do Sistema — PRONTO + LAUNCH BLOCKERS"
approved_by: Danilo
tags: [rules, pricing, bag-fee, launch-blocker-closed]
---

# Bag Fee Fix — BUG-MN-015 Fechado

## Antes

- `pricing_calculate` calculava `v_bag_fee` internamente mas **não o expunha** no `RETURNS TABLE` — estava apenas somado em `customer_total`
- `create_order` lia `bag_fee` do input do cliente (`p_input->>'bag_fee'`) — Flutter nunca enviava este campo → coluna `bag_fee` na DB ficava sempre **€0.00**
- Restaurante: cliente pagava o total correcto (€0.30 incluído em `customer_total`) mas a coluna `bag_fee` ficava €0 — split errado no recibo
- Mercado (`storeShopping`): `updateBagCount` guardava `bag_count` mas **não calculava nem guardava `bag_fee`** → `finalizePurchase` recalculava o total sem sacos → cliente nunca era cobrado pelos sacos
- Sem notificação push ao cliente quando estafeta contava sacos

## Depois

- `pricing_calculate`: `bag_fee NUMERIC` adicionado ao `RETURNS TABLE` → exposto como coluna separada
- `create_order`: usa `v_pricing.bag_fee` (calculado pelo servidor) em vez do input do cliente
- `updateBagCount` (Dart): guarda `bag_fee = count × €0.10` no DB + estado local; dispara push ao cliente quando `count > 0`
- `finalizePurchase` (Dart): soma `order.bagFee` ao `computedFinalTotal` para `storeShopping`
- `NotificationService.notifyClientBagCount`: novo método — push "🛍️ X sacos × €0.10 = €X.XX"

## Regras de negócio (imutáveis — confirmadas)

| Tipo de ordem | Bag fee | Quando |
|---------------|---------|--------|
| Restaurante parceiro | €0.30 fixo | Automático na criação da ordem |
| Restaurante não-parceiro | €0.30 fixo | Automático na criação da ordem |
| Mercado (storeShopping) | €0.10 × nº sacos | Estafeta conta no checkout via `updateBagCount` |

## Motivo

Bug financeiro: clientes de mercado não estavam a ser cobrados pelos sacos de plástico.
Coluna `bag_fee` em restaurante ficava €0 apesar do total correcto — inconsistência de reporting.

## Impacto

- Receita aumenta: cada encomenda de mercado passa a cobrar sacos correctamente
- Transparência: coluna `bag_fee` no recibo agora reflecte o valor real
- UX cliente: push informativo quando sacos são adicionados

## Testes live confirmados (2026-04-25)

```sql
pricing_calculate('restaurant',    20, 2, TRUE,  FALSE, FALSE) → bag_fee=0.30 ✅
pricing_calculate('restaurant',    20, 2, FALSE, FALSE, FALSE) → bag_fee=0.30 ✅
pricing_calculate('storeShopping', 35, 2, FALSE, FALSE, FALSE) → bag_fee=0.00 ✅
```

## Ficheiros

- `supabase/migrations/20260425000010_fix_bag_fee.sql` — DROP + CREATE `pricing_calculate` com `bag_fee` no RETURNS TABLE; CREATE OR REPLACE `create_order` com `v_pricing.bag_fee`
- `lib/stores/order_store.dart` — `updateBagCount` + `finalizePurchase`
- `lib/services/notification_service.dart` — método `notifyClientBagCount`
