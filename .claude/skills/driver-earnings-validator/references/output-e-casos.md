# Formato do relatório e casos validados

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

