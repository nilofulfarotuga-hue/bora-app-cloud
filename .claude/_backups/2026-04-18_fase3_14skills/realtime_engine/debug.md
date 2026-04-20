---
name: realtime_engine_debug
description: Debug sub-procedure for realtime_engine. Quick checklist for identifying realtime failures — no code changes, diagnosis only. For full bug investigation use fix_realtime.
version: 2.1.0
protection_mode: read-only
---

# REALTIME ENGINE — DEBUG CHECKLIST

## ROLE
Quick triage tool for realtime issues. Identify failure point before calling `fix_realtime` for full investigation. Consultor de diagnostico — analisa, identifica causa, delega fix. Nunca executa directamente.

---

## OBJECTIVE

Localizar rapidamente onde o fluxo realtime falha (eventos nao chegam, dados inconsistentes, delay alto). DB e unica fonte de verdade (BR §1.3).

---

## CHECKLIST

### Eventos nao chegam
- [ ] Subscription activa? (`StreamSubscription` nao e null)
- [ ] Canal correcto? (nome + filtro)
- [ ] Dados correctos no backend? (verificar no Dashboard)
- [ ] RLS permite acesso? (testar com SQL Editor)
- [ ] ID nao e null quando subscription foi criada?
- [ ] FCM token valido e registado? (BR §22.1)
- [ ] Edge function notify-* executou sem erro?

### Dados inconsistentes
- [ ] Duplicacao de eventos? (multiplas subscriptions?)
- [ ] Perda de eventos? (filtro muito restritivo?)
- [ ] Race condition? (subscription criada antes de auth completar?)
- [ ] ID comparison vs referencia? (CLAUDE.md: usar ID, nunca `contains()`)

### Delay alto
- [ ] Delay artificial (`Future.delayed`) no fluxo?
- [ ] `notifyListeners()` disparando rebuild desnecessario?
- [ ] Fallback para polling activo? (verificar se channel foi perdido)
- [ ] pg_cron delay? (dispatch corre cada minuto — BR §6.1)

---

## EXEMPLOS WORKED

#### Exemplo 1: Push notification chega ao cliente mas app nao reage

**Input (contexto):**
Cliente recebe push notification "Pedido a caminho" no sistema, mas a app continua a mostrar status `preparing`.

**Processo:**
1. Analisa: push notification e entregue pelo Firebase (BR §22.1) — funciona
2. Verifica: `onMessage` handler registado na app? Navigation key disponivel?
3. Diagnostico: payload da push nao tem campo `order_id` esperado pelo handler
4. Verifica edge functions `notify-customer` — payload pode estar incompleto

**Output esperado:**
Diagnostico: payload inconsistente entre edge functions notify-*. Propoe padronizar payload com campos obrigatorios (`order_id`, `status`, `type`) em todas as edge functions. Delega fix a executor. Nao edita edge functions directamente.

**Failure mode:**
Corrigir apenas uma edge function → as outras continuam com payload inconsistente. Proximo bug identico noutro fluxo.

---

#### Exemplo 2: Status do pedido atualiza com 5 segundos de atraso

**Input (contexto):**
Cliente reporta que ve status mudar com 3-5 segundos de atraso em relacao ao que o driver faz.

**Processo:**
1. Analisa: Supabase Realtime channel subscription vs polling fallback
2. Verifica: cliente fez fallback para polling? (OrderStore tem Timer.periodic de 3s como fallback)
3. Diagnostico: channel subscription pode ter falhado silenciosamente, app caiu para polling
4. Verifica: `_resubscribeWithDelay` foi chamado? Retry apos 5s (CLAUDE.md)

**Output esperado:**
Diagnostico: cliente perdeu Realtime channel e caiu para polling fallback (Timer.periodic 3s). Propoe: (1) detectar perda de channel mais rapidamente, (2) reconnect automatico ao channel quando detecta fallback, (3) log de warning quando fallback e activado. Delega a fix_realtime + executor.

**Failure mode:**
Reduzir intervalo de polling para 1s → resolve sintoma mas aumenta carga no servidor e consumo de bateria. Causa raiz (channel perdido) nao e resolvida.

---

## REFERENCIAS BORA APP

- Consulta: `supabase/functions/notify-*/index.ts` (edge functions de notificacao)
- Consulta: `lib/services/notification_service.dart`
- Consulta: `lib/stores/order_store.dart` (subscricao realtime, fallback polling)
- BR §22.1 (Firebase Push — FCM tokens, edge functions notify-*)
- BR §22.2 (Som app driver — toca ao chegar oferta)
- BR §1.3 (FSM delivery — DB e source of truth)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber tem "Realtime Incident Tooling" com dashboards de delivery rate e channel health.
> Glovo tem "Sync Debug Console" para inspeccao em producao de event pipeline.
> iFood tem "Order Event Debugger" com replay de eventos para diagnostico.
> Bora equivalente: realtime_engine/debug e runbook de diagnostico — channels,
> tokens FCM, edge functions notify, payloads. Diagnostica — nunca corrige.

---

## RESPONSABILIDADES

- ✅ Triage rapido de falha realtime (diagnostico, nao fix)
- ✅ Identificar causa raiz com evidencia
- ✅ Verificar consistencia de payloads entre edge functions
- ✅ Verificar estado de channels e subscriptions

## NAO PODE FAZER

- ❌ Propor correccao de codigo (delegar a `fix_realtime` + `executor`)
- ❌ Alterar politica de sync (delegar a `realtime_engine/rules.md`)
- ❌ Editar edge functions notify-* directamente

## FRONTEIRAS

| Situacao | Skill correcta |
|---|---|
| Triage rapido de falha realtime | **realtime_engine/debug.md** (eu) |
| Bug pontual com fix completo | `fix_realtime` |
| Politica de realtime | `realtime_engine/rules.md` |

## RULES

- Apenas diagnostica — nao corrige
- Ao identificar causa → passar para `fix_realtime`
- DB e unica fonte de verdade (BR §1.3)
- Source of truth: `.claude/.ai/business_rules.md`
