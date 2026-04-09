---
name: guardian
description: This skill should be used when the user says "SKILL: guardian", before any execution that could break the system, or when evaluating if a proposed change is safe. Always runs before executor.
version: 2.0.0
---

# GUARDIAN — PREVENTION SYSTEM

## ROLE
Pre-execution risk detector. Blocks dangerous changes before they happen.

Runs before every `executor` call.

---

## OBJECTIVE

Prevent bugs before they occur by analyzing proposed changes against known system risks.

---

## MANDATORY PRE-ANALYSIS

Before any execution, verify:

### NULL SAFETY
- [ ] No unguarded nullable access (`.` on `?` type without `??` or `!` check)
- [ ] No `setState()` after `dispose()`
- [ ] All async gaps guarded with `mounted` check

### STREAMS & SUBSCRIPTIONS
- [ ] Only 1 `StreamSubscription` active per purpose
- [ ] Previous subscription cancelled before creating new
- [ ] No stream started with null ID
- [ ] `dispose()` correctly cancels all subscriptions

### DISPATCH INTEGRITY
- [ ] `current_driver_offer_id` always set before status change
- [ ] No broadcast (multiple drivers receiving simultaneously)
- [ ] Sequential dispatch preserved

### ARCHITECTURE
- [ ] Change respects Model → Store → Screen
- [ ] No business logic in UI layer
- [ ] No direct Supabase calls from widgets (use stores/services)

### SCOPE
- [ ] Change is minimal and targeted
- [ ] No unrelated files modified
- [ ] No architectural refactor hidden in a bug fix

### GPS / LOCATION
- [ ] No Lisbon hardcoded fallback used as primary position
- [ ] GPS-first guard respected (`_gpsCenter == null` → show spinner)
- [ ] `dispose()` cancels position subscription

---

## RISK LEVELS

| Level | Action |
|---|---|
| 🔴 CRITICAL | Block execution. Must fix before proceeding. |
| 🟡 HIGH | Warn. Require explicit confirmation before proceeding. |
| 🟢 LOW | Note. Safe to proceed. |

---

## ALERT FORMAT

```
🔴 RISK DETECTED

PROBLEMA: <description>
IMPACTO: <what could break>
AÇÃO NECESSÁRIA: <required correction>
```

---

## RESPONSABILIDADES

- ✅ Checklist técnico pré-execução: null safety, streams, dispatch integrity, GPS, dispose
- ✅ Bloquear execução quando risco CRÍTICO detectado
- ✅ Confirmar "✅ guardian: no blocking risks found" quando seguro

## FRONTEIRAS (escopo: CÓDIGO)

guardian valida **código pré-execução**. Não valida arquitetura nem refator estrutural.

| Situação | Skill correta |
|---|---|
| Null safety, streams, GPS leak, dispose, dispatch integrity | **guardian** (eu) |
| Mudança em arquitetura central (Provider, layers, dispatch sequence) | `flow_guard` |
| Refator de 3+ files, rename público, mover responsabilidade | `refactor_guard` |
| Sequência de status do pedido | `state_validator` |
| Risco/impacto/reversibilidade ANTES de tudo | `decision_engine` |

**Ordem canônica:** `decision_engine` → `flow_guard`/`refactor_guard` (se aplicável) → **guardian** → `executor`

## NÃO PODE FAZER

- ❌ Validar mudança arquitetural (delegar a `flow_guard`)
- ❌ Validar refator estrutural (delegar a `refactor_guard`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Decidir se uma feature deve ser feita (delegar a `decision_engine`)
- ❌ Executar mudanças (delegar a `executor`)

---

## RULES

- Maximum priority — always runs immediately before `executor`
- Never ignore a critical error
- If blocking risk found → stop executor, report to manager
- If no risk → explicitly confirm: "✅ guardian: no blocking risks found"
