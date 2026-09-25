# Batch D — Pricing & Tokens Overhaul
**Data:** 2026-04-25  
**Estado:** ✅ Implementado e deployed

---

## Motivação

Correcção de 6 bugs/inconsistências acumuladas nas regras de negócio:
1. Comissão parceiro estava flat 20% sem separação contabilística
2. €0.80 bónus era aplicado a todos, incluindo restaurant drivers (errado)
3. Driver não tinha partilha do lucro Bora (non-partner)
4. Token cliente: factor-100 bug (× 0.03 em vez de × 3)
5. Token driver: flat 40 independente de ser parceiro ou não
6. Package/logistics drivers não recebiam €0.80 mesmo fazendo recolha física

---

## Alterações

### `lib/services/pricing_service.dart`

| Constante | Antes | Depois |
|---|---|---|
| `_partnerCommissionRate` | 0.20 | 0.10 (apenas visible) |
| `_partnerServiceFeeRate` | — | 0.05 (NOVO) |
| `_partnerMarkupHiddenRate` | — | 0.05 (NOVO) |
| `_partnerStackingBonus` | — | 3.00 (NOVO) |
| `_driverProfitShareRate` | — | 0.30 (NOVO) |

**Novo parâmetro:** `isStackedPartnerBonus` em `calculateBreakdown()`  
**Novo campo:** `partnerMarkupHidden` em `OrderPricingBreakdown`

#### Bloco non-partner
- €0.80 → só `storeShopping` (antes: todos non-partner)
- Driver = base + bonus + km + 30% × (bora_markup + delivery + service - driver_fixed)

#### Bloco partner
- `serviceFee` = 5% × subtotal (NOVO — aparece no recibo do cliente)
- `platformCommission` = 10% × subtotal (era 20%)
- `driverEarnings` += `_partnerStackingBonus` se `isStackedPartnerBonus`

#### Bloco logistics (carry/send)
- Adicionado `_shoppingDriverBonus` (€0.80) — faltava completamente

### SQL — `pricing_calculate()`

Mesmas regras espelhadas em SQL. Nova assinatura:
```sql
pricing_calculate(service_type, subtotal, distance_km, is_partner_store, apartment_delivery, is_stacked_partner)
```
Retorna 6 colunas (antes 5): adicionado `partner_markup_hidden`.

### SQL — `fn_award_tokens_on_delivery()`

| Campo | Antes | Depois |
|---|---|---|
| Driver tokens | 40 flat | 50 partner / 40 non-partner |
| Client tokens | `ROUND(price × 0.03)` | `ROUND(price × 3)` |

**Impacto no cliente:** pedido de €50 → antes: 2 tokens (€0.01) → agora: 150 tokens (€0.75)

### DB — `orders` table

3 novas colunas:
- `partner_commission_visible` — 10% × subtotal (partner only)
- `partner_markup_hidden` — 5% × subtotal (partner only)  
- `partner_service_fee_client` — 5% × subtotal (partner only)

### `create_order` RPC

- Usa `RECORD` em vez de `JSONB` para o resultado de `pricing_calculate`
- Popula as 3 novas colunas
- Expõe `partner_markup_hidden` no JSON de resposta

---

## Cenários de validação

### Cenário A — Restaurante parceiro, 2km, subtotal €30
- `delivery_fee` = €2.50
- `service_fee` = €1.50 (5%)
- `platform_commission` = €3.00 (10%)
- `partner_markup_hidden` = €1.50 (5%)
- `driver_earnings` = €3.80 + €0.40 = €4.20
- `customer_total` = €30 + €1.50 + €2.50 = €34.00

### Cenário B — Restaurante não-parceiro (fast food), 3km, subtotal €25 (com 15% markup já incluído)
- `delivery_fee` = €2.50, `service_fee` = €2.50
- `driver_fixed` = €3.80 + €0 + €0.60 = €4.40 (sem €0.80 — é restaurant)
- `bora_gross` = €3.75 + €2.50 + €2.50 = €8.75
- `bora_net` = €8.75 − €4.40 = €4.35
- `driver_earnings` = €4.40 + €1.31 = €5.71
- `customer_total` = €25 + €2.50 + €2.50 = €30.00

### Cenário C — storeShopping não-parceiro, 5km, subtotal €80
- `delivery_fee` = €2.50 + €0.50 = €3.00 (1km extra)
- `service_fee` = €2.50
- `driver_fixed` = €3.80 + €0.80 + €1.00 = €5.60
- `bora_gross` = €12.00 + €3.00 + €2.50 = €17.50
- `bora_net` = €17.50 − €5.60 = €11.90
- `driver_earnings` = €5.60 + €3.57 = €9.17
- `customer_total` = €80 + €2.50 + €3.00 = €85.50

### Cenário D — carryGroceries, 3km
- `delivery_fee` = €6.00, `platform_commission` = €2.00
- `driver_earnings` = €4.00 + €1.50 + €0.80 = €6.30 ✅ (€0.80 incluído)

---

## Ficheiros modificados

- `lib/services/pricing_service.dart`
- `supabase/migrations/20260425000001_batch_d_pricing_calculate.sql`
- `supabase/migrations/20260425000002_batch_d_tokens.sql`
- `supabase/migrations/20260425000003_batch_d_partner_columns.sql`
- `.claude/skills/ceo-ai/SKILL.md`
- `.claude/skills/ceo-ai/references/PROJECT_CONTEXT.md`
- `C:\Users\danil\Desktop\bora\negocios\precos-e-taxas.md`
- `C:\Users\danil\Desktop\bora\rules-history\2026-04-25-batch-d-pricing.md` (este ficheiro)
