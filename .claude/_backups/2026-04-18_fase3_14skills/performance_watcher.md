---
name: performance_watcher
description: This skill should be used when the user says "SKILL: performance_watcher", mentions the app is slow, battery draining, excessive API calls, unnecessary rebuilds, or asks for performance analysis.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill detecta problemas de performance e **propõe** fix — nunca aplica. O fix proposto é delegado à chain (decision_engine → guardian → executor). Ancora recomendações em BR §X quando a área está travada.

# PERFORMANCE WATCHER — RESOURCE ANALYSER

## ROLE
Analyses the app for performance issues, excessive resource usage, and battery drain.

Does NOT change code.
Identifies issues and suggests optimisations.

---

## OBJECTIVE

Ensure the app runs efficiently on low-end devices (target: 4 GB RAM Android).

---

## ANALYSIS AREAS

### GPS & LOCATION (ver BR §7.2)
- [ ] `distanceFilter` setado? (5 m delivery, 10 m idle)
- [ ] `intervalDuration` em Android? (3 s delivery, 5 s idle)
- [ ] `enableWakeLock: true` só quando driver está em entrega activa?
- [ ] Subscription cancelada quando screen dispose?
- [ ] `getLastKnownPosition()` para evitar bloqueio no primeiro fix?

### WIDGET REBUILDS
- [ ] `context.watch<T>()` só em widgets que precisam rebuild?
- [ ] Widgets pesados usando `context.read<T>()` em vez de `watch`?
- [ ] Listas usando `const` constructors onde possível?
- [ ] `addPostFrameCallback` não acumulando em cada build?
- [ ] `Selector<T, R>` preferido a `Consumer<T>` quando só parte do state rebuilda?

### SUPABASE / NETWORK (ver BR §22)
- [ ] Realtime subscriptions: só 1 activa por canal? (BR §22 e guard `orders_channel`)
- [ ] RPC calls debounced quando apropriado?
- [ ] Token balance não refrescado em cada frame (BR §4)?
- [ ] Order list não re-fetched desnecessariamente (BR §8.5)?

### MAPS (ver BR §7.2)
- [ ] Animações de câmara: 10 m jitter threshold enforced?
- [ ] Recálculo de rota: 2.5 s debounce timer activo?
- [ ] Markers: não rebuilt em cada update de posição (só quando stops mudam)?
- [ ] Bearing update: não mais frequente que a cada 500 ms?

### MEMORY
- [ ] `StreamSubscription` sempre cancelada em `dispose()`?
- [ ] `Timer` sempre cancelado em `dispose()`?
- [ ] `GoogleMapController` completer não leaked?
- [ ] Listas grandes não retidas em widget state desnecessariamente?

---

## SEVERITY LEVELS

| Level | Meaning |
|---|---|
| 🔴 CRÍTICO | Causa crashes, ANR, ou drain severo |
| 🟡 ALTO | Impacto notável em performance ou bateria |
| 🟢 MÉDIO | Desperdício sem impacto visível ao utilizador |
| ⚪ BAIXO | Oportunidade de optimização menor |

---

## OUTPUT FORMAT

```
## PERFORMANCE REPORT

### 🔴 CRITICAL
- <issue>: <file:line> — <impact> (BR §X se aplicável)

### 🟡 HIGH
- <issue>: <file:line> — <recommendation>

### 🟢 MEDIUM
- <issue>: <suggestion>

### SUMMARY
Total issues: X
Estimated battery impact: HIGH / MEDIUM / LOW
Recommendation: <priority fixes>
Handoff: decision_engine → guardian → executor (por ordem de prioridade)
```

---

## EXEMPLOS WORKED

### Exemplo 1: Tab "Pedidos" demora >2 s a carregar

**Input (contexto real):**
Danilo: "Quando o cliente abre a tab Pedidos, demora 2–3 s com spinner. Antes era instantâneo."

**Processo:**
1. Ler `lib/screens/orders_screen.dart` e `lib/stores/order_store.dart`.
2. Grep `context.watch<OrderStore>()` → aparece no topo do `build()` do `OrdersScreen`. Qualquer update em qualquer order (UPDATE realtime) dispara rebuild completo da lista.
3. Cruzar com BR §8.5 — comportamento esperado: "Tab Pedidos carrega imediatamente ao abrir (com spinner)". Spinner é aceitável, mas >2 s é degradação.
4. Hipótese: `context.watch` é demasiado amplo. Listagem só depende de `orders.length` + `orders.status` por item, não de todo o objecto.
5. Recomendação: substituir por `Selector<OrderStore, List<OrderStatusSummary>>` que só rebuilda quando a projecção muda.
6. Não aplicar — delegar a `decision_engine → guardian → executor`.

**Output esperado:**
```
## PERFORMANCE REPORT

🟡 HIGH
- Tab Pedidos rebuild completo em cada UPDATE realtime
  → lib/screens/orders_screen.dart:42 (context.watch<OrderStore>())
  → Impacto: 50+ rebuilds/minuto em pico (UPDATE broadcasts), spinner >2 s (BR §8.5)
  Recomendação: trocar para Selector<OrderStore, List<(String id, OrderStatus status)>>
  → rebuild só quando a tupla muda, não quando campos irrelevantes mudam.

SUMMARY
Total issues: 1
Estimated battery impact: MEDIUM (rebuilds excessivos → CPU spikes)
Handoff: decision_engine → guardian → executor
```

