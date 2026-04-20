---
name: dispatch_bugfix
description: This skill should be used when the user says "SKILL: dispatch_bugfix", or when investigating a SPECIFIC bug in the existing dispatch system (broadcast leak, current_driver_offer_id null, multiple drivers receiving, redispatch loop). Bug-fixer only — never implements new dispatch rules (those belong to dispatch_manager).
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill investiga bugs de dispatch e **propõe** fix cirúrgico — nunca aplica. O fix vai à chain (decision_engine → flow_guard → guardian → executor). **CRÍTICO:** dispatch-engine v31 (`supabase/functions/dispatch-engine/index.ts`) e `driver_capacity_service.dart` são zona protegida BR §25.3 — qualquer fix exige aprovação explícita do Danilo.

# DISPATCH BUGFIX — INCIDENT INVESTIGATOR

## ROLE
Investigates and corrects pontual bugs in the existing sequential dispatch implementation. Never implements new business rules — only fixes regressions and incidents.

For new rules, delegate to `dispatch_manager`.

---

## OBJECTIVE

Identify root cause of a dispatch incident with concrete evidence and propose a minimal, targeted fix that does not change the dispatch architecture.

---

## SCOPE

✅ **In scope** — investigação/fix de bug para:
- Broadcast leak (múltiplos drivers recebendo mesma oferta)
- `current_driver_offer_id` null quando deveria estar setado (BR §6.5)
- Lock optimista a falhar
- Redispatch loop / double-dispatch
- `tried_driver_ids` não respeitado
- Offer expiry race (40 s — BR §6.3)
- Status preso em `callingDriver`
- Pedidos não atribuídos apesar de drivers online

❌ **Out of scope** (delegate a `dispatch_manager`):
- Implementar nova fila local 200m/5s
- Implementar nova capacidade
- Implementar nova prioridade in-store
- Implementar monitor SLA
- Implementar novo critério de batching
- Adicionar novas constantes (BR §25.2 é travada)

---

## REGRAS CRÍTICAS (do business_rules.md — INVIOLÁVEIS)

- Sequential dispatch — NUNCA broadcast (BR §6.2 · §7.1)
- FIFO geográfico puro na fila local — sem ranking (BR §6.2)
- `current_driver_offer_id` deve estar setado antes de status mudar para `callingDriver` (BR §6.5)
- Optimistic locking obrigatório nos UPDATEs (BR §6.5)
- Constantes travadas (BR §25.2):
  - `OFFER_TIMEOUT_SECONDS = 40`
  - `MAX_ORDERS_PER_DRIVER = 3`
  - `FIFO_RADIUS_KM = 0.2` (200 m)
  - `BATCHING_RADIUS_KM = 3.0` (3 km)
  - `SLA_CHECK_MINUTES = 7`
  - `PREFERRED_RADIUS_KM = 10`

---

## INVESTIGAÇÃO (OBRIGATÓRIA ANTES DE QUALQUER FIX)

### Passo 1 — Reproduzir
- [ ] Logs Supabase Edge Function `dispatch-engine` no momento do bug
- [ ] Estado do pedido afectado (status, `current_driver_offer_id`, `tried_driver_ids`, `driver_offer_expires_at`)
- [ ] Quantos drivers receberam (deveria ser 1 — BR §7.1)
- [ ] Timing: coincide com pg_cron (cada minuto, BR §6.1)? Coincide com segunda 03h (pg_cron + bora_weekly_auto_payout, BR §3.4 + padrão detectado por learning_engine)?

### Passo 2 — Localizar causa
- [ ] Onde drivers são seleccionados? (`dispatch-engine/index.ts`)
- [ ] Onde `current_driver_offer_id` é definido?
- [ ] Por que o lock optimista não bloqueou?
- [ ] `tried_driver_ids` foi actualizado?

### Passo 3 — Provar
Para cada erro encontrado, registar:
- Ficheiro + linha
- Trecho de código problemático
- Por que produz o sintoma observado

---

## CHECKLIST DE FIX

Antes de aprovar correcção:

- [ ] Fix é mínimo (1 função / 1 query / 1 condição)
- [ ] Não introduz broadcast (BR §7.1)
- [ ] Mantém optimistic lock (BR §6.5)
- [ ] `current_driver_offer_id` continua setado antes de `callingDriver` (BR §6.5)
- [ ] Não toca em fila local / capacidade / SLA (escopo de `dispatch_manager`)
- [ ] Não altera constantes BR §25.2
- [ ] Logs adicionados para confirmar cura
- [ ] Reprodução do bug deixa de acontecer
- [ ] **Aprovação explícita Danilo** (zona protegida BR §25.3)

---

## EXEMPLOS WORKED

### Exemplo 1: Oferta aparece a 2 drivers simultaneamente

**Input (contexto real):**
Incidente reportado: "Fiz um pedido e 2 drivers ligaram-me em 5 s a dizer que aceitaram". Logs Supabase mostram 2 UPDATEs em `orders.assigned_driver_id` com 200 ms de diferença.

