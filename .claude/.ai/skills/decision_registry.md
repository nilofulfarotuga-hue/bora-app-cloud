---
name: decision_registry
description: This skill should be used when the user says "SKILL: decision_registry", or before proposing any change that could conflict with a previously locked decision. Quick lookup of "what was already decided and why" — prevents reopening closed discussions.
version: 1.0.0
---

# DECISION REGISTRY — LOCKED DECISIONS LOOKUP

## ROLE
Indexed lookup of every locked decision in the Bora project. Complement to `memory` (which is append-only and chronological) — registry is queryable by topic.

Always consulted BEFORE proposing changes to dispatch, payment, tokens, SLA, or any business rule.

---

## OBJECTIVE

Prevent re-debating already-closed decisions. Every PR or skill action consults the registry to confirm whether the area being touched has a locked rule.

---

## STRUCTURE

Each locked decision has:

```
TOPIC:        <area>
DECISION:     <one-line decision>
LOCKED IN:    <BR version | skill | date>
RATIONALE:    <why this was chosen>
DO NOT:       <what is forbidden>
SOURCE:       <file path or BR section>
```

---

## CURRENT REGISTRY (extraído de business_rules.md)

### DISPATCH
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Modelo | Sequencial, NUNCA broadcast | BR v1 | regra #6 |
| Capacidade | 1 normal, 3 escassez | BR v1 | seção Capacidade |
| Fila local raio | 200m FIXO (não dinâmico no MVP) | BR v1.2 | seção Fila |
| Fila local dwell | ≥5s para entrar | BR v1.2 | seção Fila |
| Ordem na fila | FIFO puro por timestamp, sem ranking | BR v1.1 | regra #7 |
| Prioridade in-store | Driver dentro de não-parceiro tem prioridade total | BR v1 | seção Prioridade |

### SLA
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Base | 10 min do aceite | BR v1 | seção SLA |
| Check | Aos 7 min, server-side, NÃO modal | BR v1.1 | seção SLA |
| Near enough | ≤500m OR ≤2min ETA | BR v1.2 | seção SLA |
| Extensão | Automática, teto +5min | BR v1.2 | seção SLA |
| SLA total max | 15 min | BR v1.2 | seção SLA |

### BATCHING
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Pré-filtro | 15 km (necessário, não suficiente) | BR v1 | seção Batching |
| Janela | 3 min | BR v1 | seção Batching |
| Critério | combinedTime < (indivA + indivB) × 1.20 | BR v1.2 | regra #13 |
| Opostos | NUNCA agrupar | BR v1.1 | seção Batching |

### PAGAMENTO
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Ordem | Cliente paga ANTES do dispatch | BR v1 | regra #14 |
| Pedido adicional driver | +3€ FIXO + 50 tokens FIXOS, km NÃO recalculado | BR v1.1 | seção Driver |
| Markup não-parceiro | +15% embutido no CADASTRO, invisível ao cliente | BR v1.1 | regra #15 |
| Cancel antes dispatch | 1,50€ | BR v1 | seção Cancelamento |
| Cancel após aceite | 50% | BR v1 | seção Cancelamento |
| Cancel após compra | 100% | BR v1 | seção Cancelamento |

### TOKENS
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Ganho driver | 40 por pedido | BR v1 | seção Tokens |
| Cashback cliente | ~3% | BR v1 | seção Tokens |
| Conversão | 100 = 0,50€ (1 = 0,005) | BR v1 | seção Tokens |
| Teto desconto | 50% do TOTAL (incluindo taxas) | BR v1.2 | regra #18 |
| Expiração | 60 dias | BR v1 | seção Tokens |
| Consumo | FIFO obrigatório | BR v1 | regra #18 |
| Excesso aplicado | Corta no teto, NUNCA rejeita | BR v1.2 | seção Tokens |

### DRIVER HELP
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Custo | 4€ FIXO | BR v1 | seção Driver Help |
| Pagador | Estafeta principal | BR v1 | seção Driver Help |
| Intermediação | Plataforma NÃO intermedia (interno) | BR v1 | regra #16 |
| Helper recebe | APENAS 4€ (sem km/comissão/tokens MVP) | BR v1 | seção Driver Help |
| Limite | 1 ajudante (MVP) | BR v1 | seção Driver Help |
| Aplicação | APENAS não-parceiro | BR v1 | seção Driver Help |
| Ativação | ANTES da compra iniciar | BR v1 | seção Driver Help |

### ESTADOS
| Topic | Decision | Locked | Source |
|---|---|---|---|
| Sequência | created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered | BR v1 | regra #5, #8 |
| Mudança | IMUTÁVEL — qualquer transição fora dessa ordem é ilegal | BR v1 | regra #5 |

---

## CONSULTA RÁPIDA (lookup table)

| Quero modificar... | Verifique decisão em |
|---|---|
| Dispatch / fila | seção DISPATCH |
| SLA / tempo de chegada | seção SLA |
| Batching / agrupamento | seção BATCHING |
| Cobrança / refund | seção PAGAMENTO |
| Markup / preço não-parceiro | seção PAGAMENTO (markup invisível) |
| Tokens / cashback | seção TOKENS |
| Driver Help | seção DRIVER HELP |
| Status do pedido | seção ESTADOS |

---

## RESPONSABILIDADES

- ✅ Servir como índice consultável de decisões travadas
- ✅ Apontar para o source (BR section ou skill)
- ✅ Bloquear propostas que contradigam decisão travada (escalando para flow_guard)

## NÃO PODE FAZER

- ❌ Modificar decisões (decisões só mudam por ação explícita do product owner em business_rules.md)
- ❌ Criar decisões novas sem fonte
- ❌ Substituir business_rules.md (é só índice)
- ❌ Tomar decisões por conta própria

---

## ATUALIZAÇÃO

Esta tabela é regenerada quando `business_rules.md` é atualizado. Procedimento:

1. Product owner atualiza `business_rules.md`
2. Bump da versão (v1 → v1.x)
3. Skill `decision_registry` é atualizada para refletir
4. `memory` recebe append do diff

---

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Consultar decisão já travada | **decision_registry** (eu) |
| Avaliar risco de nova mudança | `decision_engine` |
| Bloquear mudança arquitetural | `flow_guard` |
| Atualizar a decisão travada | product owner via `business_rules.md` |

## RULES

- NUNCA contradiz `business_rules.md`
- Em divergência → BR vence, registry é corrigido
- Consulta obrigatória antes de qualquer mudança em área coberta
- Read-only por natureza (só recebe updates via processo formal)
