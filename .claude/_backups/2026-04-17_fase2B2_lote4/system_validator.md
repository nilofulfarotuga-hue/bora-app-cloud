---
name: system_validator
description: This skill should be used when the user says "SKILL: system_validator", asks to validate the full system, verify the complete order flow end-to-end, check tokens and pricing consistency, or confirm everything works after a large change.
version: 1.0.0
---

# SYSTEM VALIDATOR — FULL SYSTEM HEALTH CHECK

## ROLE
Validates the complete bora_app system end-to-end.

Does NOT change code.
Only validates and reports.

---

## OBJECTIVE

Confirm that all major systems are consistent and functional after any significant change.

---

## VALIDATION SCOPE

### 1. ORDER FLOW
- [ ] `created` → dispatch triggers immediately
- [ ] `callingDriver` → exactly 1 driver receives offer
- [ ] Offer timeout → redispatch to next driver
- [ ] `driverAccepted` → client notified
- [ ] `pickedUp` → delivery in progress
- [ ] `delivered` → delivery code validated, tokens awarded
- [ ] Delivery code: 4-digit, validated before status advance

### 2. DISPATCH ENGINE
- [ ] `current_driver_offer_id` set before status change
- [ ] No broadcast to multiple drivers
- [ ] `driver_offer_history` prevents re-offer to same driver
- [ ] `driver_offer_expires_at` timeout works

### 3. TOKENS SYSTEM
- [ ] `bora_tokens` table exists with correct schema
- [ ] `add_tokens()` RPC: awards on delivery, `ON CONFLICT DO NOTHING`
- [ ] `get_user_tokens()` RPC: sums active, non-expired tokens
- [ ] `consume_tokens()` RPC: FIFO order, split remainder, race-condition safe
- [ ] Trigger `trg_award_tokens_on_delivery` fires on `delivered` status
- [ ] Driver balance shows in `DriverHomeScreen` and `ProfileScreen`
- [ ] Checkout: 50% discount limit (TOKEN_MAX_DISCOUNT_RATIO = 0.50), toggle, token deduction after order created

### 4. PRICING
- [ ] Partner restaurant/retail: `deliveryFee` + `platformCommission` (20%)
- [ ] Non-partner: markup baked into subtotal, `purchaseFee` = €2.50
- [ ] Package/logistics: flat base €6 + €0.50/km over 4km
- [ ] Driver earnings: base €3.80 + €0.20/km (+ €0.80 shopping bonus)
- [ ] Apartment surcharge: €1.50 total (€1.00 driver / €0.50 platform)
- [ ] `customerTotal` = subtotal + serviceFee + deliveryFee

### 5. GPS & MAPS
- [ ] Map never opens at Lisbon (GPS-first guard active)
- [ ] Driver map follows position in real time
- [ ] Background tracking active (foreground service on Android)
- [ ] Permission flow handles denied/deniedForever with snackbar

### 6. AUTH
- [ ] `driverId` = `auth.currentUser.id` (UUID, not mocked)
- [ ] Session persists across app restart
- [ ] No guest session in driver flow

### 7. CODE QUALITY
- [ ] `dart analyze` returns 0 errors, 0 warnings
- [ ] No `use_build_context_synchronously` from my changes
- [ ] No `unused_field` / `unused_local_variable` from my changes

---

## OUTPUT FORMAT

```
## SYSTEM VALIDATION REPORT

### ✅ PASSING
- <system>: <reason>

### ❌ FAILING
- <system>: <problem> → <file/line if known>

### ⚠️ WARNINGS
- <system>: <concern>

### VERDICT
SYSTEM HEALTHY ✅ / ISSUES FOUND ❌
```

---

## RESPONSABILIDADES

- ✅ Validar sistema completo pós-execução (order flow, dispatch, tokens, GPS, auth, code quality)
- ✅ Produzir relatório PASSING / FAILING / WARNINGS com localização
- ✅ Ser a última skill chamada em qualquer chain de execução

## NÃO PODE FAZER

- ❌ Corrigir bugs (apenas reporta — delegar a skill especialista)
- ❌ Validar sequência de status do pedido (delegar a `state_validator`)
- ❌ Executar `dart run` ou testes automatizados
- ❌ Modificar `business_rules.md`

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Health check geral pós-execução | **system_validator** (eu) |
| Sequência imutável de status | `state_validator` |
| Análise de performance | `performance_watcher` |
| Bug específico de realtime | `fix_realtime` |
| Bug específico de auth | `fix_auth` |

## RULES

- Apenas valida — nunca corrige
- Sempre a última skill da chain (antes de `memory`)
- Veredicto explícito: SYSTEM HEALTHY ✅ ou ISSUES FOUND ❌
- Source of truth: `.claude/.ai/business_rules.md`
