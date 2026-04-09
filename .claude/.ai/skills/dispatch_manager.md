---
name: dispatch_manager
description: This skill should be used when the user says "SKILL: dispatch_manager", or when implementing/modifying dispatch logic, driver queue, capacity, in-store priority, SLA monitoring, or batching. Source of truth is business_rules.md sections Dispatch/Capacidade/Fila/Tempo de Chegada/Batching.
version: 1.0.0
---

# DISPATCH MANAGER — DOMAIN SPECIALIST

## ROLE
Owns all dispatch business rules. The single skill responsible for implementing how drivers are selected, queued, offered, and re-dispatched.

Domain authority for `business_rules.md` sections: Dispatch, Capacidade, Fila, Tempo de Chegada, Batching, Driver Help (helper dispatch only).

---

## OBJECTIVE

Translate business_rules.md dispatch logic into correct, deterministic, FIFO-respecting code — without ever introducing broadcast, ranking inside the local queue, or fixed timers that ignore GPS.

---

## REGRAS DURAS (do business_rules.md — NÃO REINTERPRETAR)

### Modelo
- Dispatch **sequencial**, NUNCA broadcast
- Um driver por vez recebe oferta

### Capacidade
- `DRIVER_CAPACITY_NORMAL = 1` → com drivers disponíveis
- `DRIVER_CAPACITY_MAX = 3` → sem drivers (escassez)

### Fila local (Regime A)
- Raio fixo: `LOCAL_QUEUE_RADIUS_METERS = 200` (NÃO dinâmico no MVP)
- Dwell mínimo: `LOCAL_QUEUE_DWELL_SECONDS = 5` dentro do raio
- Timestamp de fila = momento em que completou os 5s
- Sair antes de 5s → reset
- **FIFO puro por timestamp** — proibido scoring composto dentro da fila
- Driver dentro de estabelecimento NÃO parceiro → **prioridade total**, pode receber múltiplos

### Dispatch normal (Regime B)
- Ninguém dentro do raio → scoring por distância (válido SÓ FORA da fila local)

### SLA
- `SLA_BASE_MINUTES = 10`
- `SLA_CHECK_AT_MINUTES = 7` → server-side, automático, NÃO modal
- `isNearEnough = distance ≤ 500m OR eta ≤ 2min` (OR, não AND)
- Extensão automática enquanto `isNearEnough == true`
- Teto absoluto: `SLA_MAX_EXTENSION_MINUTES = 5` → SLA total máximo 15min
- Atingiu teto → redispatch imediato, sem nova extensão

### Batching
- Pré-filtro: `BATCHING_RADIUS_KM = 15` (necessário, não suficiente)
- Janela: `BATCHING_WAIT_WINDOW_MINUTES = 3`
- Critério ÚNICO de aceitação:
  ```
  isBatchAcceptable(A, B) =
      combinedRouteTime(A+B) < (individualTime(A) + individualTime(B)) * 1.20
  ```
- Não satisfez → NUNCA agrupa

---

## RESPONSABILIDADES

- ✅ Implementar Regime A (fila local FIFO 200m/5s)
- ✅ Implementar Regime B (scoring fora da fila)
- ✅ Capacidade elástica 1↔3 (capacity-aware)
- ✅ Prioridade dentro de estabelecimento não-parceiro
- ✅ SLA monitor server-side com check aos 7min e extensão até +5min
- ✅ Redispatch automático no teto SLA
- ✅ Batching com critério de tempo (×1.20)
- ✅ Helper dispatch (Driver Help) usando o mesmo motor sequencial

## NÃO PODE FAZER

- ❌ Implementar broadcast (regra inviolável #1, #6)
- ❌ Ranking/scoring dentro da fila local (regra #7)
- ❌ Modal de "está perto?" para o driver (SLA é GPS-driven, não pergunta)
- ❌ Agrupar pedidos por raio puro (sem critério de tempo ×1.20)
- ❌ Modificar a sequência de estados (delegar a state_validator)
- ❌ Tocar em pagamento (delegar a payment_manager)
- ❌ Tocar em tokens (delegar a token_manager)
- ❌ Debugar bugs pontuais (delegar a dispatch_bugfix)

---

## CHECKLIST DE IMPLEMENTAÇÃO

Antes de aprovar qualquer mudança em dispatch:

- [ ] Usa constantes da tabela de business_rules.md (não literais mágicos)
- [ ] FIFO é por timestamp de entrada na fila, não por outra ordem
- [ ] Optimistic locking nos UPDATEs (`.is null .lt expiry`)
- [ ] Tried_driver_ids respeitado (não reoferecer ao mesmo driver no mesmo ciclo)
- [ ] Cycle reset documentado (quando todos foram tentados)
- [ ] SLA check é server-side (Edge Function ou pg_cron, não app)
- [ ] Capacidade lida do contador real (não cache stale)
- [ ] Helper dispatch reutiliza o mesmo motor (não cria paralelo)

---

## FRONTEIRAS

| Não tocar em | Skill responsável |
|---|---|
| Sequência de estados | state_validator |
| Bugs pontuais de dispatch | dispatch_bugfix |
| Pagamento pré-dispatch | payment_manager |
| Tokens FIFO/cashback | token_manager |
| Sync realtime | realtime_engine |
| GPS/mapas | map_master |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- Em conflito entre código e BR → BR vence sempre
- Nunca "otimizar" uma regra travada sem autorização do product owner
- Toda mudança passa por guardian + decision_engine antes
