---
name: system_validator
description: This skill should be used when the user says "SKILL: system_validator", asks to validate the full system, verify the complete order flow end-to-end, check tokens and pricing consistency, or confirm everything works after a large change.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill corre `dart analyze`, smoke tests e verificações de schema — nunca modifica código, nunca escreve no banco. Se detecta problema, delega correcção à skill especialista (fix_realtime/fix_auth/dispatch_bugfix) e reporta.

# SYSTEM VALIDATOR — FULL SYSTEM HEALTH CHECK

## ROLE
Validates the complete bora_app system end-to-end.

Does NOT change code.
Only validates and reports.

Runs IMMEDIATELY after `executor`, before `memory`.

---

## OBJECTIVE

Confirm that all major systems are consistent and functional after any significant change.

---

## VALIDATION SCOPE

### 1. ORDER FLOW (ver BR §1.3)
- [ ] `created` → dispatch triggers imediatamente
- [ ] `callingDriver` → exactamente 1 driver recebe oferta (BR §7.1)
- [ ] Offer timeout 40 s (BR §6.3) → redispatch para próximo driver
- [ ] `driverAccepted` → cliente notificado (BR §22.1)
- [ ] `pickedUp` → entrega em progresso
- [ ] `delivered` → código 4 dígitos validado, tokens atribuídos (BR §4.2 · §4.4)
- [ ] Delivery code: 4-digit, validated before status advance (BR §7.3)

### 2. DISPATCH ENGINE (ver BR §6)
- [ ] `current_driver_offer_id` set antes de status change (BR §6.5)
- [ ] No broadcast para múltiplos drivers (BR §6.2 · §7.1)
- [ ] `driver_offer_history` previne re-offer ao mesmo driver (BR §6.3)
- [ ] `driver_offer_expires_at` timeout funciona (40 s — BR §6.3)
- [ ] `MAX_ORDERS_PER_DRIVER = 3` respeitado (BR §6.4 · §25.2)
- [ ] `FIFO_RADIUS_KM = 0.2` (200 m) fixo (BR §6.2 · §25.2)

### 3. TOKENS SYSTEM (ver BR §4)
- [ ] `bora_tokens` table existe (BR §4.4 · §25.3 zona protegida)
- [ ] `add_tokens()` RPC: +40/entrega driver (BR §4.2), `ON CONFLICT DO NOTHING`
- [ ] `get_user_tokens()` RPC: soma activos e não-expirados (60 dias — BR §4.1)
- [ ] `consume_tokens()` RPC: FIFO (BR §4.1), split remainder, race-safe
- [ ] Trigger `trg_award_tokens_on_delivery` dispara em `delivered` (BR §4.4 · §25.3)
- [ ] Teto desconto cliente: até 50% do valor do pedido (BR §4.3)
- [ ] Conversão: 100 tokens = €0,50 (BR §4.1)

### 4. PRICING (ver BR §2 · §5)
- [ ] Parceiro: markup 10+5+5% aplicado (BR §2.4)
- [ ] Não-parceiro: markup +15% invisível (BR §2.4)
- [ ] Taxa entrega €2,50 até 4 km; +€0,50/km acima (BR §2.1)
- [ ] Apartment surcharge +€1,50 (€1 driver · €0,50 Bora) (BR §2.3)
- [ ] Driver earnings: base €3,80 + €0,20/km + €0,80 taxa + €3 parceiro (BR §5.1)
- [ ] Saco restaurante €0,30; saco mercado €0,10/saco (BR §2.5)
- [ ] Limite dinheiro €40 (BR §3.2)

### 5. GPS & MAPS (ver BR §7.2)
- [ ] Map nunca abre em Lisboa (GPS-first guard activo)
- [ ] Driver map segue posição em real-time com bearing
- [ ] Background tracking activo (foreground service Android)
- [ ] Permission flow trata denied/deniedForever com snackbar

### 6. AUTH (ver BR §21)
- [ ] `driverId` = `auth.currentUser.id` (UUID, não mocked)
- [ ] Session persiste across app restart
- [ ] No guest session no driver flow
- [ ] RLS policies activas em `orders`, `drivers`, `driver_transactions`, `reservations` (BR §21.1–§21.4)