**Processo:**
1. Consultar BR §6.5 — "`findNextDriver` exclui drivers com oferta activa; `assignDriver` usa lock optimista (UPDATE com WHERE guards)".
2. Ler `supabase/functions/dispatch-engine/index.ts` (leitura, BR §25.3 zona protegida).
3. Hipótese: dois triggers acordaram `dispatch-engine` em paralelo (pg_cron + evento de status change). Se `assignDriver` não tem `WHERE current_driver_offer_id IS NULL`, race condition ocorre.
4. Verificar UPDATE em `assignDriver`:
   ```
   UPDATE orders SET assigned_driver_id = $1
   WHERE id = $2
   ```
   **ENCONTRADO** — falta `AND assigned_driver_id IS NULL`.
5. Fix mínimo: adicionar cláusula ao UPDATE. Só 1 UPDATE ganha a race.
6. Validar cura: reproduzir simulando 2 invocações paralelas → apenas 1 assign deve ter sucesso; o outro retorna `rowCount: 0` e o driver-2 é devolvido à fila.

**Output esperado:**
```
## DISPATCH_BUGFIX REPORT

Sintoma: 2 drivers aceitaram o mesmo pedido em 200 ms
Causa-raíz: race em assignDriver — UPDATE sem guard
BR REF: §6.5 (guard anti-duplicação) · §7.1 (1 diálogo de cada vez) · §25.3 (dispatch-engine protegido)

Evidência:
  - Supabase logs: 2 UPDATEs simultâneos em orders.assigned_driver_id
  - supabase/functions/dispatch-engine/index.ts:134 assignDriver:
      UPDATE orders SET assigned_driver_id = $1 WHERE id = $2
    (falta guard AND assigned_driver_id IS NULL)

Fix proposto (mínimo):
  supabase/functions/dispatch-engine/index.ts:134
    UPDATE orders
       SET assigned_driver_id = $1,
           current_driver_offer_id = $1,
           status = 'callingDriver'
     WHERE id = $2
+      AND assigned_driver_id IS NULL
+      AND status = 'preparing'

  Se rowCount = 0 → devolver driver à fila e tentar próximo.

Handoff: decision_engine → flow_guard (zona arquitetural) → guardian → executor
         + APROVAÇÃO EXPLÍCITA DANILO (BR §25.3 dispatch-engine)

Validação pós-fix:
  - Simular 2 invocações paralelas → apenas 1 UPDATE bem-sucedido
  - Confirmar em logs Supabase que rowCount = 0 aparece para o "perdedor"
  - system_validator corre smoke test FSM BR §1.3
```

**Failure mode:**
Skill falha se propor fix no cliente Flutter — a race é server-side; cliente não pode corrigir. Também falha se esquecer `AND status = 'preparing'` — sem isso, UPDATE pode roubar pedidos já `callingDriver`. Falha crítica se aplicar sem aprovação Danilo (zona protegida BR §25.3).

---

### Exemplo 2: Pedido fica "callingDriver" para sempre

**Input (contexto real):**
Um pedido do Carlos ficou em `callingDriver` durante 30 min. Drivers online suficientes (5 activos). Manualmente cliente cancelou e refez.

**Processo:**
1. Consultar BR §6.2 — algoritmo de selecção. Se todos tried → reset do ciclo.
2. Consultar BR §6.3 — timeout 40 s por oferta. Se todos recusam → próximo ciclo.
3. Consultar logs: `tried_driver_ids` cresceu até 5 drivers (todos recusaram). Depois nada mais aconteceu.
4. Ler lógica de reset em `dispatch-engine/index.ts`. **ENCONTRADO**: após `tried_driver_ids.length === total_online_drivers`, deveria resetar e esperar 60 s antes de retentar. Condição existe, mas após reset o pedido não foi re-enfileirado na pg_cron.
5. Fix mínimo: garantir que reset também actualiza `orders.status = 'callingDriver'` e `driver_offer_expires_at = NOW() + 60s` para forçar re-acordar no próximo tick pg_cron.

**Output esperado:**
```
## DISPATCH_BUGFIX REPORT

Sintoma: pedido preso em callingDriver 30 min, apesar de 5 drivers online
Causa-raíz: reset de tried_driver_ids não re-enfileira pedido na próxima pg_cron tick
BR REF: §6.1 (pg_cron + eventos) · §6.2 (algoritmo) · §6.3 (timeout 40s) · §25.3 (protegido)

Evidência:
  - Logs: tried_driver_ids cresceu a 5, reset acontece aos 3 min, depois silêncio
  - supabase/functions/dispatch-engine/index.ts:245 reset section:
      UPDATE orders SET tried_driver_ids = '{}' WHERE id = $1
    (não actualiza status nem expires_at → pg_cron skippa)

Fix proposto (mínimo):
  supabase/functions/dispatch-engine/index.ts:245
    UPDATE orders
       SET tried_driver_ids = '{}',
+          status = 'callingDriver',
+          driver_offer_expires_at = NOW() + INTERVAL '60 seconds'
     WHERE id = $1;

  Assim, próximo tick pg_cron re-processa o pedido naturalmente.

Handoff: decision_engine → flow_guard → guardian → executor
         + APROVAÇÃO EXPLÍCITA DANILO (BR §25.3)

Validação pós-fix:
  - Reproduzir: forçar 5 recusas consecutivas, confirmar reset + re-enfileiramento
  - system_validator corre smoke test
  - Monitorar incidência por 1 semana (learning_engine)
```