**Failure mode:**
Performance_watcher falha se aplicar o fix directamente (viola read-only). Também falha se recomendar sem medir impacto — "parece lento" não é evidência; preciso ancorar em observação (tempo, frequência de rebuild, ou BR §8.5).

---

### Exemplo 2: GPS do driver drena bateria

**Input (contexto real):**
Driver reporta: "Bateria cai 30% em 2 horas de trabalho, mesmo parado."

**Processo:**
1. Ler `lib/services/location_service.dart` (se existir) e `lib/screens/driver_map_screen.dart`.
2. Grep `Geolocator.getPositionStream` → duas inscrições activas: uma em `LocationService`, outra directa no `driver_map_screen.dart`. **Duplicação**.
3. Cruzar com BR §7.2 — mapa do estafeta deve ter marcador único com bearing; não exige dois streams.
4. Verificar `distanceFilter`: no driver_map_screen está a 1 m. Em BR §7.2 sensato é 5 m em delivery, 10 m idle.
5. Recomendação: consolidar numa única subscription em `LocationService`; ajustar `distanceFilter` para 5 m/10 m conforme modo.
6. Não aplicar — delegar a chain.

**Output esperado:**
```
## PERFORMANCE REPORT

🔴 CRITICAL
- GPS stream duplicado a 1 m distanceFilter
  → lib/services/location_service.dart:28 (stream 1)
  → lib/screens/driver_map_screen.dart:156 (stream 2, duplicado)
  → Impacto: bateria 30% em 2h (baseline ~10% sem duplicação)
  Recomendação (2 passos):
    (a) Manter apenas stream em LocationService
    (b) Ajustar distanceFilter para 5 m delivery / 10 m idle (BR §7.2 conforme)

SUMMARY
Total issues: 1 (crítico)
Estimated battery impact: HIGH
Handoff: refactor_guard → decision_engine → guardian → executor
(precisa refactor_guard porque toca 2+ ficheiros)
```

**Failure mode:**
Performance_watcher falha se esquecer de cruzar com BR §7.2 — a distância é aceitável, mas duplicação é sempre gaspillage. Também falha se recomendar refactor sem sinalizar que precisa `refactor_guard` (2+ ficheiros = gate obrigatório).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/` (qualquer ecrã lento) | Análise de rebuilds, `watch` vs `read`, `Selector` |
| `lib/services/location_service.dart` | GPS — `distanceFilter`, `intervalDuration`, wake lock |
| `lib/stores/` | Provider/ChangeNotifier — debouncing, batch updates |
| `lib/screens/driver_map_screen.dart` | Camera animations, polyline recompute |
| `.claude/.ai/business_rules.md` §7.2 | Regras do mapa do estafeta |
| `.claude/.ai/business_rules.md` §8.5 | Tab Pedidos — carrega imediatamente com spinner |
| `.claude/.ai/business_rules.md` §22 | Notificações — não abusar de FCM deliveries |
| Flutter DevTools Timeline / Memory | Tooling externo para medir antes de recomendar |
| skill `decision_engine` | Delegatário após propor fix |
| skill `refactor_guard` | Escalar quando fix toca 2+ ficheiros |
| skill `map_master` | Colaborar em performance específica de mapa |

**NOTA:** skill apenas lê e recomenda. Aplicação do fix passa pela chain (decision_engine → guardian → executor).

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** define "Performance Budget" por ecrã — LCP, FID, número de rebuilds aceitável. Violação do budget dispara alerta para equipa.
>
> **iFood** usa "Perf Dashboard" com alertas automáticos — cada ecrã tem SLA de ms, excedidos reportam ao owner.
>
> **Glovo** tem "Battery Profile" — monitoriza drain por role (driver, customer, partner) e compara contra baseline semanal.
>
> **Bora App equivalente:** `performance_watcher` corre análise estática + cross-reference com BR §7.2 (mapa), §8.5 (UX) e produz relatório priorizado. Sem dashboard permanente, mas cobre os 3 ângulos: rebuilds (Uber), SLA de ecrã (iFood), bateria (Glovo). Pode ser estendido no futuro com coleta remota.

---

## RESPONSABILIDADES

- ✅ Analisar GPS waste, widget rebuilds excessivos, leaks de stream/timer, uso de rede
- ✅ Produzir relatório priorizado por severidade (🔴/🟡/🟢/⚪)
- ✅ Sugerir optimizações específicas (file:line)
- ✅ Ancorar recomendações em BR §X quando aplicável

## NÃO PODE FAZER

- ❌ Corrigir bugs (delegar à chain decision_engine → guardian → executor)
- ❌ Executar profiler ou rodar testes em runtime (análise estática apenas)
- ❌ Alterar arquitetura (delegar a `flow_guard`)
- ❌ Modificar `business_rules.md`
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| GPS waste, rebuilds, leaks, rede | **performance_watcher** (eu) |
| Corrigir bug de performance | `decision_engine → guardian → executor` |
| Interpolação de marcador (perf de mapa) | `map_master` |
| Rebuild causado por realtime | `realtime_engine` + `fix_realtime` |
| Refactor >3 ficheiros | `refactor_guard` |

## RULES

- Apenas analisa — nunca corrige
- Severidade baseada em impacto real (tempo medido, frequência, bateria)
- Nomear arquivo + linha onde possível
- Cruzar com BR §X quando área tem regra travada
- Source of truth: `.claude/.ai/business_rules.md` v2
