---
name: auto_orchestrator_flow
description: Defines the canonical execution flow for orchestrated tasks. Uses only real Bora skills.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill define a sequência canónica — nunca executa directamente, nunca modifica ficheiros. Cada chain cita BR §X quando a área está travada.

# AUTO ORCHESTRATOR — FLOW

## ROLE
Defines how a task moves through the orchestration pipeline.

---

## FLUXO

### 1. RECEBER PROBLEMA
Extrair: descrição, área afectada, urgência, escopo esperado.
Se input ambíguo → devolver a `auto_orchestrator/rules.md` com pedido de clarificação.

### 2. CLASSIFICAR
- bug-geral
- bug-realtime
- bug-dispatch
- bug-auth
- regra-dispatch (nova feature, BR §6)
- regra-pagamento (BR §2 · §3 · §8.3)
- regra-tokens (BR §4)
- realtime (mudança de política, BR §22)
- backend (query / migration, BR §21)
- refator (3+ ficheiros)
- arquitetura (Provider, layers, fluxo central)
- performance
- estado/status (BR §1.3 · §1.4)
- gps/mapas (BR §7.2)
- ux/feature (BR §8 cliente · §16 admin)

### 3. SELECIONAR CHAIN
Consultar `auto_orchestrator/decision.md` para a sequência correcta.

### 4. EXECUTAR EM ORDEM
Cada skill da chain é chamada sequencialmente. Se uma bloquear → parar e reportar.

### 5. VALIDAR RESULTADO
`system_validator` confirma cura. Se OK → registar em `memory` e finalizar.

### 6. SE NÃO RESOLVIDO → LOOP
Voltar ao passo 1 com novo contexto. Máximo 5 ciclos (`auto_orchestrator/loop.md`).

---

## EXEMPLOS (resumo rápido)

### Bug realtime
```
bug-realtime → decision_engine → fix_realtime → guardian → executor → system_validator → memory
```

### Implementar fila local 200 m / 5 s (BR §6.2)
```
regra-dispatch → decision_engine → decision_registry → dispatch_manager → guardian → executor → system_validator → memory
```

### Refator de `PaymentStore`
```
refator → decision_engine → refactor_guard → flow_guard → guardian → executor → system_validator → memory
```

### Bug auth (PGRST116)
```
bug-auth → decision_engine → fix_auth → guardian → executor → system_validator → memory
```

---

## EXEMPLOS WORKED

### Exemplo 1: Bug report de dispatch

**Input (contexto real):**
Driver reporta: "oferta não aparece, mesmo com app aberta e GPS on". Sinal concentrado em segundas-feiras (ver learning_engine pattern).

**Processo:**
1. Passo 1 — receber. Descrição: bug operacional em dispatch. Urgência: alta (afecta LTV do driver).
2. Passo 2 — classificar: `bug-dispatch`.
3. Passo 3 — consultar `auto_orchestrator/decision.md` → chain BUG DISPATCH: `decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory`.
4. Passo 4 — executar em ordem. `decision_engine` lê BR §6 (toda). Aprovado com risco 🟡 MÉDIO. `dispatch_bugfix` analisa. `guardian` confirma null safety. `executor` aplica patch. `system_validator` corre smoke test em staging.
5. Passo 5 — se staging OK → `memory` regista. Se não → ciclo 2 com novo contexto.

**Output esperado:**
```
FLOW PLAN: bug-dispatch
CHAIN: decision_engine → dispatch_bugfix → guardian → executor → system_validator → memory
BR REFS: §6 (dispatch), §6.5 (guard anti-duplicação), §25.2 (constantes)
ESTIMATED CYCLES: 1-2
NOTES: se envolver pg_cron colisão segunda 03:00 (padrão detectado), cruzar com BR §3.4
```

**Failure mode:**
Flow falha se pular `dispatch_bugfix` e ir directo a `guardian` — perde o diagnóstico específico de dispatch. Também falha se chain não terminar em `system_validator` + `memory`.

---

### Exemplo 2: Feature "painel admin — cancelar pedido"

**Input (contexto real):**
Danilo: "Preciso de botão no painel admin para cancelar qualquer pedido com motivo obrigatório" (BR §16.2 item 11 e BR §12.5).

