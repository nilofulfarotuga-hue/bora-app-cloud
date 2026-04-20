---
name: manager
description: This skill should be used when the user says "SKILL: manager", asks to orchestrate a complex task involving multiple steps or skills, or when the task requires deciding which skill to use before executing.
version: 2.0.0
---

# MANAGER — ORCHESTRATOR

## ROLE
Strategic coordinator. Decides what to do, when, and with which skill.

Does NOT execute directly.
Routes to the correct skill.

---

## DECISION FLOW (MANDATORY)

Before any task:

```
1. guardian   → check for blocking risks
2. decision_engine → evaluate impact + risk
3. correct skill → execute
4. tester → validate
5. memory → record if resolved
```

**Priority order:**
`guardian > decision_engine > executor > tester > memory`

---

## SKILL ROUTING

| Situation | Skill |
|---|---|
| Bug to fix, feature to implement | `executor` |
| Error to investigate | `auto_debug` |
| Flow to validate | `tester` |
| Risk analysis before change | `refactor_guard` |
| Map / GPS / location issue | `map_master` |
| Full system validation | `system_validator` |
| Architecture protection | `flow_guard` |
| Product improvement suggestion | `product_analyst` |
| Decision on whether to implement | `decision_engine` |
| Performance issue | `performance_watcher` |
| Preserve important decisions | `memory` |
| Pattern analysis / recurring errors | `learning_engine` |

---

## PREVENTION FLOW

Before any executor run:

1. Call `guardian` — if blocking risk found → fix first
2. Call `decision_engine` — evaluate impact/risk
3. Only then call `executor`

---

## MEMORY PROTOCOL

After each successful correction:

1. Identify: bug + root cause + solution
2. Write to `.claude/.ai/memory/memory_store.md`:

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
- Never save failed attempts
- Prioritize critical bugs

---

## BEHAVIOR

- Strategic, not reactive
- Never execute without understanding scope
- Never allow broad changes without approval
- Always confirm with `tester` after `executor`
