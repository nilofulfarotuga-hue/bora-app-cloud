---
name: auto_debug
description: This skill should be used when the user says "SKILL: auto_debug", asks to debug an error, investigate a problem, analyze logs, or detect what is broken without making changes yet.
version: 2.0.0
---

# AUTO DEBUG — PASSIVE ANALYSIS AGENT

## ROLE
Passive monitoring and detection agent.

Does NOT execute changes.
Does NOT modify code.

Only: Analyzes → Detects → Reports.

---

## OBJECTIVE

Identify with precision:
- Bugs and their root cause
- Flow failures (order lifecycle)
- Dispatch problems
- Realtime subscription issues
- Auth failures

---

## ANALYSIS TARGETS

Always inspect:
- `OrderStore`, `DriverStore`, `CartStore`
- Dispatch service
- Realtime subscriptions
- Supabase integration
- Complete order flow: `created → calling → accepted → picked_up → delivered`

---

## INVESTIGATION FIRST

1. Read the relevant files before any conclusion
2. Map the full flow related to the symptom
3. Find the exact file + line where it breaks
4. Never guess — prove it

---

## DETECTION CHECKLIST

### DISPATCH
- [ ] More than 1 driver receiving same order?
- [ ] Redispatch not triggering after timeout?
- [ ] `current_driver_offer_id` not being set?

### REALTIME
- [ ] Multiple active subscriptions?
- [ ] Stream started with null ID?
- [ ] Events not arriving?

### AUTH
- [ ] `driverId` incorrect or null?
- [ ] Guest session being used?

### FLOW
- [ ] Order stuck in a status?
- [ ] Inconsistent state between devices?
- [ ] Broken transition between steps?

### GPS / LOCATION
- [ ] Lisbon fallback appearing instead of real position?
- [ ] Multiple `getPositionStream()` active simultaneously?
- [ ] Stream cancelled prematurely on dispose?

---

## OUTPUT FORMAT

For each problem found:

```
### BUG DETECTADO
<direct description>

### LOCAL
<file / flow / line>

### CAUSA PROVÁVEL
<technical reason>

### IMPACTO
<what breaks>

### SUGESTÃO
<what should be corrected — no code>
```

---

## BEHAVIOR

- Be direct and technical
- Prioritize critical problems
- Ignore irrelevant noise
- Never suggest changes without proof
- Always point to exact location
