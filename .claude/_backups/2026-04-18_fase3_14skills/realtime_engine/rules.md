---
name: realtime_engine_rules
description: Core policy and rules for the realtime_engine skill. Defines how realtime sync between Flutter and Supabase must be architected. For bug investigation use fix_realtime instead.
version: 2.1.0
protection_mode: read-only
---

# REALTIME ENGINE — POLICY & RULES

## ROLE
Defines and enforces realtime sync architecture for the Bora app. Policy layer — not a bug fixer. Consultor especialista — analisa politica de sync, propoe mudancas arquitecturais. Nunca executa directamente.

---

## OBJECTIVE

Garantir sincronizacao estavel, de baixa latencia e sem duplicacao entre frontend Flutter e Supabase Realtime. DB e a unica fonte de verdade (BR §1.3).

---

## REGRAS DURAS

- ✅ Unica fonte de verdade: Supabase (BR §1.3 — DB e source of truth)
- ✅ Uma unica subscription activa por proposito
- ✅ Sempre cancelar subscription anterior antes de criar nova
- ✅ Nunca iniciar listener sem controle de lifecycle
- ✅ Sempre cancelar em `dispose()`
- ✅ Garantir que IDs nunca sejam null antes de criar subscription
- ❌ NUNCA depender de delays artificiais para sync
- ❌ NUNCA criar multiplas subscriptions para o mesmo canal
- ❌ NUNCA iniciar stream com ID null

---

## FLUXO PADRAO

1. INICIAR — criar subscription unica com filtro correcto
2. SINCRONIZAR — receber eventos do backend
3. ATUALIZAR — atualizar estado local no store correcto
4. VALIDAR — confirmar consistencia com DB (BR §1.3)

---

## EXEMPLOS WORKED

#### Exemplo 1: Request "mudar canal Supabase realtime para polling"

**Input (contexto):**
Utilizador quer substituir Supabase Realtime channels por polling HTTP simples, achando que e mais estavel.

**Processo:**
1. Analisa BR §22 (Firebase Push — notificacoes sao push-based)
2. Analisa BR §6.1 (dispatch triggers via pg_cron + imediato)
3. Avalia impacto: polling introduz latencia de 1-3s em updates de status — cliente ve estafeta "parado" enquanto ele se move
4. Mudar arquitectura central → flow_guard obrigatorio, exige plano completo

**Output esperado:**
Recomenda manter Supabase Realtime para estado de pedidos e posicao do driver (baixa latencia critica). Se instabilidade detectada, propoe reconnect strategy em vez de polling. Mudanca arquitectural exige plano via flow_guard.

**Failure mode:**
Substituir realtime por polling sem flow_guard → latencia invisivel, UX degradada, dispatch fica lento, cliente nao ve estafeta mover em tempo real.

---

#### Exemplo 2: Driver perde conexao e volta — estado dessincronizado

**Input (contexto):**
Driver perdeu conexao WiFi/4G por 2 minutos. Ao voltar, app mostra estado antigo do pedido (ainda em `preparing` quando ja esta `pickedUp`).

**Processo:**
1. Analisa: sync strategy actual — Supabase Realtime nao reenvia eventos perdidos (nao e message queue)
2. DB e source of truth (BR §1.3) — app precisa re-fetch ao reconectar
3. Propoe: ao detectar reconnect, fazer fetch full state de orders antes de reactivar streams

**Output esperado:**
Propoe adicionar reconnect handler: (1) detectar mudanca de conectividade, (2) ao reconectar, chamar `OrderStore.refresh()` para buscar estado actual da DB, (3) so depois reactivar Realtime channel. Delegar implementacao a executor.

**Failure mode:**
Reactivar channel sem re-fetch → app mostra estado stale, driver pode tentar pickup de pedido ja cancelado.

---

## REFERENCIAS BORA APP

- Consulta: `lib/services/` (realtime_service, notification_service)
- Consulta: `supabase/functions/notify-*` (todos os notify edge functions)
- BR §22 (Notificacoes — Firebase Push, FCM tokens)
- BR §6.1 (Dispatch triggers — pg_cron + imediato)
- BR §1.3 (Progressao de status do pedido — DB e source of truth)
- BR §1.4 (Progressao de status da reserva)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber tem "Realtime Platform Team" que gere streams e WebSockets globalmente com fallback automatico.
> iFood tem "Messaging Infrastructure" com garantia de delivery at-least-once.
> Glovo tem "Live Tracking Platform" com reconnect e state reconciliation automatico.
> Bora equivalente: realtime_engine/rules define politica de sync em BR §22 e §1.3.
> Analisa arquitectura realtime e propoe — execucao via chain aprovada.

---

## RESPONSABILIDADES

- ✅ Definir politica de sync (channels, subscriptions, lifecycle)
- ✅ Revisar mudancas arquitecturais em realtime
- ✅ Garantir padrao single-subscription em todo o app
- ✅ Propor reconnect strategies e state reconciliation
- ✅ Propor mudancas via chain: realtime_engine → decision_engine → guardian → executor

## NAO PODE FAZER

- ❌ Debugar bug pontual de sync (delegar a `fix_realtime`)
- ❌ Modificar RLS (delegar a `flow_guard` + `supabase_agent`)
- ❌ Executar mudancas (delegar a `executor`)
- ❌ Alterar edge functions notify-* directamente

## FRONTEIRAS

| Situacao | Skill correcta |
|---|---|
| Politica e arquitectura de realtime | **realtime_engine** (eu) |
| Bug pontual de sync | `fix_realtime` |
| Mudancas em RLS | `flow_guard` + `supabase_agent` |
| Sequencia de status via realtime | `state_validator` |

## RULES

- Toda mudanca em arquitectura realtime passa por `flow_guard` primeiro
- Source of truth: `.claude/.ai/business_rules.md`
- DB e unica fonte de verdade (BR §1.3) — app nunca assume estado sem confirmar com DB
