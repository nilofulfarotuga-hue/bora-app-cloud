---
name: auto_orchestrator_decision
description: Mapping table of problem types to the correct sequence of real Bora skills. Use this to pick which skills to invoke for a given task.
version: 2.0.0
---

# AUTO ORCHESTRATOR — DECISION TABLE

## ROLE
Maps problem types to the canonical skill chain. Only references skills that exist on disk.

---

## REGRAS

- Basear decisão no tipo de problema
- Evitar skills desnecessárias
- Sempre passar por `decision_engine` primeiro
- Sempre terminar com `system_validator` + `memory`

---

## MAPEAMENTO

### BUG (geral, não-realtime)
```
decision_engine → guardian → executor → system_validator → memory
```

### BUG REALTIME / SYNC
```
decision_engine → fix_realtime → guardian → executor → system_validator → memory
```

### BUG DISPATCH (incidente pontual)
```
decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory
```

### BUG AUTH
```
decision_engine → fix_auth → guardian → executor → system_validator → memory
```

### IMPLEMENTAR REGRA DE DISPATCH (fila, capacidade, SLA, batching)
```
decision_engine → decision_registry → dispatch_manager → guardian → executor → system_validator → memory
```

### IMPLEMENTAR REGRA DE PAGAMENTO (cobrança, refund, fees, markup)
```
decision_engine → decision_registry → payment_manager → guardian → flow_guard → executor → system_validator → memory
```

### IMPLEMENTAR REGRA DE TOKENS (FIFO, expiração, cashback)
```
decision_engine → decision_registry → token_manager → guardian → executor → system_validator → memory
```

### REALTIME (mudança em sync, channels, streams)
```
decision_engine → realtime_engine → flow_guard → guardian → executor → system_validator → memory
```

### BACKEND (queries, migrations, RPCs)
```
decision_engine → supabase_agent → supabase_engine → guardian → executor → system_validator → memory
```

### REFATOR (3+ files, rename, restructure)
```
decision_engine → refactor_guard → flow_guard → guardian → executor → system_validator → memory
```

### MUDANÇA ARQUITETURAL (Provider, layers, fluxo central)
```
decision_engine → flow_guard → refactor_guard → guardian → executor → system_validator → memory
```

### PERFORMANCE (rebuilds, GPS waste, leaks)
```
decision_engine → performance_watcher → guardian → executor → system_validator → memory
```

### MUDANÇA DE STATUS / ESTADO DO PEDIDO
```
decision_engine → state_validator → guardian → executor → system_validator → memory
```

### GPS / MAPAS / TRACKING
```
decision_engine → map_master → guardian → executor → system_validator → memory
```

### UX / FEATURE
```
product_analyst → decision_engine → guardian → executor → system_validator → memory
```

---

## RESPONSABILIDADES

- ✅ Mapear tipo de problema → chain de skills correta
- ✅ Garantir que chains usem apenas skills reais
- ✅ Ser a tabela de lookup central para `auto_orchestrator/flow.md`

## NÃO PODE FAZER

- ❌ Incluir skills inexistentes em chains
- ❌ Montar chains sem `guardian` antes de `executor`
- ❌ Montar chains sem `system_validator` + `memory` no final
- ❌ Tomar decisões de risco (delegar a `decision_engine`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Tabela de mapeamento problema → chain | **auto_orchestrator/decision.md** (eu) |
| Fluxo de execução passo-a-passo | `auto_orchestrator/flow.md` |
| Limites de ciclo | `auto_orchestrator/loop.md` |
| Decisão de risco/impacto | `decision_engine` |

## RULES

- ❌ NÃO incluir `auto_debug`, `ux_optimizer`, `system_designer`, `tester` (não existem)
- ❌ NÃO usar `dispatch_engine_fix` (renomeado para `dispatch_bugfix`)
- ✅ Toda chain começa com `decision_engine` (exceto UX que começa com `product_analyst`)
- ✅ Toda chain termina com `system_validator` + `memory`
- ✅ Toda chain inclui `guardian` antes de `executor`
