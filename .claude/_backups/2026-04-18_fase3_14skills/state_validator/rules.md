---
name: state_validator_rules
description: Core policy for state_validator. Defines valid OrderStatus transitions and rules for preventing invalid/contradictory states. Called before any change to order status or state transitions.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill define a FSM imutável de status do pedido e da reserva — nunca modifica código. Toda transição citada aponta para BR §1.3 (delivery) ou §1.4 (reserva).

# STATE VALIDATOR — RULES

## ROLE
Enforces the immutable OrderStatus state machine and prevents contradictory or invalid state transitions.

---

## OBJECTIVE

Garantir que nenhuma transição de status aconteça fora da sequência definida em `business_rules.md`. Toda mudança de status passa por aqui.

---

## SEQUÊNCIA IMUTÁVEL — DELIVERY (BR §1.3)

```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
```

Qualquer transição fora desta sequência é **ILEGAL** e deve ser bloqueada.

### Estados terminais legítimos
- `delivered` — fluxo completo
- `rejected` — só a partir de `created` (não-parceiro sem cobertura ou parceiro recusa)
- `cancelled` — via `driver_cancel_order()` RPC (volta a `callingDriver`, ver BR §7.7)

---

## SEQUÊNCIA IMUTÁVEL — RESERVA (BR §1.4 · §14.8)

```
reservation_requested
  → restaurant_responding
  → (accepted | suggested_alternative | rejected)
  → confirmed
  → customer_arrived
  → completed | no_show
```

Fora desta sequência: **ILEGAL**.

---

## REGRAS DURAS

- ✅ Cada entidade tem uma única fonte de verdade (`OrderStore` ou `ReservationStore`)
- ✅ Estados não podem ser contraditórios
- ✅ Transições devem seguir o fluxo definido em BR §1.3 / §1.4
- ✅ Validar antes E depois de alterações
- ✅ Nunca permitir estados inválidos
- ✅ Evitar duplicação de estado entre stores
- ❌ **NUNCA pular** um status (ex: `created` → `driverAccepted`)
- ❌ **NUNCA voltar** um status (ex: `pickedUp` → `preparing`)
- ❌ **NUNCA usar String** em vez do enum `OrderStatus` (CLAUDE.md core rule + BR §1.3)

### Excepções documentadas
- `driverAccepted → callingDriver` é legal **apenas** via `driver_cancel_order()` RPC (BR §7.7) — ainda assim, é "volta" controlada, não livre.
- `pickedUp → callingDriver` idem — só via cancel do estafeta.

---

## VALIDAÇÕES OBRIGATÓRIAS

Antes de aprovar qualquer transição:

- [ ] Transição existe em BR §1.3 (delivery) ou §1.4 (reserva)?
- [ ] `OrderStatus` está tipado como enum (não String)?
- [ ] Driver não tem múltiplos estados activos conflituantes?
- [ ] Dados consistentes entre stores (`OrderStore` ↔ `DriverStore`)?
- [ ] Estado não depende de valores nulos?
- [ ] Para `driverAccepted` em diante: `assigned_driver_id` preenchido?
- [ ] Para `pickedUp` em não-parceiro: `isPurchaseFinalized = true` (BR §7.4)?
- [ ] Para `delivered`: código 4 dígitos validado (BR §7.3)?

---

## EXEMPLOS WORKED

### Exemplo 1: Tentativa de saltar de `preparing` → `driverAccepted`

**Input (contexto real):**
Um novo desenvolvedor escreve uma função que atribui driver ao pedido sem passar por `callingDriver`: "já sei quem é o driver, vou marcar aceite directamente".

**Processo:**
1. state_validator/rules lê sequência BR §1.3.
2. Compara transição proposta: `preparing` → `driverAccepted`.
3. Sequência legal de `preparing` é apenas `callingDriver`.
4. Veredicto: ILEGAL. Mesmo se o driver já é conhecido, tem de passar por `callingDriver` para o guard de dispatch (BR §6.5) registar a oferta e respeitar `OFFER_TIMEOUT_SECONDS = 40 s`.

**Output esperado:**
```
🛑 STATE VALIDATOR: ILLEGAL TRANSITION
FROM: preparing
TO:   driverAccepted
BR REF: §1.3 (sequência imutável)

MOTIVO: A sequência legal de `preparing` é apenas `callingDriver`.
        Pular callingDriver contorna o guard de dispatch (BR §6.5).

AÇÃO NECESSÁRIA:
  1. Passar por callingDriver (ainda que breve)
  2. Registar current_driver_offer_id
  3. Só então advance para driverAccepted
```

