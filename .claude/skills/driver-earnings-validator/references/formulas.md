# Fórmulas do driver_earnings (espelho de pricing_service.dart)

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

