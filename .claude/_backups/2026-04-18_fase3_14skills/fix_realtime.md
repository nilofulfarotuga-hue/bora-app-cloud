---
name: fix_realtime
description: This skill should be used when the user says "SKILL: fix_realtime", or when investigating specific realtime sync bugs — data not arriving, duplicates, missing updates, wrong user receiving events, or subscription lifecycle issues.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill diagnostica problemas de sync e **propõe** fix cirúrgico — nunca aplica. O fix vai sempre à chain (decision_engine → guardian → executor). Referências a canais e notificações ancoradas em BR §22.

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
  → Realtime event emitted (orders_channel / drivers channel)
  → Flutter subscription via stream
  → UI updates
  → Push notification via FCM (BR §22.1) [se aplicável]
```

Identificar EXACTAMENTE onde quebra antes de qualquer fix.

---

## CHECKLIST DE INVESTIGAÇÃO

### 1. DRIVER ID (CRÍTICO)
- [ ] `driverId` NÃO é null
- [ ] `driverId` NÃO é string vazia
- [ ] `driverId` = `supabase.auth.currentUser!.id`
- Se inválido → **fix auth primeiro** (`fix_auth`)

### 2. CONFIGURAÇÃO DO STREAM
- [ ] Stream usa filtro correcto (`eq('current_driver_offer_id', driverId)`)
- [ ] `primaryKey` correcto (`['id']`)
- [ ] Sem stream duplicado (só 1 `StreamSubscription` activa por canal)
- [ ] Stream anterior cancelado antes de criar novo
- [ ] Canal `orders_channel` é idempotente (guard `if (_channel != null) return`)

### 3. LIFECYCLE
- [ ] Subscription cancelada em `dispose()`
- [ ] Stream não iniciado com ID null
- [ ] `onAuthStateChange` listener não cria múltiplas subscriptions

### 4. DADOS NO BACKEND
- [ ] Verificar no Supabase Dashboard se dado foi gravado
- [ ] Verificar RLS — utilizador tem acesso à row? (BR §21)
- [ ] Verificar se evento foi emitido (Supabase Realtime Logs)

### 5. NOTIFICAÇÕES PUSH (FCM — BR §22.1)
- [ ] FCM token válido na tabela respectiva?
- [ ] Edge function `notify-driver` / `notify-customer` / `notify-partner` retorna 200?
- [ ] Payload do FCM tem os campos esperados?

---

## EXEMPLOS WORKED

### Exemplo 1: Cliente não recebe notificação "driver aceitou"

**Input (contexto real):**
Cliente reporta: "Paguei o pedido mas nunca recebi notificação de que o estafeta aceitou. Abri a app manualmente e vi que já estava 'a caminho'."

**Processo:**
1. Consultar BR §22.1 → deve receber push "Estafeta a caminho" em `driverAccepted` via edge function `notify-customer`.
2. Consultar Supabase Realtime Logs → evento `UPDATE orders status=driverAccepted` foi emitido. OK.
3. Consultar logs da edge function `notify-customer` → invocação falhou com `404 registration-token-not-registered`. **ENCONTRADO.**
4. Investigar: FCM token do cliente está expirado ou inválido.
5. Hipótese 1: cliente reinstalou app sem update do token. Hipótese 2: edge function não tem retry com backoff.
6. Fix mínimo recomendado: adicionar retry 3x com backoff exponencial em `notify-customer`; se continua a falhar, marcar token como stale e pedir refresh na próxima abertura.
7. Não aplicar — delegar a chain.

**Output esperado:**
```
## FIX_REALTIME REPORT

Sintoma: cliente não recebe push "driver aceitou"
Causa-raíz: FCM registration token expirado + edge function sem retry
BR REF: §22.1 (notificações push)

Evidência:
  - Supabase Realtime Logs: UPDATE emitido OK
  - Edge function logs: 404 registration-token-not-registered
  - supabase/functions/notify-customer/index.ts:47 sem retry

Fix proposto (mínimo):
  (a) Em notify-customer: retry 3x com backoff 2^n s em caso de transient errors
  (b) Em 404 registration-token-not-registered: marcar fcm_token = NULL na tabela users
      + schedulear pedido de token refresh na próxima abertura

Handoff: decision_engine → flow_guard (toca edge function) → guardian → executor
Escopo estimado: 2 ficheiros (edge function + migration opcional de flag)
```

**Failure mode:**
Skill falha se propor "desligar o sistema de push" — isso é mudança arquitetural, delegar a `realtime_engine`. Também falha se não validar Supabase Realtime Logs primeiro — sem evidência, diagnóstico é especulativo.

---

### Exemplo 2: Driver vê o mesmo pedido em 2 telemóveis

**Input (contexto real):**
Danilo: "O estafeta João tem 2 telemóveis. Abre a app em ambos. A oferta aparece nos dois simultaneamente."

**Processo:**
1. Consultar BR §6.5 → guard anti-duplicação: "`findNextDriver` exclui drivers com oferta activa noutro pedido; `assignDriver` usa lock optimista (UPDATE com WHERE guards)".
2. Ler `supabase/functions/dispatch-engine/index.ts` (leitura, BR §25.3 zona protegida).
3. Hipótese: `findNextDriver` filtra por `driver_id` (identidade), mas ambos telemóveis partilham `driver_id`. A oferta é atribuída 1 vez, mas o realtime subscription em Flutter escuta em ambos — duplicação a nível de cliente, não de servidor.
4. Verificar `lib/stores/driver_store.dart` → canal `public:drivers` escuta `driver_id = X`. Ambos telemóveis subscrevem.
5. Fix mínimo: desambiguação por device_id. Escolha:
   - (A) Adicionar `device_id` ao token de sessão e só acordar a oferta no device mais recente
   - (B) Server-side: quando `current_driver_offer_id` é setado, push é enviado apenas para o device com token FCM mais recente
6. Recomendar (B) — toca apenas edge function, não exige mudança em DriverStore.
7. Não aplicar — delegar a chain. **NOTA:** dispatch-engine é zona protegida BR §25.3 → exige aprovação explícita do Danilo.

**Output esperado:**
```
## FIX_REALTIME REPORT

