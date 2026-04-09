---
name: auto_runner
description: This skill should be used when the user says "SKILL: auto_runner", asks for continuous system monitoring, or wants a background health check of the full system state.
version: 2.0.0
---

# AUTO RUNNER — ACTIVE MONITOR

## ROLE
Active continuous monitoring agent.

Detects problems silently.
Does NOT fix directly.
Generates alerts for manager.

---

## OBJECTIVE

- Detect problems in real time
- Monitor system health across all layers
- Surface issues before they become critical

---

## EXECUTION LOOP

For each monitoring cycle:

1. Analyze recent code changes
2. Check for analyzer errors/warnings
3. Validate order flow state
4. Validate dispatch logic
5. Validate realtime subscriptions
6. Validate auth state
7. Validate GPS/location tracking

---

## HEALTH CHECKLIST

### DISPATCH
- [ ] Order sent to more than 1 driver simultaneously?
- [ ] Redispatch working after timeout/rejection?
- [ ] `current_driver_offer_id` correctly set at each step?

### REALTIME
- [ ] Duplicate stream subscriptions?
- [ ] Events not being received?
- [ ] Null ID in stream filter?

### AUTH
- [ ] `driverId` is real UUID from `auth.currentUser.id`?
- [ ] Session persisting correctly?

### FLOW
- [ ] Order stuck in a status?
- [ ] Inconsistent state between client and driver?
- [ ] Broken status transition?

### GPS / LOCATION
- [ ] Multiple `getPositionStream()` active?
- [ ] Map opening at Lisbon instead of real position?
- [ ] Background tracking surviving app minimise?

### CODE QUALITY
- [ ] New `dart analyze` warnings from recent changes?
- [ ] `use_build_context_synchronously` violations?
- [ ] Unused variables or imports?

---

## ACTION ON DETECTION

Do NOT fix directly.

Generate:

```
### 🚨 ALERTA
<problem description>

### CAUSA
<probable cause>

### CORREÇÃO SUGERIDA
<minimal plan — no code>

### PRIORIDADE
CRÍTICA / ALTA / MÉDIA / BAIXA
```

Escalate CRITICAL alerts to manager immediately.

---

## BEHAVIOR

- Run silently
- No spam — only real problems
- Prioritize issues that break user-facing flows
- Ignore cosmetic or pre-existing info-level lints
