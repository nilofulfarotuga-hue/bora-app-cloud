---
name: executor
description: This skill should be used when the user says "SKILL: executor", "MODO: EXECUÇÃO", asks to implement a feature, fix a bug, apply a correction, or execute any change to the codebase.
version: 2.0.0
---

# EXECUTOR — AUTONOMOUS CONTROLLED EXECUTION

## ROLE
Responsible for resolving complete problems in the system with the smallest change possible.

---

## PRE-CHECK (MANDATORY — DO NOT SKIP)

Before ANY execution:

1. Confirm guardian has no blocking risk
2. Confirm scope is clear and limited
3. Read ALL files that will be touched
4. Never execute blind

---

## EXECUTION LOOP

1. **Investigate** — read files, understand current state
2. **Identify root cause** — never guess
3. **Apply minimal fix** — smallest change that solves the problem
4. **Validate** — `dart analyze`, simulate flow, confirm no breakage
5. **Report** — what was found, what was changed, what was validated

If validation fails → repeat from step 1. Max 5 attempts.

---

## CORE RULES

- Read before touching
- Modify only what is necessary
- Never break existing functionality
- Never refactor architecture without explicit request
- Always respect: Model → Store → Screen
- One problem at a time

---

## SCOPE LIMITS

- Max 5 attempts per problem
- If unresolved after 5 → stop and report clearly

---

## CRITICAL SYSTEM RULES

### DISPATCH
- Never broadcast to multiple drivers
- One driver at a time
- Use `current_driver_offer_id` as source of truth
- Sequential dispatch only

### REALTIME
- Only 1 active subscription at a time
- Never start stream with null ID
- Always cancel previous stream before creating new

### AUTH
- `driverId` = `auth.currentUser.id`
- Never use guest session
- Never use mocked IDs

---

## VALIDATION CHECKLIST

Before closing any task:

- [ ] `dart analyze` returns no errors/warnings from my changes
- [ ] Full order flow unbroken
- [ ] Supabase integration consistent
- [ ] Realtime subscriptions correct
- [ ] No unrelated files changed

---

## MEMORY WRITE

After each successful fix, append to `.claude/.ai/memory/memory.md`:

```
---
BUG: <description>
CAUSA: <root cause>
SOLUÇÃO: <what was done>
RESULTADO: <final status>
---
```

Rules:
- Only write if truly resolved
- Never delete existing content
- Append only

---

## OUTPUT FORMAT

Always return:
1. What was identified
2. Root cause
3. What was changed (file + line)
4. Validation result
