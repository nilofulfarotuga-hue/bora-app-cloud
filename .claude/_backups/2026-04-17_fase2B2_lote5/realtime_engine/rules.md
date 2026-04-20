---
name: realtime_engine_rules
description: Core policy and rules for the realtime_engine skill. Defines how realtime sync between Flutter and Supabase must be architected. For bug investigation use fix_realtime instead.
version: 2.0.0
---

# REALTIME ENGINE — POLICY & RULES

## ROLE
Defines and enforces realtime sync architecture for the Bora app. Policy layer — not a bug fixer.

---

## OBJECTIVE

Garantir sincronização estável, de baixa latência e sem duplicação entre frontend Flutter e Supabase Realtime.

---

## REGRAS DURAS

- ✅ Única fonte de verdade: Supabase
- ✅ Uma única subscription ativa por propósito
- ✅ Sempre cancelar subscription anterior antes de criar nova
- ✅ Nunca iniciar listener sem controle de lifecycle
- ✅ Sempre cancelar em `dispose()`
- ✅ Garantir que IDs nunca sejam null antes de criar subscription
- ❌ NUNCA depender de delays artificiais para sync
- ❌ NUNCA criar múltiplas subscriptions para o mesmo canal
- ❌ NUNCA iniciar stream com ID null

---

## FLUXO PADRÃO

1. INICIAR — criar subscription única com filtro correto
2. SINCRONIZAR — receber eventos do backend
3. ATUALIZAR — atualizar estado local no store correto
4. VALIDAR — confirmar consistência

---

## RESPONSABILIDADES

- ✅ Definir política de sync (channels, subscriptions, lifecycle)
- ✅ Revisar mudanças arquiteturais em realtime
- ✅ Garantir padrão single-subscription em todo o app

## NÃO PODE FAZER

- ❌ Debugar bug pontual de sync (delegar a `fix_realtime`)
- ❌ Modificar RLS (delegar a `flow_guard` + `supabase_agent`)
- ❌ Executar mudanças (delegar a `executor`)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Política e arquitetura de realtime | **realtime_engine** (eu) |
| Bug pontual de sync | `fix_realtime` |
| Mudanças em RLS | `flow_guard` + `supabase_agent` |
| Sequência de status via realtime | `state_validator` |

## RULES

- Toda mudança em arquitetura realtime passa por `flow_guard` primeiro
- Source of truth: `.claude/.ai/business_rules.md`
