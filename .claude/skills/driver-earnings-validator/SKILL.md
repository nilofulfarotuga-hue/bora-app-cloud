---
name: driver-earnings-validator
description: Valida driver_earnings de um pedido contra fórmula pricing_service. Detecta discrepâncias, identifica root cause (distance errada vs markup errado vs base wrong) e reporta com matemática completa. Útil quando estafeta reclama pagamento ou Danilo suspeita de bug financeiro.
triggers:
  - "validar driver_earnings"
  - "auditar pagamento estafeta"
  - "/driver-earnings-validator"
  - "driver earnings check"
  - "verificar ganhos estafeta"
---

# Driver Earnings Validator

Skill para o Robô B replicar a fórmula `pricing_service.dart` em SQL/Python
e validar `orders.driver_earnings` vs cálculo manual. Single source of truth
para diagnóstico financeiro estafeta.

## Quando invocar

- Estafeta reclama pagamento (carteira não bate)
- Danilo reporta discrepância suspeita (ex: BUG G da sessão 2026-05-11)
- Auditoria periódica antes de payout semanal
- Validação após mudança na fórmula pricing

## Parâmetros

- `order_id` (UUID, obrigatório)
- `tolerance_eur` (float, default 0.02) — diferença aceitável

## Fórmula (single source of truth — replicar pricing_service.dart)

### Constantes

```
PARTNER_DELIVERY_FEE    = 2.50
DRIVER_BASE_PAY         = 3.80
DRIVER_PER_KM_RATE      = 0.20
SHOPPING_DRIVER_BONUS   = 0.80   (só storeShopping/carry/send)
NON_PARTNER_MARKUP_RATE = 0.15
NON_PARTNER_PURCHASE_FEE = 2.50
DRIVER_PROFIT_SHARE_RATE = 0.30  (não-parceiro só)
PACKAGE_BASE_DISTANCE_KM = 4.0
PACKAGE_EXTRA_PER_KM    = 0.50
```

### Cálculo non-partner storeShopping (caso mais comum)

```python
# Inputs from orders row
subtotal = order.subtotal               # já com 15% markup
distance_km = order.distance_km
service_fee = order.service_fee
delivery_fee = order.delivery_fee
apartment = order.apartment_delivery

# Driver fixed pay
shopping_bonus = 0.80 if service_type in ('storeShopping','carryGroceries','sendPackage') else 0
apartment_driver_bonus = 1.00 if apartment else 0
driver_fixed = round_cur(
  DRIVER_BASE_PAY
  + shopping_bonus
  + (DRIVER_PER_KM_RATE * distance_km)
  + apartment_driver_bonus
)

# Bora gross/net
bora_markup = round_cur(subtotal * NON_PARTNER_MARKUP_RATE)
bora_gross  = bora_markup + delivery_fee + service_fee
bora_net    = max(0, bora_gross - driver_fixed)

# Driver share 30%
driver_share = round_cur(bora_net * DRIVER_PROFIT_SHARE_RATE)

# Total driver earnings
expected_driver_earnings = driver_fixed + driver_share

def round_cur(x): return round(x * 100) / 100  # arredondar 2 casas decimais
```

### Cálculo non-partner restaurant

Igual a storeShopping, mas `shopping_bonus = 0` (restaurante não-parceiro
não tem shopping bonus).

### Cálculo partner storeShopping

```python
driver_fixed = round_cur(
  DRIVER_BASE_PAY
  + (DRIVER_PER_KM_RATE * distance_km)
  + apartment_driver_bonus
)
# Partner não tem profit share — só base + km
expected = driver_fixed
```

### Cálculo logistics (carry/send package)

Fórmula diferente — usa `_logisticsDriverBasePay = 4.00` + `_logisticsDriverPerKmRate = 0.50`
+ shopping_bonus = 0.80 + apartment.

## Algoritmo

1. Query order:
   ```sql
   SELECT id, service_type, is_partner_store, subtotal, distance_km,
          delivery_fee, service_fee, apartment_delivery,
          driver_earnings, payment_method
   FROM orders WHERE id = $1;
   ```

2. Determinar branch (non-partner storeShopping / partner / logistics / restaurant)

3. Aplicar fórmula

4. Comparar `expected` vs `db_driver_earnings`:
   - Match (|diff| ≤ tolerance) → ✅ correcto
   - Diff > tolerance → ⚠️ flag + analisar componentes

5. Se diff:
   - Recalcular com `distance_km = 0` para ver base
   - Recalcular com `subtotal = 0` para ver markup contribution
   - Identify qual input pode estar errado

## Output

```
=== Driver Earnings Validation — Order <short_id> ===

📋 Type: <service_type> | Partner: <bool> | Distance: <km>km

💸 Inputs:
  Subtotal:     €<subtotal>
  Delivery:     €<delivery_fee>
  Service:      €<service_fee>
  Apartment:    <bool>

🧮 Calculation:
  Driver fixed:
    Base €3.80
    + Shopping bonus €0.80
    + Per-km (€0.20 × <km>) = €<per_km>
    + Apartment €1.00 (if applicable)
    = €<driver_fixed>

  Bora math:
    Markup (subtotal × 0.15) = €<markup>
    Gross (markup + delivery + service) = €<gross>
    Net (gross - driver_fixed) = €<net>
    Driver share (net × 0.30) = €<share>

  Expected: €<expected>

📊 Comparison:
  Expected: €<expected>
  DB actual: €<db>
  Diff: €<diff>
  Status: ✅ MATCH | ⚠️ DRIFT

🔍 Root cause analysis (if drift):
  - Distance contribution: €<x>
  - Markup contribution: €<y>
  - Fee contribution: €<z>
  - Most likely error: <hypothesis>

💡 Recommendation:
  <action>
```

## Casos validados (registo histórico)

- Pedido `5041075d-50c4-4491-ad2b-df9b884d7410` (2026-05-11):
  distance=4.445km, subtotal=€8.44, fee=€2.50+€2.72
  → expected=€5.79, db=€5.79 ✅ MATCH (BUG G da sessão close-todos =
  FALSO POSITIVO)

## Notas

- Read-only — NÃO modifica DB
- Single source of truth: `pricing_service.dart`. Mudar lá → actualizar
  esta skill em sincronia.
- Para payout semanal (multi-pedidos), invocar para cada pedido + somar
  expected. Comparar com `driver_balances` para detectar drift acumulado.
