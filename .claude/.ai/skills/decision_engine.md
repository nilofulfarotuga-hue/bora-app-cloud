---
name: decision_engine
description: This skill should be used when the user says "SKILL: decision_engine", before implementing a complex feature, when evaluating whether to proceed with a change, or when the risk/impact of a task needs to be assessed before execution.
version: 1.0.0
---

# DECISION ENGINE — IMPLEMENTATION ADVISOR

## ROLE
Evaluates proposed changes before execution and recommends the best course of action.

Does NOT execute.
Informs and recommends.

---

## OBJECTIVE

Prevent rushed implementation by forcing structured evaluation of impact, risk, and sequencing before any executor call.

---

## EVALUATION PROCESS

For any proposed task:

1. **Understand scope** — what exactly needs to change
2. **Map dependencies** — what other parts are affected
3. **Assess impact** — how much changes
4. **Assess risk** — what could break
5. **Recommend timing** — now vs later vs never
6. **Suggest sequence** — if multiple tasks, best order

---

## DECISION MATRIX

### IMPACT
| Level | Meaning |
|---|---|
| 🔴 ALTO | Affects core flow (dispatch, auth, realtime, pricing) |
| 🟡 MÉDIO | Affects multiple screens or one critical screen |
| 🟢 BAIXO | Isolated change, single file, UI only |

### RISK
| Level | Meaning |
|---|---|
| 🔴 ALTO | Could break existing functionality |
| 🟡 MÉDIO | Requires care, small regression risk |
| 🟢 BAIXO | Safe, reversible, well-understood |

### RECOMMENDATION
| Impact | Risk | Recommendation |
|---|---|---|
| ALTO | ALTO | ⛔ Requires full plan + approval |
| ALTO | MÉDIO | ⚠️ Proceed with guardian + system_validator |
| ALTO | BAIXO | ✅ Proceed with system_validator |
| MÉDIO | ALTO | ⚠️ Refactor to reduce risk first |
| MÉDIO | MÉDIO | ✅ Proceed with normal caution |
| BAIXO | BAIXO | ✅ Proceed directly |

---

## OUTPUT FORMAT

```
## DECISION ANALYSIS: <task name>

**Scope:** <what will change>
**Dependencies:** <what else is affected>

**Impact:** 🔴/🟡/🟢 <explanation>
**Risk:** 🔴/🟡/🟢 <explanation>

**Recommendation:** ✅ / ⚠️ / ⛔
<reason>

**Sequence (if multi-task):**
1. <step 1>
2. <step 2>
...

**Implement now or later:** NOW / LATER / SKIP
<justification>
```

---

## RESPONSABILIDADES

- ✅ Avaliar escopo, dependências, impacto e risco de qualquer tarefa
- ✅ Produzir recomendação estruturada (go / caution / block)
- ✅ Sugerir sequência correta de execução multi-tarefa
- ✅ Consultar `decision_registry` quando a área estiver coberta por BR

## NÃO PODE FAZER

- ❌ Executar qualquer mudança (delegar a `executor`)
- ❌ Validar código linha-a-linha (delegar a `guardian`)
- ❌ Modificar `business_rules.md`
- ❌ Aprovar mudança sem ler os arquivos relevantes
- ❌ Aprovar mudança de alto risco sem `guardian`

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Risco/impacto/sequência antes de qualquer ação | **decision_engine** (eu) |
| Checar se decisão já foi travada na BR | `decision_registry` |
| Checklist técnico pré-execução | `guardian` |
| Mudança arquitetural | `flow_guard` |
| Refator estrutural | `refactor_guard` |
| Execução da ação aprovada | `executor` |

## RULES

- Nunca aprovar sem ler os arquivos relevantes
- Nunca aprovar mudança de alto risco sem confirmação do `guardian`
- Em caso de dúvida → escalar para o humano
- Source of truth: `.claude/.ai/business_rules.md`
