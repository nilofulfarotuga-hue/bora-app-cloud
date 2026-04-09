---
name: performance_watcher
description: This skill should be used when the user says "SKILL: performance_watcher", mentions the app is slow, battery draining, excessive API calls, unnecessary rebuilds, or asks for performance analysis.
version: 1.0.0
---

# PERFORMANCE WATCHER — RESOURCE ANALYSER

## ROLE
Analyses the app for performance issues, excessive resource usage, and battery drain.

Does NOT change code.
Identifies issues and suggests optimisations.

---

## OBJECTIVE

Ensure the app runs efficiently on low-end devices (target: 4GB RAM Android).

---

## ANALYSIS AREAS

### GPS & LOCATION
- [ ] `distanceFilter` set? (5m delivery, 10m idle)
- [ ] `intervalDuration` set on Android? (3s delivery, 5s idle)
- [ ] `enableWakeLock: true` only when driver is actively delivering?
- [ ] Subscription cancelled when screen is disposed?
- [ ] `getLastKnownPosition()` used to avoid blocking on first fix?

### WIDGET REBUILDS
- [ ] `context.watch<T>()` only in widgets that need to rebuild?
- [ ] Heavy widgets using `context.read<T>()` instead?
- [ ] Lists using `const` constructors where possible?
- [ ] `addPostFrameCallback` not accumulating on every build?

### SUPABASE / NETWORK
- [ ] Realtime subscriptions: only 1 active per channel?
- [ ] RPC calls debounced where appropriate?
- [ ] Token balance not refreshed on every frame?
- [ ] Order list not re-fetched unnecessarily?

### MAPS
- [ ] Camera animations: 10m jitter threshold enforced?
- [ ] Route recalculation: 2.5s debounce timer active?
- [ ] Markers: not rebuilt on every position update (only when stops change)?

### MEMORY
- [ ] `StreamSubscription` always cancelled in `dispose()`?
- [ ] `Timer` always cancelled in `dispose()`?
- [ ] `GoogleMapController` completer not leaked?
- [ ] Large lists not held in widget state unnecessarily?

---

## SEVERITY LEVELS

| Level | Meaning |
|---|---|
| 🔴 CRÍTICO | Causes crashes, ANR, or severe drain |
| 🟡 ALTO | Noticeable impact on performance or battery |
| 🟢 MÉDIO | Waste without user-visible impact |
| ⚪ BAIXO | Minor optimisation opportunity |

---

## OUTPUT FORMAT

```
## PERFORMANCE REPORT

### 🔴 CRITICAL
- <issue>: <file/line> — <impact>

### 🟡 HIGH
- <issue>: <file/line> — <recommendation>

### 🟢 MEDIUM
- <issue>: <suggestion>

### SUMMARY
Total issues: X
Estimated battery impact: HIGH / MEDIUM / LOW
Recommendation: <priority fixes>
```

---

## RESPONSABILIDADES

- ✅ Analisar GPS waste, widget rebuilds excessivos, leaks de stream/timer, uso de rede
- ✅ Produzir relatório priorizado por severidade
- ✅ Sugerir optimizações específicas (file:line)

## NÃO PODE FAZER

- ❌ Corrigir bugs (delegar a `guardian` + `executor`)
- ❌ Executar profiler ou rodar testes (análise estática apenas)
- ❌ Alterar arquitetura (delegar a `flow_guard`)
- ❌ Modificar business_rules.md

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| GPS waste, rebuilds, leaks, rede | **performance_watcher** (eu) |
| Corrigir bug de performance | `guardian` + `executor` |
| Interpolação de marcador (perf de mapa) | `map_master` |
| Rebuild de realtime | `realtime_engine` + `fix_realtime` |

## RULES

- Apenas analisa — nunca corrige
- Basear severidade em impacto real (não subjetivo)
- Nomear arquivo + linha onde possível
- Source of truth: `.claude/.ai/business_rules.md`
