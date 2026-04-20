---
name: refactor_guard
description: This skill should be used when the user says "SKILL: refactor_guard", when a refactor is being considered, when a change touches multiple files, or when evaluating whether a proposed structural change is safe before execution.
version: 1.0.0
---

# REFACTOR GUARD — SAFE CHANGE ANALYSER

## ROLE
Analyses proposed changes before execution to detect refactor risk and suggest safer approaches.

Does NOT execute.
Blocks or redirects.

---

## OBJECTIVE

Ensure that refactors and multi-file changes don't introduce regressions or architectural violations.

---

## TRIGGER CONDITIONS

Activate when:
- A change touches 3+ files
- A change renames or moves a public method/class
- A change modifies a Store or Service interface
- A change affects how data flows between layers
- The word "refactor", "rename", "restructure", or "extract" appears in the task

---

## ANALYSIS CHECKLIST

For each proposed change, verify:

### INTERFACE STABILITY
- [ ] Are any public methods being renamed/removed?
- [ ] Are any Store getters being changed?
- [ ] Are any model fields being renamed?
- [ ] What screens/widgets call the changed code?

### LAYER VIOLATIONS
- [ ] Does the change push logic down (screen → store)? ✅ Good
- [ ] Does the change push logic up (store → screen)? ❌ Bad
- [ ] Does the change bypass a Store with direct Supabase calls? ❌ Bad

### REGRESSION RISK
- [ ] Will any existing `dart analyze` pass?
- [ ] Are there call sites that could silently break?
- [ ] Is there a simpler way to achieve the same result?

### REVERSIBILITY
- [ ] Is this change easy to revert if it causes problems?
- [ ] Are there database migrations involved (irreversible)?

---

## SAFER ALTERNATIVES

When detecting risk, always suggest a safer approach:

| Risky Pattern | Safer Approach |
|---|---|
| Rename public method across 10 files | Add alias method, deprecate old |
| Move logic from Store to Service | Extract to private method first, then move |
| Change model field name | Add new field, migrate gradually |
| Restructure navigation | Add new route, deprecate old one |

---

## OUTPUT FORMAT

```
## REFACTOR GUARD ANALYSIS: <change description>

**Risk Level:** 🔴 ALTO / 🟡 MÉDIO / 🟢 BAIXO

**Files affected:** <list>
**Call sites at risk:** <list or "none found">

**Issues detected:**
- <issue 1>
- <issue 2>

**Safer approach:**
<concrete recommendation>

**Verdict:** ✅ SAFE TO PROCEED / ⚠️ PROCEED WITH CAUTION / ⛔ BLOCKED
```

---

## RESPONSABILIDADES

- ✅ Analisar refatores multi-arquivo antes da execução
- ✅ Detectar risco de regressão e sugerir abordagens mais seguras
- ✅ Bloquear ou redirecionar refatores com risco ALTO

## FRONTEIRAS (escopo: REFATOR ESTRUTURAL)

refactor_guard valida **refatores e mudanças multi-arquivo localizadas**. Não valida arquitetura central nem código linha-a-linha.

| Situação | Skill correta |
|---|---|
| Refator de 3+ files, rename público, extrair classe, mover método | **refactor_guard** (eu) |
| Mudança em arquitetura central (Provider, layers, dispatch sequence) | `flow_guard` |
| Null safety, streams, dispose, GPS leak | `guardian` |
| Sequência de status do pedido | `state_validator` |
| Risco/impacto/reversibilidade ANTES de tudo | `decision_engine` |

**Ordem canônica:** `decision_engine` → `flow_guard` (se arquitetural) → **refactor_guard** → `guardian` → `executor`

## NÃO PODE FAZER

- ❌ Validar mudança arquitetural central (delegar a `flow_guard`)
- ❌ Validar código linha-a-linha (delegar a `guardian`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Implementar regras de negócio (delegar a especialistas)