### 7. CODE QUALITY
- [ ] `dart analyze` retorna 0 erros, 0 warnings
- [ ] No `use_build_context_synchronously` nas mudanças
- [ ] No `unused_field` / `unused_local_variable` nas mudanças

---

## OUTPUT FORMAT

```
## SYSTEM VALIDATION REPORT

### ✅ PASSING
- <system>: <reason> (BR §X)

### ❌ FAILING
- <system>: <problem> → <file/line if known> (BR §X)

### ⚠️ WARNINGS
- <system>: <concern>

### VERDICT
SYSTEM HEALTHY ✅ / ISSUES FOUND ❌

### HANDOFF
- If HEALTHY → memory (regista mudança)
- If ISSUES → skill especialista (fix_realtime | fix_auth | dispatch_bugfix | …)
```

---

## EXEMPLOS WORKED

### Exemplo 1: Após executor aplicar patch em `order_store.dart`

**Input (contexto real):**
Executor acabou de aplicar patch no `_advanceStatus` — adicionou try/catch em chamada Supabase. Chain termina em system_validator. Alvo: confirmar que FSM BR §1.3 continua intacta e `dart analyze` passa.

**Processo:**
1. Corrida `dart analyze` sobre o projecto completo. Esperado: 0 erros, 0 warnings.
2. Smoke test: simular criação de pedido dummy em staging. Verificar que passa por todos os status BR §1.3 (`created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered`).
3. Verificar `current_driver_offer_id` setado antes de `callingDriver` (BR §6.5).
4. Verificar que `trg_award_tokens_on_delivery` disparou em `delivered` (BR §4.4).
5. Verificar que realtime channel `orders_channel` propagou UPDATE (BR §22).

**Output esperado (happy path):**
```
## SYSTEM VALIDATION REPORT

✅ PASSING
- Order flow: sequência BR §1.3 respeitada em smoke test
- Dispatch: current_driver_offer_id setado correctamente (BR §6.5)
- Tokens: +40 atribuídos ao driver em delivered (BR §4.2)
- Realtime: UPDATE propagado em orders_channel (BR §22)
- Code quality: dart analyze 0 erros

VERDICT: SYSTEM HEALTHY ✅
HANDOFF: memory (registar fix do mounted guard)
```

**Output esperado (unhappy path — falha):**
```
## SYSTEM VALIDATION REPORT

❌ FAILING
- Order flow: smoke test paralisou em `callingDriver` por 60 s (BR §1.3)
  → lib/stores/order_store.dart:312 (try/catch silenciou erro)

VERDICT: ISSUES FOUND ❌
HANDOFF: dispatch_bugfix (analisar porque dispatch não acionou)
         Recomendação paralela: reverter via git se staging estiver comprometido
```

**Failure mode:**
A skill falha se reportar "HEALTHY" sem correr `dart analyze` ou sem validar a FSM inteira. Também falha se tentar corrigir (ex: reeditar o ficheiro) — o papel é reportar, não corrigir.

---

### Exemplo 2: Após executor criar migration SQL

**Input (contexto real):**
Executor criou `supabase/migrations/20260417120000_add_orders_delivery_code_index.sql` com `CREATE INDEX IF NOT EXISTS`. Chain chega a system_validator. Alvo: validar que schema bate com BR §21 (RLS) e §1.3 (orders status).

**Processo:**
1. Correr migration em staging (via supabase CLI, modo dry-run primeiro).
2. Validar schema: index criado, tabela `orders` intacta, RLS policies preservadas (BR §21.1).
3. Verificar que `orders.delivery_code` continua presente (BR §7.3 depende).
4. Smoke test de SELECT com filtro `delivery_code = '1234'` — confirmar que usa o novo índice (EXPLAIN ANALYZE).
5. Se OK em staging → autorizar produção. Se falha → reverter migration.

