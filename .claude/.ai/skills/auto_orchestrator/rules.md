---
name: auto_orchestrator
description: This skill should be used when the user says "SKILL: auto_orchestrator", or when a multi-step task needs coordinated execution across decision/control/execution layers. Coordinates real Bora skills only — never references skills that don't exist on disk.
version: 2.0.0
---

# AUTO ORCHESTRATOR — RULES

## ROLE
Coordinates real Bora skills (decision/control/execution/validation) into a controlled loop until the task is solved. Never executes directly — always delegates.

---

## OBJECTIVE

Drive a multi-step task through the correct skills in the correct order, with at most 5 cycles, stopping immediately when objective is reached or when a gate blocks.

---

## REGRAS

- ✅ Sempre INVESTIGAR antes de EXECUTAR
- ✅ Sempre passar por `decision_engine` antes de qualquer ação
- ✅ Sempre passar por `guardian` (e `flow_guard`/`refactor_guard` quando aplicável) antes de `executor`
- ✅ Sempre validar com `system_validator` após executar
- ✅ Sempre registrar decisões em `memory`
- ✅ Loop máximo: 5 ciclos
- ❌ NUNCA chamar skills que não existem em `.claude/.ai/skills/`
- ❌ NUNCA executar diretamente (sempre via `executor`)
- ❌ NUNCA pular gates de controle
- ❌ NUNCA fazer mudanças amplas sem validação

---

## FLUXO BASE

```
1. ANALISAR     → decision_engine + decision_registry
2. CONTROLAR    → guardian (+ flow_guard / refactor_guard se aplicável)
3. EXECUTAR     → executor
4. VALIDAR      → system_validator
5. REGISTRAR    → memory
6. REPETIR      → se objetivo não atingido (max 5 ciclos)
```

---

## SKILLS REAIS DISPONÍVEIS

Cérebro: `decision_engine`, `decision_registry`, `memory`, `learning_engine`, `product_analyst`
Controle: `guardian`, `flow_guard`, `refactor_guard`, `state_validator`
Execução: `executor`
Processamento: `system_validator`, `performance_watcher`, `fix_realtime`, `fix_auth`, `dispatch_bugfix`
Especialistas: `dispatch_manager`, `payment_manager`, `token_manager`, `realtime_engine`, `map_master`
Backend: `supabase_agent`, `supabase_engine`
AI: `prompt_engine`

---

## RESPONSABILIDADES

- ✅ Coordenar skills reais em loop controlado (max 5 ciclos)
- ✅ Garantir que toda chain passa por decision_engine → gate → executor → system_validator
- ✅ Reportar estado após cada ciclo

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Coordenação de multi-step task | **auto_orchestrator** (eu) |
| Decisão de risco/impacto | `decision_engine` |
| Checklist técnico | `guardian` |
| Execução de ação aprovada | `executor` |
| Validação pós-exec | `system_validator` |

## NÃO PODE FAZER

- ❌ Referenciar `auto_debug` (não existe)
- ❌ Referenciar `ux_optimizer` (não existe)
- ❌ Referenciar `system_designer` (não existe)
- ❌ Referenciar `tester` (não existe)
- ❌ Referenciar `dispatch_engine_fix` (renomeado para `dispatch_bugfix`)
- ❌ Tomar decisões próprias — só coordena
