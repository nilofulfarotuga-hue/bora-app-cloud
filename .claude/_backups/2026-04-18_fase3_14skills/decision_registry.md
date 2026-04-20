---
name: decision_registry
description: This skill should be used when the user says "SKILL: decision_registry", or before proposing any change that could conflict with a previously locked decision. Quick lookup of "what was already decided and why" — prevents reopening closed discussions.
version: 1.2.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. A tabela abaixo é espelho indexado de `business_rules.md` v2. Em divergência, **BR v2 vence sempre** — esta skill só aponta para a BR, nunca decide.

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

## CURRENT REGISTRY (espelho de business_rules.md v2 — 2026-04-17)

### DISPATCH
| Topic | Decision | Source |
|---|---|---|
| Motor | Edge Function `dispatch-engine` v31 + pg_cron (1min) | BR §6.1 · §25.2 |
| Ordem de seleção | (1) SLA crítico · (2) não-parceiro · (3) FIFO geográfico 200m · (4) ≤10km · (5) `priority_until` | BR §6.2 |
| Raio FIFO | **200 m** (`FIFO_RADIUS_KM = 0.2`) — fixo | BR §6.2 · §25.2 |
| Timeout oferta | **40 s** (`OFFER_TIMEOUT_SECONDS = 40`) | BR §6.3 · §25.2 |
| Stacking máximo | **3 pedidos** simultâneos (`MAX_ORDERS_PER_DRIVER = 3`) | BR §6.4 · §25.2 |
| Batching raio | **≤ 3 km entre lojas** (`BATCHING_RADIUS_KM = 3.0`) | BR §6.4 · §25.2 |
| Diálogo | 1 de cada vez — segundo pedido descartado | BR §7.1 |
| Guard anti-duplicação | `findNextDriver` exclui drivers com oferta activa; `assignDriver` lock optimista | BR §6.5 |
| Rota multi-stop | TODOS pickups primeiro, depois TODOS dropoffs | BR §6.6 |

### SLA
| Topic | Decision | Source |
|---|---|---|
| Base | **10 min** desde o pedido até dispatch confirmado (`SLA_BASE_MINUTES = 10`) | BR §9.1 · §25.2 |
| Alerta crítico | **7 min** sobe prioridade (`SLA_CHECK_MINUTES = 7`) | BR §9.1 · §25.2 |
| Raio preferido | **10 km** (`PREFERRED_RADIUS_KM = 10`) | BR §25.2 |

### BATCHING (STACKING)
| Topic | Decision | Source |
|---|---|---|
| Máximo | 3 pedidos por driver | BR §6.4 |
| Critério de junção | ≤ 3 km entre lojas | BR §6.4 |
| Opostos | Nunca empilhar 2 diálogos em simultâneo | BR §7.1 |

### PAGAMENTO
| Topic | Decision | Source |
|---|---|---|
| Métodos | Cartão (Stripe), MBWay, Dinheiro | BR §3.1 |
| Limite dinheiro | **€40** por pedido (Flutter + trigger DB) | BR §3.2 |
| Buffer Stripe não-parceiro | +15% pré-autorização, libertado após compra | BR §3.3 |
| Markup parceiro | 10% comissão + 5% invisível + 5% serviço | BR §2.4 |
| Markup não-parceiro | **+15% invisível** sobre o preço | BR §2.4 |
| Taxa entrega | €2,50 até 4 km; +€0,50/km acima | BR §2.1 |
| Surcharge apartamento | +€1,50 (€1 estafeta · €0,50 Bora) | BR §2.3 |
| Saco restaurante | €0,30 fixo, automático | BR §2.5 |
| Saco mercado | €0,10/saco, contados pelo estafeta | BR §2.5 |
| Cancel antes aceitar | **€1,00** | BR §8.3 |
| Cancel a caminho | **€2,50** (taxa entrega) | BR §8.3 |
| Cancel após recolha | **100%** do pedido | BR §8.3 |
| Payout semanal | Segunda 3h · mínimo €10 · `bora_weekly_auto_payout` | BR §3.4 · §5.3 |

### TOKENS
| Topic | Decision | Source |
|---|---|---|
| Ganho driver | +40 tokens por entrega | BR §4.2 |
| Ganho driver stacking | +50 tokens por entrega adicional | BR §4.2 |
| Cashback cliente | 3% do valor do pedido em tokens | BR §4.2 |
| Conversão | **100 tokens = €0,50** | BR §4.1 |
| Expiração | **60 dias** | BR §4.1 |
| Consumo | **FIFO** (primeiros a entrar, primeiros a sair) | BR §4.1 |
| Teto desconto cliente | **até 50%** do valor do pedido | BR §4.3 |
| Prioridade driver (tokens) | 50→5min · 90→10min · 125→15min · 400→1h | BR §4.3 |
| Tabela/trigger | `bora_tokens` + `trg_award_tokens_on_delivery` | BR §4.4 |
| Gorjeta | Valores 1/2/3/5€ + livre · divisão 80% driver / 20% Bora | BR §4.5 |