**Processo:**
1. Passo 1 — receber. Feature nova, painel admin.
2. Passo 2 — classificar: `ux/feature` + `backend` (nova RPC + RLS) + `estado/status` (cancel → status).
3. Passo 3 — consultar `auto_orchestrator/decision.md` → UX primeiro, depois backend, depois state_validator.
4. Chain: `product_analyst → decision_engine → state_validator → flow_guard → supabase_agent → guardian → executor → system_validator → memory`.
5. `product_analyst` primeiro porque é feature — spec vem antes de código. `state_validator` antes de `flow_guard` porque cancel mexe na FSM (BR §1.3). `flow_guard` porque nova RPC e potencial mudança RLS (BR §21).
6. Estimar: 3 ciclos (spec, migration, UI).

**Output esperado:**
```
FLOW PLAN: ux/feature + backend + estado/status
CHAIN: product_analyst → decision_engine → state_validator → flow_guard → supabase_agent → guardian → executor → system_validator → memory
BR REFS: §16.2 (painel admin), §12.5 (cancel por admin), §1.3 (FSM status), §21 (RLS)
ESTIMATED CYCLES: 3
NOTES: motivo obrigatório deve aparecer ao cliente (BR §12.5 + §22 notificações)
```

**Failure mode:**
Flow falha se começar por `executor` (pula spec), ou se pular `state_validator` (mudança de status sem validação). Também falha se inserir `refactor_guard` sem necessidade (é feature, não refactor).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/skills/auto_orchestrator/decision.md` | Tabela de lookup problema → chain |
| `.claude/.ai/skills/auto_orchestrator/loop.md` | Limites de ciclo e anti-loop |
| `.claude/.ai/business_rules.md` | Source of truth para anotar BR §X em cada chain |
| `.claude/.ai/business_rules.md` §26.2 | Checklist de lançamento — features novas cruzam aqui |
| `.claude/.ai/memory/memory_store.md` | Padrões anteriores de chain usados com sucesso |
| skill `learning_engine` | Consultar antes de classificar se o request vem de padrão recorrente |

**NOTA:** skill apenas lê e recomenda. A chain é executada pelo orquestrador principal.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **iFood** documenta "Standard Operating Procedures (SOPs)" por tipo de task — cada SOP é um runbook step-by-step versionado. Mudar SOP exige RFC.
>
> **Uber** tem "Playbooks" versionados por tipo de incidente (matching, pricing, trust) — cada playbook lista ordem de investigação, equipas a chamar, métricas a observar.
>
> **Glovo** usa "Workflow Library" — colecção de workflows pré-montados, cada um com chain de skills e critério de sucesso.
>
> **Bora App equivalente:** `auto_orchestrator/flow.md` é o playbook canónico por classe de request. Combinação de SOP + Playbook + Workflow Library num único ficheiro markdown. Simples, versionado, consultável.

---

## RESPONSABILIDADES

- ✅ Classificar o problema numa das 15 categorias
- ✅ Seleccionar a chain correcta de `decision.md`
- ✅ Executar skills em ordem, parando em gates bloqueantes
- ✅ Ancorar cada chain em BR §X quando aplicável

## NÃO PODE FAZER

- ❌ Pular um gate de controlo
- ❌ Substituir a chain definida em `decision.md` por improviso
- ❌ Incluir skill que não existe em `.claude/.ai/skills/`
- ❌ Executar directamente sem delegar a `executor`
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Fluxo de execução de task orquestrada | **auto_orchestrator/flow.md** (eu) |
| Mapeamento problema → chain | `auto_orchestrator/decision.md` |
| Limites de ciclo e anti-loop | `auto_orchestrator/loop.md` |
| Regras gerais do orquestrador | `auto_orchestrator/rules.md` |

## RULES

- ❌ Nunca pular um gate
- ❌ Nunca substituir a chain definida em `decision.md`
- ❌ Nunca incluir skill que não existe
- ✅ Sempre logar a chain executada antes de começar
- ✅ Sempre parar quando um gate bloquear
- ✅ Cada chain deve citar BR §X quando aplicável
- Source of truth: `.claude/.ai/business_rules.md` v2