**Failure mode:**
A skill falha se aceitar "mas já sei quem é o driver" como excepção — a FSM é imutável e o guard de dispatch depende do passo intermédio.

---

### Exemplo 2: Avançar para `delivered` sem passar por `onTheWay`

**Input (contexto real):**
Botão "Marcar entregue" num ecrã de teste chama `_advanceStatus(OrderStatus.delivered)` directamente a partir de `pickedUp`.

**Processo:**
1. Sequência BR §1.3: `pickedUp → onTheWay → delivered`.
2. Proposta: `pickedUp → delivered`. Salta `onTheWay`.
3. `onTheWay` não é decorativo — é o estado em que o cliente vê "estafeta a caminho" e o chat está activo (BR §8.2).
4. Além disso, confirmação de entrega exige **código 4 dígitos** (BR §7.3) — validação faz-se em `onTheWay → delivered`.

**Output esperado:**
```
🛑 STATE VALIDATOR: ILLEGAL TRANSITION
FROM: pickedUp
TO:   delivered
BR REF: §1.3 + §7.3 (código 4 dígitos)

MOTIVO: Salta `onTheWay`. Em consequência:
  - Cliente nunca vê "estafeta a caminho" (BR §8.2)
  - Código 4 dígitos não é validado (BR §7.3)
  - Chat driver↔cliente fecha prematuramente

AÇÃO NECESSÁRIA:
  1. Advance para onTheWay primeiro
  2. Driver solicita código ao cliente na entrega
  3. Só com código válido → delivered
```

**Failure mode:**
A skill falha se deixar passar como "atalho de demo" — mesmo em ambiente de teste, a FSM é imutável para evitar que o código de teste entre em produção.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `.claude/.ai/business_rules.md` §1.3 | Sequência imutável delivery (source of truth) |
| `.claude/.ai/business_rules.md` §1.4 · §14.8 | Sequência imutável reserva |
| `.claude/.ai/business_rules.md` §7.3 · §7.4 | Pré-condições para `delivered` (código 4 dígitos, isPurchaseFinalized) |
| `.claude/.ai/business_rules.md` §7.7 | Cancel pelo driver — única "volta" legítima |
| `lib/models/order_model.dart` | Enum `OrderStatus` (fonte de código) |
| `lib/stores/order_store.dart` | `_advanceStatus` e `_statusFlow` (implementação) |
| `lib/models/order_service_type.dart` | `OrderServiceType` (restaurant/storeShopping/carryGroceries/sendPackage) |
| skill `state_validator/validation.md` | Checklist step-by-step antes/depois da transição |
| skill `guardian` | Alertar se código usa String em vez do enum |
| skill `flow_guard` | Escalar se alguém propõe mudar o próprio enum |

**NOTA:** skill apenas define a policy. A execução do checklist é feita pela sub-skill `validation.md`.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** define "Trip State Machine" formal em documentação interna — cada transição tem pré-condições, pós-condições e evento que a dispara. Mudanças à FSM exigem RFC + approval do arquiteto.
>
> **iFood** tem "Order Status FSM" versionada — diagrama de estados canônico, gerado automaticamente a partir do código e comparado contra o doc em cada PR.
>
> **Glovo** usa "State Machine Tests" — suite obrigatória que tenta todas as transições ilegais e espera que sejam bloqueadas.
>
> **Bora App equivalente:** `state_validator/rules.md` define a FSM ancorada em BR §1.3 (imutável) + `validation.md` executa o checklist por transição. Cobre o papel dos três: documento canónico + verificação + bloqueio de ilegais. Sem geração automática (opcional para o futuro).

---

## RESPONSABILIDADES

- ✅ Validar transições de `OrderStatus` e status de reserva
- ✅ Detectar estados contraditórios entre stores
- ✅ Bloquear transições ilegais
- ✅ Ancorar cada regra em BR §1.3 ou §1.4

## NÃO PODE FAZER

- ❌ Validar pagamento (delegar a `payment_manager`)
- ❌ Validar dispatch (delegar a `dispatch_manager`)
- ❌ Validar realtime sync (delegar a `realtime_engine`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Sequência e validade de OrderStatus | **state_validator/rules** (eu) |
| Checklist step-by-step por transição | `state_validator/validation` |
| Saúde geral do sistema pós-exec | `system_validator` |
| Sync do status via realtime | `realtime_engine` |
| Regras de dispatch que mudam status | `dispatch_manager` |

## RULES

- Sequência de status é **INVIOLÁVEL** (BR §1.3 · §1.4)
- Toda transição de status deve ser validada aqui antes de executar
- Usar sempre o enum `OrderStatus`, **nunca String** (CLAUDE.md core rule)
- Source of truth: `.claude/.ai/business_rules.md` v2
