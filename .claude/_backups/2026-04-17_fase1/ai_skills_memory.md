---
name: memory
description: This skill should be used when the user says "SKILL: memory", asks to save an important decision, record a confirmed pattern, update the operational rules, or preserve knowledge that must persist across sessions.
version: 1.0.0
---

# MEMORY — PERSISTENT KNOWLEDGE STORE

## ROLE
Manages the project's long-term memory.

Reads and writes `.claude/.ai/memory/memory.md`.

---

## WHAT TO STORE

✅ Store:
- Confirmed architectural decisions
- Resolved bugs (root cause + solution)
- Pricing rates and business rules
- Operational patterns and flows
- Technical decisions with reasoning
- Patterns detected by learning_engine

❌ Never store:
- Temporary debug output
- Failed attempts
- Speculative ideas (use product_analyst for that)
- Data that changes frequently (use Supabase)

---

## WRITE PROTOCOL

Before writing, verify:
1. The information is confirmed (not tentative)
2. It belongs to one of the stable categories above
3. It will be useful in a future session

---

## WRITE FORMAT

### For bugs:
```
---
BUG: <description>
CAUSA: <root cause>
SOLUÇÃO: <what was done>
RESULTADO: resolved
---
```

### For decisions:
```
DECISÃO: <what was decided>
RAZÃO: <why>
DATA: <date>
```

### For patterns:
```
PADRÃO: <pattern name>
ONDE: <files/areas>
PREVENÇÃO: <how to avoid>
```

### For operational rules:
```
REGRA: <rule>
ÂMBITO: <when it applies>
```

---

## READ PROTOCOL

When a session starts or a task is complex:
1. Read memory.md to recover context
2. Apply relevant decisions and patterns
3. Do not re-ask questions already answered in memory

---

## RESPONSABILIDADES

- ✅ Escrever em `.claude/.ai/memory/memory.md` (append-only)
- ✅ Armazenar decisões confirmadas, bugs resolvidos, padrões detectados
- ✅ Servir como fonte de contexto persistente entre sessões
- ✅ Ser lido no início de sessões complexas

## NÃO PODE FAZER

- ❌ Deletar ou sobrescrever entradas existentes sem instrução explícita
- ❌ Armazenar tentativas falhadas, output de debug ou dados temporários
- ❌ Armazenar dados que mudam frequentemente (usar Supabase)
- ❌ Interpretar ou tomar decisões baseadas no conteúdo (delegar a `learning_engine`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Persistir decisão confirmada / bug resolvido / padrão | **memory** (eu) |
| Análise de padrões históricos | `learning_engine` |
| Consultar decisões travadas na BR | `decision_registry` |
| Decisões de design de feature | `product_analyst` |

## RULES

- Nunca deletar conteúdo existente — apenas append
- Nunca sobrescrever decisão anterior sem instrução explícita
- Entradas concisas — uma decisão por bloco
- Memory é referência, não log — evitar duplicatas
- Source of truth de regras de negócio: `.claude/.ai/business_rules.md`