**Failure mode:**
Skill falha se sugerir "aumentar retry" ou "adicionar broadcast de fallback" — ambos violam BR §6 e §7.1. Também falha se não validar com learning_engine após fix — o padrão pode repetir-se por outra causa.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `supabase/functions/dispatch-engine/index.ts` | **Zona protegida BR §25.3** — apenas leitura; fix via chain + aprovação |
| `lib/dispatch/driver_capacity_service.dart` | **Zona protegida BR §25.3** — apenas leitura |
| `lib/dispatch/dispatch_engine.dart` | Lógica client-side (memory-based) |
| `lib/stores/order_store.dart` — método `finalizePurchase` | **Zona protegida BR §25.3** |
| Supabase Dashboard → Edge Function Logs | Evidência obrigatória de qualquer incidente |
| Supabase Dashboard → Database Logs | UPDATEs concorrentes, race conditions |
| `.claude/.ai/business_rules.md` §6 completa | Dispatch policy — inviolável |
| `.claude/.ai/business_rules.md` §6.5 | Guard anti-duplicação + lock optimista |
| `.claude/.ai/business_rules.md` §7.1 | 1 diálogo de cada vez |
| `.claude/.ai/business_rules.md` §25.2 | Constantes travadas — nunca alterar |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — exigem aprovação Danilo |
| skill `dispatch_manager` | Delegar se causa é "falta feature" (não bug) |
| skill `fix_realtime` | Delegar se causa é sync (não dispatch logic) |
| skill `learning_engine` | Cruzar com padrões temporais conhecidos |

**NOTA:** skill lê e propõe. Toda alteração em dispatch-engine exige aprovação EXPLÍCITA Danilo (BR §25.3).

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Matching Bug Triage" — equipa dedicada de engenheiros especializados em incidentes de matching driver↔rider. Runbook formal por tipo de incidente.
>
> **iFood** mantém "Dispatch Incident Playbook" — documento versionado com 20+ cenários comuns e fix templates.
>
> **Glovo** tem "Matching Health Dashboard" — métricas em tempo real (dispatch latency, acceptance rate, tried drivers before assign) com alertas automáticos.
>
> **Bora App equivalente:** `dispatch_bugfix` é playbook + runbook + triagem num único skill. Combina matriz de causas-raíz com ancoragem obrigatória em BR §6 / §25.2 / §25.3. Cobre os três gigantes com proteção extra (aprovação explícita Danilo) por ser zona crítica.

---

## RESPONSABILIDADES

- ✅ Investigar incidentes pontuais de dispatch
- ✅ Propor fixes cirúrgicos com prova (file:line + logs)
- ✅ Garantir que o fix não viola regras críticas BR §6
- ✅ Ancorar cada diagnóstico em BR §X
- ✅ Sinalizar zona protegida BR §25.3 — exige aprovação Danilo

## NÃO PODE FAZER

- ❌ Implementar novas regras de negócio (delegar a `dispatch_manager`)
- ❌ Refactor arquitetural do dispatch (delegar a `flow_guard` + `refactor_guard`)
- ❌ Modificar constantes da BR §25.2
- ❌ Tocar em pagamento / tokens / estados / realtime
- ❌ Adicionar fila local / SLA monitor (são features, não bugs)
- ❌ Aplicar fix sem aprovação Danilo (BR §25.3)
- ❌ Modificar ficheiros (é read-only)

---

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Bug pontual de dispatch | **dispatch_bugfix** (eu) |
| Novas regras de dispatch | `dispatch_manager` |
| Refactor arquitetural | `flow_guard` + `refactor_guard` |
| Sequência de estados | `state_validator` |
| Pagamento | `payment_manager` |
| Tokens | `token_manager` |
| Sync realtime | `fix_realtime` / `realtime_engine` |
| Auth (driverId null) | `fix_auth` |

---

## RULES

- Bug-fixer ONLY. Não é feature implementer.
- Toda correcção precisa de prova (file:line + log Supabase)
- Dispatch-engine + driver_capacity_service = zona protegida BR §25.3 — aprovação Danilo obrigatória
- Ancorar cada proposta em BR §6 / §25.2 / §25.3
- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md` v2
- Em conflito → BR vence
