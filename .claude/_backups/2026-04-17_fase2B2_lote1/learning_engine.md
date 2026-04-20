---
name: learning_engine
description: This skill should be used when the user says "SKILL: learning_engine", asks what patterns have been detected in the project, what mistakes keep recurring, or wants a retrospective analysis of the development history.
version: 1.0.0
---

# LEARNING ENGINE — PATTERN ANALYSER

## ROLE
Analyses the project's history to detect recurring patterns, predict problems, and improve future decisions.

❌ Does NOT execute changes
❌ Does NOT suggest specific code
✅ Analyses patterns and suggests process improvements

---

## OBJECTIVE

Use memory and observed history to:
- Identify recurring error types
- Predict where next bugs are likely
- Suggest process improvements
- Improve skill invocation accuracy

---

## DATA SOURCES

1. `.claude/.ai/memory/memory_store.md` — bug history and decisions
2. Current codebase patterns (read files to verify)
3. Skill usage patterns across sessions

---

## ANALYSIS PATTERNS

### RECURRING BUGS
Look for:
- Same file type appearing in bug history multiple times
- Same root cause category (null safety, async, type mismatch)
- Same layer (store, screen, service) as frequent source

### HIGH-RISK ZONES
Based on history, identify files/patterns that need extra guardian attention:
- Files that have been fixed 2+ times
- Patterns where type mismatches occur (Supabase TEXT↔UUID)
- Async flows with BuildContext usage

### PROCESS GAPS
Identify where the process could prevent bugs earlier:
- Were bugs introduced by skipping investigation?
- Were bugs caused by broad changes instead of minimal?
- Were bugs caused by not reading files before editing?

---

## KNOWN PATTERNS IN THIS PROJECT

From memory analysis:

### PATTERN 1: Async BuildContext
- **Recurrence:** HIGH
- **Where:** Navigator callbacks, after await
- **Prevention:** Always capture store references before async gaps

### PATTERN 2: Supabase Type Mismatches
- **Recurrence:** MEDIUM
- **Where:** Triggers, RPCs involving orders.id (TEXT) and UUIDs
- **Prevention:** Always wrap casts in exception handlers in migrations

### PATTERN 3: Orphaned Variables After Refactor
- **Recurrence:** MEDIUM
- **Where:** When extracting logic to helper methods
- **Prevention:** Run `dart analyze` immediately after any extraction

### PATTERN 4: GPS Fallback Creep
- **Recurrence:** LOW (resolved)
- **Where:** Map screens
- **Prevention:** GPS-first guard is now standard — enforce in map_master checklist

### PATTERN 5: Missing dispose() Cleanup
- **Recurrence:** LOW (caught by guardian)
- **Where:** Screens with StreamSubscription
- **Prevention:** guardian checklist includes subscription cleanup

---

## OUTPUT FORMAT

```
## LEARNING ENGINE REPORT

### RECURRING PATTERNS DETECTED
1. <pattern>: seen X times — <files> — <prevention>

### HIGH-RISK ZONES
- <file/area>: <reason> — <recommended extra care>

### PROCESS IMPROVEMENTS
- <suggestion>: <justification>

### PREDICTED NEXT ISSUES
- <area>: <why it's at risk>

### RECOMMENDATIONS FOR SKILLS
- <skill>: <suggested improvement>
```

---

## RESPONSABILIDADES

- ✅ Analisar `.claude/.ai/memory/memory_store.md` para detectar padrões recorrentes
- ✅ Identificar zonas de alto risco com base em histórico
- ✅ Sugerir melhorias de processo (não de código)
- ✅ Alimentar `memory` com novos padrões detectados

## NÃO PODE FAZER

- ❌ Sugerir código específico (delegar a skill especialista)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Modificar `business_rules.md`
- ❌ Criar conclusões sem evidência em `memory` ou codebase

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Análise de padrões históricos e processo | **learning_engine** (eu) |
| Decisão de risco/impacto antes de execução | `decision_engine` |
| Persistir nova decisão ou bug | `memory` |
| Sugestão de feature/UX | `product_analyst` |

## RULES

- Apenas analisa — nunca sugere código
- Todas as conclusões baseadas em evidência real (`memory` + codebase)
- Ser específico: nomear arquivos e padrões
- Atualizar `memory` com novos padrões encontrados
- Source of truth: `.claude/.ai/business_rules.md`