### DRIVER HELP
| Topic | Decision | Source |
|---|---|---|
| Custo | **€4 fixos** para o ajudante | BR §5.2 |
| Pagador | Estafeta principal (não é custo Bora) | BR §5.2 |
| Aplicação | Apenas mercados e restaurantes **não-parceiros** | BR §5.2 |
| Seleção | Dispatch normal (40 s para aceitar) | BR §5.2 |

### REMUNERAÇÃO DO ESTAFETA
| Topic | Decision | Source |
|---|---|---|
| Base | €3,80 | BR §5.1 |
| Distância | +€0,20/km | BR §5.1 |
| Taxa entrega | +€0,80 | BR §5.1 |
| Parceiro | +€3,00 adicional | BR §5.1 |
| Pagamento | Semanal, segunda 3h, mínimo €10 | BR §5.3 |

### RESERVA DE MESA
| Topic | Decision | Source |
|---|---|---|
| Pré-pagamento | **€3** (anti no-show) | BR §14.5 |
| Slots | 30 minutos | BR §14.4 |
| Cancelamento ≥4h antes | Reembolso total | BR §14.5 |
| Cancelamento <4h / no-show | Cliente perde €3 (€1 Bora + €2 restaurante) | BR §14.5 |
| Rejeitada pelo restaurante | Reembolso total automático | BR §14.5 |
| Lembretes | 24h + 2h (cliente) · 30min (restaurante) | BR §14.6 |

### MARKETPLACE (FUTURO)
| Topic | Decision | Source |
|---|---|---|
| Estado | Planeado, não desenvolvido | BR §17.1 |
| Entrega | CTT/DPD — não usa estafetas Bora | BR §17.3 |
| Markup escalonado | ≤10€ +40% · 10–50 +30% · 50–150 +30% · >150 +20% | BR §17.5 |
| Devoluções | Cliente resolve com fornecedor · Bora intermediária | BR §17.6 |

### LIMPEZA DE CASAS (FUTURO)
| Topic | Decision | Source |
|---|---|---|
| Estado | Planeado, pós-delivery consolidado | BR §18.1 |
| Divisão | 85% empregada · 15% Bora | BR §18.4 |
| Produtos | Sem (grátis) ou com (+€10) | BR §18.5 |

### ESTADOS DO PEDIDO (DELIVERY)
| Topic | Decision | Source |
|---|---|---|
| Sequência | `created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered` | BR §1.3 |
| Mudança | **IMUTÁVEL** — transição fora da ordem é ilegal | BR §1.3 |

### ESTADOS DA RESERVA
| Topic | Decision | Source |
|---|---|---|
| Sequência | `reservation_requested → restaurant_responding → (accepted\|suggested_alternative\|rejected) → confirmed → customer_arrived → completed\|no_show` | BR §1.4 · §14.8 |

### ZONAS PROTEGIDAS (NÃO TOCAR SEM APROVAÇÃO)
| Ficheiro/recurso | Source |
|---|---|
| `lib/services/pricing_service.dart` | BR §25.3 |
| `lib/dispatch/driver_capacity_service.dart` | BR §25.3 |
| `lib/stores/order_store.dart` método `finalizePurchase` | BR §25.3 |
| Triggers `bora_tokens` e `trg_award_tokens_on_delivery` | BR §25.3 |
| Qualquer código de pagamento Stripe | BR §25.3 |
| `supabase/functions/dispatch-engine/index.ts` | BR §25.2 |

---

## CONSULTA RÁPIDA (lookup table)

| Quero modificar... | Verifique secção |
|---|---|
| Dispatch / fila / timeouts | DISPATCH · BR §6 |
| SLA / tempo de chegada | SLA · BR §9 |
| Stacking / batching | BATCHING · BR §6.4 |
| Cobrança / refund / cancelamento | PAGAMENTO · BR §3 · §8.3 |
| Markup / preço não-parceiro | PAGAMENTO · BR §2.4 |
| Tokens / cashback | TOKENS · BR §4 |
| Driver Help | DRIVER HELP · BR §5.2 |
| Status do pedido | ESTADOS DO PEDIDO · BR §1.3 |
| Reserva de mesa | RESERVA DE MESA · BR §14 |

---

## EXEMPLOS WORKED

### Exemplo 1: "Posso mudar o FIFO para 300 m?"

**Input (contexto real):**
Durante uma conversa sobre melhoria de dispatch, alguém sugere: "E se aumentar o raio FIFO de 200 m para 300 m? Pega mais drivers próximos."

**Processo:**
1. Skill procura "FIFO" na tabela DISPATCH.
2. Encontra entrada: `Raio FIFO = 200 m (FIFO_RADIUS_KM = 0.2), fixo, source BR §6.2 · §25.2`.
3. Verifica se BR v2 confirma → sim, §6.2 "FIFO geográfico: se há drivers a ≤200m do pickup".
4. Resposta imediata: decisão travada.

