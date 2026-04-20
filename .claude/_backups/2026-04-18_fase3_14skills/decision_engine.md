---
name: decision_engine
description: This skill should be used when the user says "SKILL: decision_engine", before implementing a complex feature, when evaluating whether to proceed with a change, or when the risk/impact of a task needs to be assessed before execution.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill apenas analisa e recomenda — nunca toca em código, migrations, BR ou outras skills. Qualquer valor numérico citado é sempre referenciado a `business_rules.md` v2 (BR §X).

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

---

## EXEMPLOS WORKED

### Exemplo 1: Reduzir timeout de oferta de 40s → 30s

**Input (contexto real):**
Danilo pergunta: "Vamos baixar o `OFFER_TIMEOUT_SECONDS` de 40s para 30s — acho que os estafetas ficam ociosos à espera de decidir."

**Processo:**
1. Ler BR §6.3 → "40 segundos para o estafeta aceitar ou recusar"
2. Ler BR §25.2 → constante `OFFER_TIMEOUT_SECONDS = 40` em `supabase/functions/dispatch-engine/index.ts`
3. Consultar `decision_registry` → dispatch está travado (SOURCE = BR §6)
4. Dependências mapeadas:
   - Edge Function dispatch-engine v31
   - `DispatchEngine._offerTimeout` em `lib/dispatch/dispatch_engine.dart`
   - UI do diálogo do driver (timer visível em `driver_home_screen.dart`)
5. Impacto: 🔴 ALTO (core dispatch flow, visível ao estafeta)
6. Risco: 🔴 ALTO (pode gerar mais recusas por pressão de tempo → mais ciclos de dispatch → SLA crítico aos 7 min bate mais cedo)

**Output esperado:**
```
## DECISION ANALYSIS: Reduzir OFFER_TIMEOUT_SECONDS 40→30s
Scope: constante dispatch-engine + UI timer + expectativa do driver
Dependencies: Edge Function v31, DispatchEngine, driver_home_screen, pg_cron loop
Impact: 🔴 ALTO — afeta core de dispatch (BR §6.3)
Risk:   🔴 ALTO — pode aumentar recusas e estourar SLA 7 min (BR §9.1)
Recommendation: ⛔ Requires full plan + approval do Danilo
Sequence: (1) A/B paralelo 40s vs 30s em staging → (2) medir taxa de aceitação
         → (3) ajustar BR §6.3 antes de mudar código
Implement: LATER — mudar BR primeiro
```

**Failure mode:**
A skill falha se aprovar sem citar BR §6.3, ou se ignorar a dependência com SLA (BR §9.1).

---

### Exemplo 2: Adicionar nova categoria "barbearia ao domicílio" via `carryGroceries`

**Input (contexto real):**
Danilo pergunta: "E se reutilizar o flow `carryGroceries` para um barbeiro ir a casa do cliente? Carro obrigatório, foto obrigatória — já temos."

**Processo:**
1. Ler BR §1.2 (tipos de serviço) + §10.6 (carryGroceries)
2. Consultar `decision_registry` → `carryGroceries` tem regra "requer carro" (BR §7.6)
3. Reutilizar flow existente parece barato, mas semanticamente errado: pricing em BR §2 assume transporte, não serviço ao domicílio
4. Mapear impacto:
   - `OrderServiceType` enum em `lib/models/order_service_type.dart` — precisa nova categoria
   - `DriverCapacityService` em `lib/dispatch/driver_capacity_service.dart` — regras de batching diferem
   - Pricing em `lib/services/pricing_service.dart` — fórmula barbearia ≠ entrega
5. Impacto: 🟡 MÉDIO (nova categoria, mas modelo existente)
6. Risco: 🟡 MÉDIO (forçar semântica errada cria dívida arquitetural)

**Output esperado:**
```
## DECISION ANALYSIS: Barbearia ao domicílio como alias de carryGroceries
Scope: reutilizar flow existente para serviço diferente
Impact: 🟡 MÉDIO
Risk:   🟡 MÉDIO — mistura "transporte de compras" com "serviço ao cliente"
Recommendation: ⚠️ Refactor antes — criar `homeService` como categoria própria
Sequence: (1) BR adiciona §1.2.homeService → (2) novo enum → (3) pricing rule
Implement: LATER — ver secção 18 (limpeza) como modelo de referência
```

**Failure mode:**
A skill falha se aprovar o atalho sem notar que `carryGroceries` tem pricing baseado em km (BR §2.1) e barbearia tem pricing por serviço prestado (≈ BR §18.3 como modelo).

---

## REFERÊNCIAS BORA APP

A skill consulta os seguintes artefactos antes de recomendar:

| Área | Ficheiro/recurso | Usar para... |
|---|---|---|
| Source of truth de regras | `.claude/.ai/business_rules.md` (todas as 26 secções) | confirmar se decisão está travada |
| Travas numéricas | BR §25.2 — constantes dispatch-engine | citar valores exactos |
| Pricing | `lib/services/pricing_service.dart` | avaliar impacto em taxas/fees |
| Dispatch | `lib/dispatch/dispatch_engine.dart`, `lib/dispatch/driver_capacity_service.dart` | avaliar impacto em atribuição |
| Ordens | `lib/stores/order_store.dart` (método `finalizePurchase`) | avaliar impacto em lifecycle |
| Schema | `supabase/migrations/*.sql` | avaliar impacto em DB/triggers |
| Decisões travadas | skill `decision_registry` | lookup rápido por tópico |
| Histórico | skill `memory` + `.claude/.ai/memory/memory_store.md` | saber se já foi discutido |

**NOTA:** esta skill nunca modifica nenhum destes ficheiros — apenas os lê.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** opera o "Decision Desk" — um comité que avalia toda mudança em engine core (matching, pricing, surge). Nenhuma alteração em dispatch entra em produção sem passar por lá.
>
> **iFood** adopta "RFC (Request For Change)" obrigatório para alterações em dispatch ou pricing — o RFC inclui impacto esperado, plano de rollback e owner.
>
> **Glovo** usa "Pre-mortem reviews" — antes de implementar mudança crítica, equipa lista tudo o que poderia correr mal e como detectar.
>
> **Bora App equivalente:** `decision_engine` (análise estruturada) + `guardian` (validação técnica) + aprovação explícita do Danilo em mudanças de impacto 🔴. Cobre as três camadas com menos overhead que uma equipa dedicada.
