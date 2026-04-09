---
name: auto_orchestrator_flow
description: Defines the canonical execution flow for orchestrated tasks. Uses only real Bora skills.
version: 2.0.0
---

# AUTO ORCHESTRATOR — FLOW

## ROLE
Defines how a task moves through the orchestration pipeline.

---

## FLUXO

### 1. RECEBER PROBLEMA
Extrair: descrição, área afetada, urgência, escopo esperado.

### 2. CLASSIFICAR
- bug-geral
- bug-realtime
- bug-dispatch
- bug-auth
- regra-dispatch (nova feature)
- regra-pagamento
- regra-tokens
- realtime (mudança de política)
- backend (query/migration)
- refator
- arquitetura
- performance
- estado/status
- gps/mapas
- ux/feature

### 3. SELECIONAR CHAIN
Consultar `auto_orchestrator/decision.md` para a sequência correta.

### 4. EXECUTAR EM ORDEM
Cada skill da chain é chamada sequencialmente. Se uma bloquear → parar e reportar.

### 5. VALIDAR RESULTADO
`system_validator` confirma cura. Se OK → registrar em `memory` e finalizar.

### 6. SE NÃO RESOLVIDO → LOOP
Voltar ao passo 1 com novo contexto. Máximo 5 ciclos (`auto_orchestrator/loop.md`).

---

## EXEMPLOS

### Bug realtime
```
realtime → fix_realtime → guardian → executor → system_validator → memory
```

### Implementar fila local 200m/5s
```
regra-dispatch → decision_registry → dispatch_manager → guardian → executor → system_validator → memory
```

### Refator de PaymentStore
```
refator → refactor_guard → flow_guard → guardian → executor → system_validator → memory
```

### Bug auth (PGRST116)
```
bug-auth → fix_auth → guardian → executor → system_validator → memory
```

---

## RESPONSABILIDADES

- ✅ Classificar o problema em uma das 15 categorias
- ✅ Selecionar a chain correta de `decision.md`
- ✅ Executar skills em ordem, parando em gates bloqueantes

## NÃO PODE FAZER

- ❌ Pular um gate de controle
- ❌ Substituir a chain definida em `decision.md` por improviso
- ❌ Incluir skill que não existe em `.claude/.ai/skills/`
- ❌ Executar diretamente sem delegar a `executor`

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Fluxo de execução de task orquestrada | **auto_orchestrator/flow.md** (eu) |
| Mapeamento problema → chain de skills | `auto_orchestrator/decision.md` |
| Limites de ciclo e anti-loop | `auto_orchestrator/loop.md` |

## RULES

- ❌ Nunca pular um gate
- ❌ Nunca substituir o chain definido em `decision.md`
- ❌ Nunca incluir skill que não existe
- ✅ Sempre logar a chain executada antes de começar
- ✅ Sempre parar quando um gate bloquear