**Output esperado:**
```
❌ DECISÃO TRAVADA — FIFO_RADIUS_KM = 0.2 (200 m)
   Source: BR §6.2 + constante em supabase/functions/dispatch-engine/index.ts (§25.2)
   Para mudar: actualizar BR §6.2 primeiro, depois v32 do dispatch-engine.
   Contacta: product owner.
```

**Failure mode:**
A skill falha se inventar "200m é só default, pode ajustar" — o registry aponta sempre para BR §6.2, que é imperativa.

---

### Exemplo 2: "Qual é o timeout actual de oferta ao estafeta?"

**Input (contexto real):**
Um novo dev pergunta: "Quanto tempo o estafeta tem para aceitar uma oferta?"

**Processo:**
1. Skill procura "timeout" ou "oferta" na tabela DISPATCH.
2. Encontra entrada: `Timeout oferta = 40 s (OFFER_TIMEOUT_SECONDS = 40), BR §6.3 · §25.2`.
3. Confirma com BR §6.3 → "40 segundos para o estafeta aceitar ou recusar".
4. Resposta com source.

**Output esperado:**
```
⏱️ TIMEOUT OFERTA = 40 s
   Source: BR §6.3
   Constante: OFFER_TIMEOUT_SECONDS em supabase/functions/dispatch-engine/index.ts (§25.2)
   UI: lib/screens/driver_home_screen.dart mostra timer visível.
   Após 40 s sem resposta → próximo driver, current entra em tried_driver_ids.
```

**Failure mode:**
A skill falha se citar valor antigo, ou se não mencionar `OFFER_TIMEOUT_SECONDS` (nome exacto da constante em BR §25.2).

---

## REFERÊNCIAS BORA APP

A skill consulta (nunca modifica) os seguintes artefactos:

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/business_rules.md` (v2, 26 secções) | Fonte única — tudo aqui é espelho |
| BR §25.2 — constantes dispatch-engine | Valores numéricos literais (timeout, raios, máximos) |
| BR §25.3 — zonas protegidas Flutter | Ficheiros que o registry marca como "não tocar" |
| `supabase/functions/dispatch-engine/index.ts` | Confirmar que constantes vivas correspondem ao registry |
| `lib/services/pricing_service.dart` | Confirmar que pricing code corresponde a BR §2, §5 |
| `lib/dispatch/driver_capacity_service.dart` | Confirmar que batching respeita BR §6.4 |
| skill `memory` + `.claude/.ai/memory/memory_store.md` | Histórico de quando cada decisão foi travada |
| skill `decision_engine` | Avalia impacto antes de qualquer proposta que toque área do registry |

**NOTA:** Quando BR v2 é actualizada, este registry deve ser regenerado na mesma PR. Nunca ficar atrasado — se o registry diverge da BR v2, a BR vence e o registry é corrigido.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** mantém "Architectural Decision Records (ADR)" — cada decisão arquitetural crítica (matching, pricing, surge) fica num documento versionado, consultável por qualquer engenheiro antes de tocar o código. Inclui rationale e data de lock.
>
> **iFood** tem "Living Documentation" — um wiki interno onde toda regra de negócio travada é indexada por tópico (dispatch, pricing, fraude). Divergência entre código e wiki é tratada como bug.
>
> **Glovo** usa "Runbook Catalog" — catálogo numerado de decisões operacionais e incidentes passados, consultado antes de qualquer mudança.
>
> **Bora App equivalente:** `decision_registry` (este ficheiro) + `business_rules.md` v2 + skill `memory` (histórico). Single source of truth = BR v2; registry indexa por tópico; memory mantém histórico cronológico. Três artefactos, função equivalente aos três gigantes, sem overhead de equipa dedicada.

---

## RESPONSABILIDADES

- ✅ Servir como índice consultável de decisões travadas
- ✅ Apontar para o source exacto (BR §X)
- ✅ Bloquear propostas que contradigam decisão travada (escalando para `flow_guard`)

## NÃO PODE FAZER

- ❌ Modificar decisões (só product owner via `business_rules.md`)
- ❌ Criar decisões novas sem fonte em BR v2
- ❌ Substituir `business_rules.md` (é só índice)
- ❌ Tomar decisões por conta própria

---

## ATUALIZAÇÃO

Esta tabela é regenerada quando `business_rules.md` é actualizada. Procedimento:

1. Product owner actualiza `business_rules.md`
2. Bump de versão da BR
3. Skill `decision_registry` é actualizada para reflectir (mesma PR)
4. `memory` recebe append do diff resumido

---

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Consultar decisão já travada | **decision_registry** (eu) |
| Avaliar risco de nova mudança | `decision_engine` |
| Bloquear mudança arquitetural | `flow_guard` |
| Actualizar a decisão travada | product owner via `business_rules.md` |

## RULES

- NUNCA contradizer `business_rules.md`
- Em divergência → BR vence, registry é corrigido
- Consulta obrigatória antes de qualquer mudança em área coberta
- Read-only por natureza (só recebe updates via processo formal)
- Source of truth: `.claude/.ai/business_rules.md` v2
