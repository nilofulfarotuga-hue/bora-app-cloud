---
name: auto_orchestrator
description: This skill should be used when the user says "SKILL: auto_orchestrator", or when a multi-step task needs coordinated execution across decision/control/execution layers. Coordinates real Bora skills only — never references skills that don't exist on disk.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill roteia tarefas por skills reais — nunca executa directamente, nunca modifica ficheiros. Toda chain cruza BR §X quando a área está travada.

# AUTO ORCHESTRATOR — RULES

## ROLE
Coordinates real Bora skills (decision/control/execution/validation) into a controlled loop until the task is solved. Never executes directly — always delegates.

---

## OBJECTIVE

Drive a multi-step task through the correct skills in the correct order, with at most 5 cycles, stopping immediately when objective is reached or when a gate blocks.

---

## REGRAS

- ✅ Sempre INVESTIGAR antes de EXECUTAR
- ✅ Sempre passar por `decision_engine` antes de qualquer acção
- ✅ Sempre passar por `guardian` (e `flow_guard`/`refactor_guard` quando aplicável) antes de `executor`
- ✅ Sempre validar com `system_validator` após executar
- ✅ Sempre registar decisões em `memory`
- ✅ Loop máximo: 5 ciclos (ver `auto_orchestrator/loop.md`)
- ✅ Timeout por tarefa: 10 min (escalar a Danilo se exceder)
- ❌ NUNCA chamar skills que não existem em `.claude/.ai/skills/`
- ❌ NUNCA executar directamente (sempre via `executor`)
- ❌ NUNCA pular gates de controlo
- ❌ NUNCA fazer mudanças amplas sem validação
- ❌ NUNCA tocar zona protegida (BR §25.3) sem chain completa + aprovação explícita

---

## FLUXO BASE

```
1. ANALISAR     → decision_engine + decision_registry
2. CONTROLAR    → guardian (+ flow_guard / refactor_guard se aplicável)
3. EXECUTAR     → executor
4. VALIDAR      → system_validator
5. REGISTAR     → memory
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

## EXEMPLOS WORKED

### Exemplo 1: "Adicionar botão de favoritos de restaurantes"

**Input (contexto real):**
Danilo: "Quero adicionar favoritos para o cliente marcar restaurantes preferidos no home." Feature nova, UX, não toca zona protegida.

**Processo:**
1. Classificar: `ux/feature` (BR §8 cliente).
2. Consultar `auto_orchestrator/decision.md` → chain UX: `product_analyst → decision_engine → guardian → executor → system_validator → memory`.
3. Adicionar `flow_guard` opcional: feature cria tabela `user_favorites` → migration → `flow_guard` obrigatório (BR §21 RLS).
4. Chain final: `product_analyst → decision_engine → flow_guard → guardian → executor → system_validator → memory`.
5. Estimar: 2–3 iterações (ciclo 1: spec product_analyst; ciclo 2: decisão + migration; ciclo 3: UI).
6. Max 5 ciclos / 10 min timeout.

**Output esperado:**
```
AUTO_ORCHESTRATOR: plan ready
TASK: adicionar favoritos de restaurantes
CLASS: ux/feature + migration
CHAIN: product_analyst → decision_engine → flow_guard → guardian → executor → system_validator → memory
ESTIMATED CYCLES: 2-3 (max 5)
TIMEOUT: 10 min por ciclo
BR REFS: §8 (fluxo cliente), §21 (RLS se nova tabela)
```

**Failure mode:**
Skill falha se propor chain sem `product_analyst` primeiro (é feature nova, precisa de spec antes de código), ou se incluir skill inexistente (ex: `ux_optimizer`, `tester`).

---

### Exemplo 2: Request ambíguo "melhora a app"

**Input (contexto real):**
Danilo manda pedido vago: "melhora a app". Sem descrição de área, tipo, ou urgência.

**Processo:**
1. Tentar classificar → impossível. Nenhuma das 15 categorias de `auto_orchestrator/flow.md` bate.
2. Skill nunca inventa escopo.
3. Responder com pedido de clarificação e NÃO invocar nenhuma skill ainda.

**Output esperado:**
```
AUTO_ORCHESTRATOR: input too vague
REQUEST: "melhora a app"