**Output esperado:**
```
## SYSTEM VALIDATION REPORT

✅ PASSING
- Migration aplicada em staging sem erros
- Schema orders intacto, delivery_code presente (BR §7.3)
- RLS policies preservadas (BR §21.1)
- Index activo — EXPLAIN mostra Index Scan em vez de Seq Scan

✅ ADDITIONAL CHECKS
- Nenhum ALTER TABLE destrutivo detectado
- Nenhum DROP detectado

VERDICT: SYSTEM HEALTHY ✅ (staging)
HANDOFF: memory — registar migration + autorizar rollout produção
         NOTA: produção deve esperar janela de manutenção se tabela grande
```

**Failure mode:**
A skill falha se não correr migration em staging primeiro — aplicar directo em produção viola BR §25 (configurações técnicas) e pode deixar a app offline. Também falha se reportar HEALTHY sem verificar RLS (migration pode ter quebrado policy invisível).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/**/*.dart` | Alvo de validação pós-exec (apenas leitura) |
| `supabase/migrations/*.sql` | Novas migrations — validar em staging |
| `.claude/.ai/business_rules.md` §1.3 | Sequência imutável — validar sempre após exec |
| `.claude/.ai/business_rules.md` §6 | Dispatch integrity checks |
| `.claude/.ai/business_rules.md` §4 | Tokens — validar atribuição correcta |
| `.claude/.ai/business_rules.md` §21 | RLS policies por tabela |
| `.claude/.ai/business_rules.md` §22 | Notificações — validar FCM delivery |
| `.claude/.ai/business_rules.md` §25.2 | Constantes dispatch-engine — nunca devem divergir após exec |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — validar que não foram alteradas indevidamente |
| Comandos read-only: `dart analyze`, `flutter test --no-sound-null-safety`, `psql EXPLAIN` | Tooling de validação |
| skill `state_validator` | Delegar validação fina de transições FSM |
| skill `memory` | Handoff pós-PASS (registar mudança) |
| skill `fix_realtime` / `fix_auth` / `dispatch_bugfix` | Handoff pós-FAIL (delegar correcção) |

**NOTA:** skill lê ficheiros e corre tooling externo (dart analyze, flutter test). Nunca modifica código nem banco.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Canary Validation Pipeline" — após deploy, roda smoke tests automáticos em 1% do tráfego antes de rollout total. Health metrics em tempo real decidem promover ou reverter.
>
> **iFood** usa "Post-Deploy Health Check" obrigatório — cada PR merged dispara suite de validações end-to-end contra staging; falha → rollback automático.
>
> **Glovo** tem "Release Gates" — cada gate (lint, test, staging, canary, produção) exige sinal verde antes de avançar.
>
> **Bora App equivalente:** `system_validator` corre `dart analyze` + smoke test de fluxo BR §1.3 + validação de schema após cada exec. Handoff a `memory` apenas se PASS. Cobre o papel dos três num único gate, com escape hatch para skills especialistas em caso de FAIL.

---

## RESPONSABILIDADES

- ✅ Validar sistema completo pós-execução (order flow, dispatch, tokens, GPS, auth, code quality)
- ✅ Produzir relatório PASSING / FAILING / WARNINGS com localização e BR §X
- ✅ Ser a última skill chamada em qualquer chain de execução (antes de `memory`)
- ✅ Delegar correcções a skills especialistas (fix_*) quando detecta FAIL

## NÃO PODE FAZER

- ❌ Corrigir bugs (apenas reporta — delegar a skill especialista)
- ❌ Validar sequência fina de status (delegar a `state_validator`)
- ❌ Modificar `business_rules.md`
- ❌ Modificar código ou banco (é read-only)
- ❌ Reverter migration sem aprovação explícita (propor, não executar)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Health check geral pós-execução | **system_validator** (eu) |
| Sequência imutável de status | `state_validator` |
| Análise de performance | `performance_watcher` |
| Bug específico de realtime | `fix_realtime` |
| Bug específico de auth | `fix_auth` |
| Bug específico de dispatch | `dispatch_bugfix` |

## RULES

- Apenas valida — nunca corrige
- Sempre a última skill da chain (antes de `memory`)
- Veredicto explícito: SYSTEM HEALTHY ✅ ou ISSUES FOUND ❌
- Todo FAIL cita BR §X + file:line quando possível
- Source of truth: `.claude/.ai/business_rules.md` v2
