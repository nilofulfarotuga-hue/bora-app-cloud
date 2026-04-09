---
name: dispatch_bugfix
description: This skill should be used when the user says "SKILL: dispatch_bugfix", or when investigating a SPECIFIC bug in the existing dispatch system (broadcast leak, current_driver_offer_id null, multiple drivers receiving, redispatch loop). Bug-fixer only — never implements new dispatch rules (those belong to dispatch_manager).
version: 2.0.0
---

# DISPATCH BUGFIX — INCIDENT INVESTIGATOR

## ROLE
Investigates and corrects pontual bugs in the existing sequential dispatch implementation. Never implements new business rules — only fixes regressions and incidents.

For new rules (queue 200m/5s, capacity 1↔3, in-store priority, SLA monitor), delegate to `dispatch_manager`.

---

## OBJECTIVE

Identify root cause of a dispatch incident with concrete evidence and propose a minimal, targeted fix that does not change the dispatch architecture.

---

## SCOPE

✅ **In scope** — bug investigation/fix for:
- Broadcast leak (multiple drivers receiving same offer)
- `current_driver_offer_id` null when it should be set
- Optimistic lock failing
- Redispatch loop / double-dispatch
- `tried_driver_ids` not respected
- Offer expiry race
- State stuck on `callingDriver`

❌ **Out of scope** (delegate to `dispatch_manager`):
- Implementing 200m local queue
- Implementing capacity 1↔3
- Implementing in-store priority
- Implementing GPS-driven SLA monitor
- Implementing batching with ×1.20 criterion
- Adding new constants

---

## REGRAS CRÍTICAS (do business_rules.md — INVIOLÁVEIS)

- Sequential dispatch — NUNCA broadcast (regra #1, #6)
- FIFO geográfico puro na fila local — sem ranking (regra #7)
- `current_driver_offer_id` deve estar setado antes de status mudar para `callingDriver`
- Optimistic locking obrigatório nos UPDATEs

---

## INVESTIGAÇÃO (OBRIGATÓRIA ANTES DE QUALQUER FIX)

### Passo 1 — Reproduzir
- [ ] Logs Supabase Edge Function `dispatch-engine` no momento do bug
- [ ] Estado do pedido afetado (status, current_driver_offer_id, tried_driver_ids, driver_offer_expires_at)
- [ ] Quantos drivers receberam (deveria ser 1)

### Passo 2 — Localizar causa
- [ ] Onde drivers são selecionados? (`dispatch-engine/index.ts`)
- [ ] Onde `current_driver_offer_id` é definido?
- [ ] Por que o lock otimista não bloqueou?
- [ ] `tried_driver_ids` foi atualizado?

### Passo 3 — Provar
Para cada erro encontrado, registrar:
- Arquivo + linha
- Trecho de código problemático
- Por que produz o sintoma observado

---

## CHECKLIST DE FIX

Antes de aprovar correção:

- [ ] Fix é mínimo (1 função / 1 query / 1 condição)
- [ ] Não introduz broadcast
- [ ] Mantém optimistic lock
- [ ] `current_driver_offer_id` continua setado antes de `callingDriver`
- [ ] Não toca em fila local / capacidade / SLA (escopo de dispatch_manager)
- [ ] Logs adicionados para confirmar cura
- [ ] Reprodução do bug deixa de acontecer

---

## RESPONSABILIDADES

- ✅ Investigar incidentes pontuais de dispatch
- ✅ Propor fixes cirúrgicos com prova (file:line)
- ✅ Garantir que o fix não viola regras críticas

## NÃO PODE FAZER

- ❌ Implementar novas regras de negócio (delegar a `dispatch_manager`)
- ❌ Refatorar a arquitetura do dispatch (delegar a `flow_guard` + `refactor_guard`)
- ❌ Modificar constantes da BR
- ❌ Tocar em pagamento / tokens / estados / realtime
- ❌ Adicionar fila local / SLA monitor (são features, não bugs)

---

## FRONTEIRAS

| Não tocar em | Skill responsável |
|---|---|
| Novas regras de dispatch | dispatch_manager |
| Refator arquitetural | flow_guard + refactor_guard |
| Sequência de estados | state_validator |
| Pagamento | payment_manager |
| Tokens | token_manager |
| Sync realtime | realtime_engine |

---

## RULES

- Bug-fixer ONLY. Não é feature implementer.
- Toda correção precisa de prova (file:line + log)
- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- Em conflito → BR vence