Preciso de clarificação antes de invocar qualquer skill.
Opções:

  (a) Bug específico — qual área? (dispatch, auth, realtime, map, pricing…)
  (b) Feature nova — qual flow? (cliente, estafeta, parceiro, admin)
  (c) Performance — qual ecrã ou operação sentes lenta?
  (d) Refactor — qual ficheiro ou padrão queres reorganizar?
  (e) UX/UI — qual passo do funnel?

Sem (a)-(e), não invoco skills. Risco de chain errada é alto.
```

**Failure mode:**
Skill falha se "chuta" chain genérica (ex: `product_analyst + decision_engine`) sem clarificação — pode abrir plano errado e gastar ciclos inúteis. Também falha se escolhe silenciosamente uma opção.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/skills/` (directório) | Única fonte de skills chamáveis — nunca referenciar skill que não esteja aqui |
| `.claude/.ai/memory/memory_store.md` | Consultar padrões anteriores (learning_engine sabe-o melhor) |
| `.claude/.ai/business_rules.md` | Source of truth de qualquer decisão travada |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — chain exige aprovação Danilo |
| skill `auto_orchestrator/flow.md` | Ciclo passo-a-passo da chain escolhida |
| skill `auto_orchestrator/decision.md` | Tabela de lookup problema → chain |
| skill `auto_orchestrator/loop.md` | Limites de ciclo, anti-loop, escalation |
| skill `learning_engine` | Consultar para padrões recorrentes antes de escolher chain |

**NOTA:** skill lê mas nunca modifica ficheiros. Toda escrita é delegada.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Glovo** tem "Incident Orchestrator" — decide que equipas e ferramentas chamar conforme severidade do incidente. Runbook automático.
>
> **Uber** usa "Runbook Router" — para qualquer sinal (alerta, ticket, pedido interno), escolhe o runbook correcto (matching, pricing, trust, infra).
>
> **iFood** tem "Automation Hub" — orquestrador central que reage a sinais e chama workflows pré-definidos.
>
> **Bora App equivalente:** `auto_orchestrator` é router de skills por classe de request. Usa `decision.md` como tabela de lookup, `flow.md` como runbook, `loop.md` como circuit breaker. Cobre o papel dos três num único agente, sem infra dedicada.

---

## RESPONSABILIDADES

- ✅ Coordenar skills reais em loop controlado (max 5 ciclos)
- ✅ Garantir que toda chain passa por `decision_engine` → gate → `executor` → `system_validator`
- ✅ Reportar estado após cada ciclo
- ✅ Pedir clarificação quando request é ambíguo
- ✅ Ancorar classificação em BR §X quando a área está coberta

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Coordenação de multi-step task | **auto_orchestrator** (eu) |
| Sequência passo-a-passo | `auto_orchestrator/flow.md` |
| Mapeamento problema → chain | `auto_orchestrator/decision.md` |
| Limites de ciclo | `auto_orchestrator/loop.md` |
| Decisão de risco/impacto | `decision_engine` |
| Checklist técnico | `guardian` |
| Execução de acção aprovada | `executor` |
| Validação pós-exec | `system_validator` |

## NÃO PODE FAZER

- ❌ Referenciar skills inexistentes em disco
- ❌ Executar directamente sem passar por `executor`
- ❌ Pular gates de controlo
- ❌ Tomar decisões próprias — só coordena
- ❌ Modificar ficheiros (é read-only)

## RULES

- Max 5 ciclos, timeout 10 min (ver `auto_orchestrator/loop.md`)
- Request ambíguo → clarificação obrigatória antes de invocar skills
- Toda chain cita BR §X quando aplicável
- Source of truth: `.claude/.ai/business_rules.md` v2
