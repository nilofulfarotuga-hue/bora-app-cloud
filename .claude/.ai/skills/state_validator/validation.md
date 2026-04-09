---
name: state_validator_validation
description: Validation procedure for state_validator. Step-by-step checklist to run before and after any state/status change.
version: 2.0.0
---

# STATE VALIDATOR — VALIDATION PROCEDURE

## ROLE
Step-by-step validation procedure. Run before AND after any change to order state or status.

---

## OBJECTIVE

Confirmar que estado atual é válido, que a transição proposta é legal, e que não há inconsistência após a mudança.

---

## PASSOS

### 1. ANALISAR
- Identificar estado atual (qual OrderStatus?)
- Identificar estado esperado (para onde está indo?)

### 2. COMPARAR
- Verificar inconsistência (estado atual ≠ esperado sem transição válida?)
- Verificar duplicação (mesmo estado em stores diferentes?)

### 3. VALIDAR TRANSIÇÃO
- Transição é válida? (segue a sequência imutável?)
- Segue a ordem correta?
- Não pula nenhum status?

### 4. DETECTAR ERRO
- Estado inválido → BLOQUEAR e reportar
- Estado duplicado → BLOQUEAR e reportar
- Estado ausente → BLOQUEAR e reportar

---

## CHECKLIST PÓS-MUDANÇA

- [ ] Status correto no banco (`orders.status`)?
- [ ] Sequência respeitada?
- [ ] Dados consistentes entre `OrderStore` e Supabase?
- [ ] Sem conflitos de driver?
- [ ] `current_driver_offer_id` coerente com status?

---

## RESPONSABILIDADES

- ✅ Validar estado antes e depois de mudanças
- ✅ Bloquear transições ilegais

## NÃO PODE FAZER

- ❌ Corrigir o estado incorreto (reportar + delegar a skill especialista)
- ❌ Executar mudanças no banco

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Validar transição de estado passo a passo | **state_validator/validation.md** (eu) |
| Política e regras de estado | `state_validator/rules.md` |
| Saúde geral do sistema | `system_validator` |

## RULES

- Sequência INVIOLÁVEL: `created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered`
- Qualquer transição fora dessa sequência é bloqueada
- Source of truth: `.claude/.ai/business_rules.md`
