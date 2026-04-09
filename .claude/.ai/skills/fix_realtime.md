---
name: fix_realtime
description: This skill should be used when the user says "SKILL: fix_realtime", or when investigating specific realtime sync bugs — data not arriving, duplicates, missing updates, wrong user receiving events, or subscription lifecycle issues.
version: 2.0.0
---

# FIX REALTIME — REALTIME SYNC INVESTIGATOR

## ROLE
Investigates and proposes fixes for specific realtime synchronization bugs between Flutter and Supabase. Bug-fixer only — for policy/architecture changes delegate to `realtime_engine`.

---

## OBJECTIVE

Diagnose realtime failures with concrete evidence (subscription state, channel config, driverId, data) and propose minimal targeted fixes.

---

## FLUXO COMPLETO (mapa mental obrigatório)

```
Flutter writes data
  → Supabase stores data
  → Realtime event emitted
  → Flutter subscription via stream
  → UI updates
```

Identificar EXATAMENTE onde quebra antes de qualquer fix.

---

## CHECKLIST DE INVESTIGAÇÃO

### 1. DRIVER ID (CRÍTICO)
- [ ] `driverId` NÃO é null
- [ ] `driverId` NÃO é string vazia
- [ ] `driverId` = `supabase.auth.currentUser!.id`
- Se inválido → **fix auth primeiro** (`fix_auth`)

### 2. CONFIGURAÇÃO DO STREAM
- [ ] Stream usa filtro correto (`eq('current_driver_offer_id', driverId)`)
- [ ] `primaryKey` correto (`['id']`)
- [ ] Sem stream duplicado (só 1 `StreamSubscription` ativa)
- [ ] Stream anterior cancelado antes de criar novo

### 3. LIFECYCLE
- [ ] Subscription cancelada em `dispose()`
- [ ] Stream não iniciado com ID null
- [ ] `onAuthStateChange` listener não cria múltiplas subscriptions

### 4. DADOS NO BACKEND
- [ ] Verificar no Supabase Dashboard se dado foi gravado
- [ ] Verificar RLS — usuário tem acesso à row?
- [ ] Verificar se evento foi emitido (Supabase Realtime Logs)

---

## RESPONSABILIDADES

- ✅ Investigar bugs pontuais de sync realtime
- ✅ Propor fix mínimo com prova (file:line)
- ✅ Garantir single-subscription, lifecycle correto, filtro correto

## NÃO PODE FAZER

- ❌ Alterar política de sync ou arquitetura (delegar a `realtime_engine`)
- ❌ Modificar RLS sem `flow_guard`
- ❌ Corrigir bugs de auth (delegar a `fix_auth`)
- ❌ Modificar dispatch/tokens/pagamento
- ❌ Executar mudanças (delegar a `executor`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Bug pontual de sync (subscription, canal, filtro) | **fix_realtime** (eu) |
| Política de realtime / arquitetura de channels | `realtime_engine` |
| driverId null / auth inválido | `fix_auth` |
| Rebuild excessivo causado por updates | `performance_watcher` |
| Sequência de status via realtime | `state_validator` |

## RULES

- Investigar antes de qualquer fix (causa raiz obrigatória)
- Prova obrigatória: file:line + log/evento capturado
- Fix mínimo — nunca refatorar enquanto corrige
- Source of truth: `.claude/.ai/business_rules.md`
