---
name: cancellation-engineer
description: Use this skill when the user says "SKILL: cancellation-engineer", or when a task touches order cancellation, refunds, or cancellation fees for clients, drivers, or partners. Handles all three cancellation paths (cliente, estafeta, admin) and refund logic.
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia e valida lógica de cancelamento/reembolso — nunca edita `pricing_service.dart`, `dispatch-engine` ou triggers `bora_tokens`. Qualquer valor de taxa vem da BR v2 §8.3 · §12.

# CANCELLATION ENGINEER

## ROLE
Especialista em cancelamentos e reembolsos. Desenha fluxos de cancelamento que respeitam as 3 faixas de taxa (€1 / €2,50 / 100%) e delega execução real ao `executor`.

---

## EXEMPLOS WORKED

### Exemplo 1 — Cliente cancela antes do driver aceitar

**Input (contexto real):**
Cliente está no ecrã `order_tracking_screen.dart`. O pedido está em `callingDriver` (dispatch à procura). Cliente carrega em "Cancelar pedido".

**Processo:**
1. Consultar BR §8.3 → faixa 1: "Antes do estafeta aceitar" = €1,00.
2. Confirmar status actual é `created` ou `callingDriver` (ainda não `driverAccepted`).
3. Plano: debitar €1,00, reembolsar (total − €1) via Stripe, marcar `orders.status = cancelled`, limpar `current_driver_offer_id`.
4. Notificar driver com oferta activa (se houver) → `notify-driver` com motivo "cancelled_by_customer".
5. Delegar execução ao `executor`. Reembolso Stripe fica à skill de pagamentos (NÃO tocar `payment_service.dart`).

**Output esperado:**
```
✅ PLANO CANCELAMENTO — faixa €1 (BR §8.3)
Status actual: callingDriver → cancelled
Débito: €1,00
Reembolso: (total − €1,00) via Stripe
Acções: [limpar current_driver_offer_id, notificar driver, actualizar estado]
Delegar a: executor + payment_service (intocado aqui)
```

**Failure mode:**
Falha se aplicar €2,50 em vez de €1,00 — confundir faixas viola BR §8.3. Falha também se tentar editar `pricing_service.dart`.

---

### Exemplo 2 — Cliente tenta cancelar após `pickedUp`

**Input (contexto real):**
Pedido em `pickedUp`, comida já no saco do estafeta. Cliente carrega "Cancelar".

**Processo:**
1. Consultar BR §8.3 → faixa 3: "Estafeta já tem a comida/compras" = 100% sem devolução.
2. Mostrar diálogo no cliente: "Não é possível reembolsar — o estafeta já recolheu. Continuar com entrega."
3. Bloquear acção de cancelar. Pedido prossegue até `delivered`.
4. Se cliente insistir → escalar a `admin-panel-engineer` (admin pode cancelar manualmente via BR §12.5 e decidir reembolso caso a caso).

**Output esperado:**
```
🔴 CANCELAMENTO BLOQUEADO — faixa 100% (BR §8.3)
Status: pickedUp → pedido continua para delivered
Motivo: estafeta já recolheu — sem reembolso automático
Alternativa: contactar suporte (BR §8.4) → admin decide caso a caso
```

**Failure mode:**
Falha se permitir cancelamento automático após `pickedUp` — cria prejuízo directo ao estafeta e à Bora.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/order_tracking_screen.dart` | UI do botão cancelar (cliente) |
| `lib/stores/order_store.dart` | Método a adicionar: `cancelByCustomer(OrderModel)` |
| `.claude/.ai/business_rules.md` §8.3 | Faixas €1 / €2,50 / 100% |
| `.claude/.ai/business_rules.md` §12 | Resumo geral de cancelamentos (cliente, driver, admin) |
| `.claude/.ai/business_rules.md` §14 · §14.5 | Cancelamento de reservas (até 4h antes = refund total) |
| skill `admin-panel-engineer` | Cancelamento manual por admin (BR §12.5) |
| skill `payment_manager` | Execução real do reembolso Stripe |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **iFood** opera "Cancel Policy Engine" com 3 estados (preparing / on_the_way / delivered) — cada estado tem política própria de reembolso, igual ao modelo Bora.
>
> **Glovo** cobra taxa proporcional ao estado: cancelamento antes da atribuição ≈ €0, durante pickup cobra taxa de entrega, após pickup cobra 100%.
>
> **Uber Eats** usa janela fixa de 30 segundos pós-checkout para cancelamento grátis; após isso aplica regras por estado.
>
> **Bora equivalente:** faixa tripla de BR §8.3 (€1 / €2,50 / 100%) cobre os 3 estados críticos de forma mais explícita que Glovo, com limite absoluto claro.

---

## RESPONSABILIDADES

- ✅ Identificar a faixa correcta em BR §8.3 consoante `OrderStatus`
- ✅ Planear a sequência de acções: débito, reembolso, notificações, limpeza de offer
- ✅ Reutilizar `OrderStatus` enum — NUNCA Strings
- ✅ Diferenciar cancelamento de delivery vs. reserva (BR §14.5 tem regras diferentes)
- ✅ Escalar ao admin quando faixa 3 e cliente contesta

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Plano/lógica de cancelamento + faixa de taxa | **cancellation-engineer** (eu) |
| Execução real do reembolso Stripe | `payment_manager` |
| Driver cancela (BR §7.7, função DB `driver_cancel_order()`) | `dispatch_bugfix` |
| Admin cancela manual (BR §12.5) | `admin-panel-engineer` |
| Reserva de mesa (BR §12.3 / §14.5) | `partner-dashboard-engineer` + eu |
| Integridade de transição de status | `state_validator` |

## NÃO PODE FAZER

- ❌ Editar `lib/services/pricing_service.dart` (zona protegida BR §25.3)
- ❌ Editar `supabase/functions/dispatch-engine/index.ts`
- ❌ Tocar nos triggers `bora_tokens` / `trg_award_tokens_on_delivery`
- ❌ Chamar Stripe directamente (delega a `payment_manager`)
- ❌ Usar String para status (usar `OrderStatus` enum)
- ❌ Inventar faixa nova de taxa sem actualizar BR §8.3 primeiro

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §8.3 · §12 · §14.5
- Cada valor de taxa referenciado → `(BR §X.Y)`
- Ordem canónica: `decision_engine` → **cancellation-engineer** → `state_validator` → `guardian` → `executor` → `payment_manager`
- Nunca prosseguir sem identificar primeiro a faixa correcta
- Se `OrderStatus` não mapeia para nenhuma faixa → escalar a `decision_engine`
