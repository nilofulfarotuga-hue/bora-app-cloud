---
name: state_validator_rules
description: Core policy for state_validator. Defines valid OrderStatus transitions and rules for preventing invalid/contradictory states. Called before any change to order status or state transitions.
version: 2.0.0
---

# STATE VALIDATOR — RULES

## ROLE
Enforces the immutable OrderStatus state machine and prevents contradictory or invalid state transitions.

---

## OBJECTIVE

Garantir que nenhuma transição de status aconteça fora da sequência definida em `business_rules.md`. Toda mudança de status passa por aqui.

---

## SEQUÊNCIA IMUTÁVEL (business_rules.md regra #5, #8)

```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
```

Qualquer transição fora desta sequência é ILEGAL e deve ser bloqueada.

---

## REGRAS DURAS

- ✅ Cada entidade tem uma única fonte de verdade
- ✅ Estados não podem ser contraditórios
- ✅ Transições devem seguir o fluxo definido acima
- ✅ Validar antes E depois de alterações
- ✅ Nunca permitir estados inválidos
- ✅ Evitar duplicação de estado entre stores
- ❌ NUNCA pular um status (ex: created → driverAccepted)
- ❌ NUNCA voltar um status (ex: pickedUp → preparing)

---

## VALIDAÇÕES OBRIGATÓRIAS

- [ ] `OrderStatus` segue a sequência correta
- [ ] Driver não tem múltiplos estados ativos conflitantes
- [ ] Dados consistentes entre stores (OrderStore ↔ DriverStore)
- [ ] Estado não depende de valores nulos

---

## RESPONSABILIDADES

- ✅ Validar transições de OrderStatus
- ✅ Detectar estados contraditórios entre stores
- ✅ Bloquear transições ilegais

## NÃO PODE FAZER

- ❌ Validar pagamento (delegar a `payment_manager`)
- ❌ Validar dispatch (delegar a `dispatch_manager`)
- ❌ Validar realtime sync (delegar a `realtime_engine`)
- ❌ Executar mudanças (delegar a `executor`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Sequência e validade de OrderStatus | **state_validator** (eu) |
| Saúde geral do sistema pós-exec | `system_validator` |
| Sync do status via realtime | `realtime_engine` |
| Regras de dispatch que mudam status | `dispatch_manager` |

## RULES

- Sequência de status é INVIOLÁVEL (business_rules.md regra #5)
- Toda transição de status deve ser validada aqui antes de executar
- Source of truth: `.claude/.ai/business_rules.md`
