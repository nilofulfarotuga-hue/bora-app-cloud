---
name: realtime_engine_sync
description: Sync procedure for realtime_engine. Step-by-step protocol for establishing and maintaining a Supabase Realtime channel correctly.
version: 2.1.0
protection_mode: read-only
---

# REALTIME ENGINE — SYNC PROTOCOL

## ROLE
Step-by-step procedure for establishing, maintaining, and tearing down a Supabase Realtime channel correctly. Consultor especialista — define protocolo de sync, analisa e propoe. Nunca executa directamente.

---

## OBJECTIVE

Garantir que toda nova subscription siga o padrao single-channel, lifecycle-safe, sem duplicacao. DB e unica fonte de verdade (BR §1.3).

---

## PASSOS

### 1. CONECTAR
- Criar channel unico (nunca duplicar canal existente)
- Verificar que ID nao e null antes de criar
- Cancelar subscription anterior se existir

### 2. ESCUTAR
- Escutar apenas eventos necessarios (INSERT, UPDATE, DELETE)
- Nunca escutar `*` se apenas UPDATE e necessario

### 3. PROCESSAR
- Validar dados recebidos antes de usar
- Ignorar eventos invalidos silenciosamente (logar em dev)
- Nunca duplicar eventos

### 4. ATUALIZAR ESTADO
- Atualizar apenas o store correcto
- Evitar rebuild desnecessario (`notifyListeners()` so quando dado mudou)
- Garantir ordem de eventos (sem race condition)
- DB e source of truth (BR §1.3) — em duvida, re-fetch

### 5. TEARDOWN
- Cancelar subscription em `dispose()`
- Nunca deixar subscription orfa

---

## EXEMPLOS WORKED

#### Exemplo 1: Cliente e driver veem status diferentes do pedido

**Input (contexto):**
Cliente ve pedido em `preparing` mas driver ve `driverAccepted`. Ambos estao online e com app aberta.

**Processo:**
1. Analisa: quem e source of truth? → DB e SoT (BR §1.3)
2. Verifica DB: status real e `driverAccepted`
3. Diagnostico: client-side esta a cachear status sem re-fetch apos evento realtime
4. Verifica: subscription do cliente filtra correctamente? Canal correcto?

**Output esperado:**
Fix: invalidar cache do cliente sempre que chega evento UPDATE no canal de orders. Garantir que `OrderStore` substitui objecto inteiro com `fromSupabase` (CLAUDE.md ja documenta isto — ID comparison, nao referencia). Delegar patch a executor.

**Failure mode:**
Usar `contains()` em vez de ID comparison para encontrar order na lista → realtime UPDATE substitui objecto e `contains()` falha silenciosamente. Status antigo fica visivel.

---

#### Exemplo 2: Novo pedido nao aparece instantaneamente ao driver online

**Input (contexto):**
Driver esta online com app aberta mas nao recebe notificacao de novo pedido durante 30-60 segundos.

**Processo:**
1. Analisa: subscricao realtime esta activa? FCM token valido?
2. Verifica: edge function `dispatch-engine` so corre via pg_cron (cada minuto) (BR §6.1)
3. Diagnostico: delay e expectavel se dispatch so corre a cada minuto
4. BR §6.1 diz que dispatch tambem e accionado imediatamente quando pedido entra em `callingDriver`

**Output esperado:**
Verificar se trigger imediato de dispatch esta activo (BR §6.1). Se so pg_cron, propoe adicionar trigger via `pg_net` quando order muda para `callingDriver`. Nao toca dispatch-engine directamente (zona protegida BR §25.3) — propoe via chain.

**Failure mode:**
Criar polling client-side para compensar delay → desperdiça bateria, requests desnecessarios, nao resolve causa raiz.

---

## REFERENCIAS BORA APP

- Consulta: `lib/stores/` — onde Supabase Realtime e subscrito (`OrderStore`, `DriverStore`)
- Consulta: `supabase/migrations/` — realtime publication config
- BR §1.3 (Progressao de status — FSM delivery, DB e SoT)
- BR §1.4 (Progressao de status — FSM reserva)
- BR §22 (Notificacoes — Firebase Push, edge functions notify-*)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber usa "Rider-Driver State Machine Synchronizer" para manter ambos alinhados em tempo real.
> iFood tem "Order State Propagator" com at-least-once delivery guarantee.
> Glovo tem "Order Sync Service" com reconciliacao periodica e event sourcing.
> Bora equivalente: realtime_engine/sync garante BR §1.3 e §1.4 sincronizados
> entre client/driver/restaurant/admin. Define protocolo — execucao via chain.

---

## RESPONSABILIDADES

- ✅ Protocolo de criacao/teardown de subscription
- ✅ Garantir ordering e deduplicacao de eventos
- ✅ Propor reconnect e state reconciliation strategies
- ✅ Propor mudancas via chain: realtime_engine/sync → decision_engine → executor

## NAO PODE FAZER

- ❌ Modificar RLS ou schema Supabase
- ❌ Executar mudancas directas no codigo sem `executor`
- ❌ Alterar edge functions notify-* directamente

## FRONTEIRAS

| Situacao | Skill correcta |
|---|---|
| Protocolo de criacao/teardown de subscription | **realtime_engine/sync.md** (eu) |
| Politica e arquitectura de realtime | `realtime_engine/rules.md` |
| Triage de falha realtime | `realtime_engine/debug.md` |
| Bug pontual de sync | `fix_realtime` |

## RULES

- Subscription activa = 1 por proposito (regra inviolavel)
- Sempre verificar ID antes de iniciar
- DB e unica fonte de verdade (BR §1.3) — em duvida, re-fetch
- Source of truth: `.claude/.ai/business_rules.md`