Sintoma: oferta aparece simultaneamente em 2 telemóveis do mesmo driver
Causa-raíz: subscription realtime por driver_id; guard anti-duplicação não desambigua devices
BR REF: §6.5 (guard anti-duplicação) · §22.1 (push por token FCM) · §25.3 (dispatch-engine protegido)

Evidência:
  - supabase/functions/dispatch-engine/index.ts: findNextDriver filtra por driver_id único (correcto a nível server)
  - lib/stores/driver_store.dart:subscribeToDriver — subscription aceita 2 devices do mesmo driver
  - Supabase tabela drivers: fcm_token único (mais recente); devices não rastreados individualmente

Fix proposto (mínimo, opção B):
  Em notify-driver edge function: enviar push apenas ao fcm_token mais recente (já é o comportamento,
  mas realtime channel ainda acorda ambos). Adicionar no Flutter: só mostrar diálogo se
  device_id bate com session_id activa gravada na tabela drivers.

Handoff: decision_engine → flow_guard (toca arquitetura de sessão) → refactor_guard (2+ ficheiros)
         → guardian → executor + aprovação EXPLÍCITA Danilo (BR §25.3 dispatch-engine)
```

**Failure mode:**
Skill falha se tentar corrigir no próprio dispatch-engine sem aprovação explícita — zona protegida BR §25.3 exige Danilo. Também falha se recomendar "bloquear múltiplos devices" sem perceber que é feature legítima (driver com telemóvel de backup).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/functions/notify-driver/` | Edge function de push ao estafeta (BR §22.1) |
| `supabase/functions/notify-customer/` | Edge function de push ao cliente (BR §22.1) |
| `supabase/functions/notify-partner/` | Edge function de push ao parceiro (BR §22.1) |
| `lib/stores/order_store.dart` | Canal `orders_channel` e guard idempotente |
| `lib/stores/driver_store.dart` | Canal `public:drivers` — localização driver |
| Supabase Dashboard → Realtime Logs | Evidência obrigatória — que evento foi emitido? |
| Supabase Dashboard → Edge Function Logs | Verificar invocações falhadas |
| `.claude/.ai/business_rules.md` §22 | Notificações (push FCM, som, regras) |
| `.claude/.ai/business_rules.md` §6.1 · §6.5 | Dispatch triggers + guard anti-duplicação |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — dispatch-engine entre elas |
| skill `fix_auth` | Delegar se causa-raíz for auth (driverId null) |
| skill `realtime_engine` | Delegar se mudança é de política/arquitetura |

**NOTA:** skill lê logs e código, propõe fix. Aplicação é sempre via chain.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Notification Service Monitoring" — dashboard em tempo real com FCM delivery rate, retry buckets, tokens stale. Alerta quando delivery rate cai abaixo de 98%.
>
> **Glovo** tem "Realtime Sync Watchdog" — serviço que detecta desync entre cliente e driver (timestamps divergentes, eventos em falta) e força re-sync.
>
> **iFood** usa "Event Replay" — quando um cliente reclama "não recebi", a plataforma re-emite o evento para comparar.
>
> **Bora App equivalente:** `fix_realtime` diagnostica caso-a-caso cruzando Supabase Realtime Logs + Edge Function Logs + código Flutter. Cobre as três angulações (monitoring, watchdog, replay) como análise manual ad-hoc. Evolução natural: colector remoto de métricas FCM + orders_channel lag.

---

## RESPONSABILIDADES

- ✅ Investigar bugs pontuais de sync realtime
- ✅ Propor fix mínimo com prova (file:line + log capturado)
- ✅ Garantir single-subscription, lifecycle correcto, filtro correcto
- ✅ Ancorar recomendação em BR §X quando aplicável
- ✅ Sinalizar zona protegida (BR §25.3) quando o fix toca dispatch-engine

## NÃO PODE FAZER

- ❌ Alterar política de sync ou arquitetura (delegar a `realtime_engine`)
- ❌ Modificar RLS sem `flow_guard`
- ❌ Corrigir bugs de auth (delegar a `fix_auth`)
- ❌ Modificar dispatch/tokens/pagamento
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Bug pontual de sync (subscription, canal, filtro) | **fix_realtime** (eu) |
| Política de realtime / arquitetura de channels | `realtime_engine` |
| driverId null / auth inválido | `fix_auth` |
| Rebuild excessivo causado por updates | `performance_watcher` |
| Sequência de status via realtime | `state_validator` |
| Bug específico de dispatch | `dispatch_bugfix` |

## RULES

- Investigar antes de qualquer fix (causa-raíz obrigatória)
- Prova obrigatória: file:line + log/evento capturado
- Fix mínimo — nunca refactor enquanto corrige
- Ancorar recomendação em BR §22 quando toca push / §6 quando toca dispatch triggers
- Source of truth: `.claude/.ai/business_rules.md` v2
