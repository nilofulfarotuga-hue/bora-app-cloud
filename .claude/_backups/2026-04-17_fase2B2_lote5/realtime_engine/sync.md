---
name: realtime_engine_sync
description: Sync procedure for realtime_engine. Step-by-step protocol for establishing and maintaining a Supabase Realtime channel correctly.
version: 2.0.0
---

# REALTIME ENGINE — SYNC PROTOCOL

## ROLE
Step-by-step procedure for establishing, maintaining, and tearing down a Supabase Realtime channel correctly.

---

## OBJECTIVE

Garantir que toda nova subscription siga o padrão single-channel, lifecycle-safe, sem duplicação.

---

## PASSOS

### 1. CONECTAR
- Criar channel único (nunca duplicar canal existente)
- Verificar que ID não é null antes de criar
- Cancelar subscription anterior se existir

### 2. ESCUTAR
- Escutar apenas eventos necessários (INSERT, UPDATE, DELETE)
- Nunca escutar `*` se apenas UPDATE é necessário

### 3. PROCESSAR
- Validar dados recebidos antes de usar
- Ignorar eventos inválidos silenciosamente (logar em dev)
- Nunca duplicar eventos

### 4. ATUALIZAR ESTADO
- Atualizar apenas o store correto
- Evitar rebuild desnecessário (`notifyListeners()` só quando dado mudou)
- Garantir ordem de eventos (sem race condition)

### 5. TEARDOWN
- Cancelar subscription em `dispose()`
- Nunca deixar subscription órfã

---

## RESPONSABILIDADES

- ✅ Protocolo de criação/teardown de subscription
- ✅ Garantir ordering e deduplicação de eventos

## NÃO PODE FAZER

- ❌ Modificar RLS ou schema Supabase
- ❌ Executar mudanças diretas no código sem `executor`

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Protocolo de criação/teardown de subscription | **realtime_engine/sync.md** (eu) |
| Política e arquitetura de realtime | `realtime_engine/rules.md` |
| Triage de falha realtime | `realtime_engine/debug.md` |
| Bug pontual de sync | `fix_realtime` |

## RULES

- Subscription ativa = 1 por propósito (regra inviolável)
- Sempre verificar ID antes de iniciar
- Source of truth: `.claude/.ai/business_rules.md`
