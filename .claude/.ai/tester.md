---
name: tester
description: This skill should be used when the user says "SKILL: tester", asks to test the dispatch flow, simulate drivers accepting/rejecting, validate order lifecycle, or verify system behavior without touching production code.
version: 2.0.0
---

# TESTER — SIMULATION & VALIDATION AGENT

## ROLE
Simulate real system behavior and validate correctness.

Does NOT change code.
Only validates logic and flow.

---

## OBJECTIVE

Verify that the system behaves correctly under all expected conditions before declaring a fix complete.

---

## CORE SIMULATION: DISPATCH FLOW

Simulate drivers A, B, C:

```
A receives offer → rejects
B receives offer → rejects
C receives offer → accepts ✔
```

**PASS conditions:**
- Exactly 1 driver receives at a time
- Redispatch triggers immediately after rejection/timeout
- C successfully accepts and order moves to `driverAccepted`
- No driver receives the same order twice

**FAIL conditions:**
- More than 1 driver receives simultaneously → CRITICAL
- No driver receives → CRITICAL
- Loop stops without resolution → CRITICAL
- Order stays in `callingDriver` indefinitely → HIGH

---

## VALIDATION CHECKLIST

### ORDER LIFECYCLE
- [ ] `created` → `callingDriver` (dispatch starts)
- [ ] `callingDriver` → `driverAccepted` (driver accepts)
- [ ] `driverAccepted` → `pickedUp` (pickup confirmed)
- [ ] `pickedUp` → `onTheWay` → `delivered` (delivery complete)
- [ ] Delivery code validated before status advances

### DISPATCH
- [ ] Only 1 `current_driver_offer_id` active at any time
- [ ] Timeout triggers redispatch correctly
- [ ] All drivers in pool are tried before failing

### REALTIME
- [ ] Client receives status update after each transition
- [ ] Driver receives order offer correctly
- [ ] No duplicate events

### TOKENS
- [ ] Driver earns tokens after delivery
- [ ] Token balance updates in real time
- [ ] `consume_tokens` deducts correctly (FIFO)
- [ ] 50% discount limit respected at checkout

### PRICING
- [ ] Partner restaurant: correct commission + delivery fee
- [ ] Non-partner: markup applied, purchase fee correct
- [ ] Package/logistics: flat base + per-km rate
- [ ] Apartment surcharge split correctly

---

## INVESTIGATION BEFORE SIMULATION

1. Read current implementation of the flow being tested
2. Identify what state transitions are expected
3. Simulate step by step
4. Report each step result

---

## OUTPUT FORMAT

```
### TEST: <flow name>
STATUS: PASS ✔ / FAIL ✖

STEPS:
1. <step> → <result>
2. <step> → <result>
...

FAILURES:
- <description of what failed>
- <file / line if known>

RECOMMENDATION:
<what needs fixing>
```
