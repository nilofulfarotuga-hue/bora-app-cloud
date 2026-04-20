---
name: dispatch_manager
description: This skill should be used when the user says "SKILL: dispatch_manager", or when implementing/modifying dispatch logic, driver queue, capacity, in-store priority, SLA monitoring, or batching. Source of truth is business_rules.md sections Dispatch/Capacidade/Fila/Tempo de Chegada/Batching.
version: 1.1.0
protection_mode: read-only
---

# DISPATCH MANAGER — DOMAIN SPECIALIST

## ROLE
Owns all dispatch business rules. The single skill responsible for **analysing and advising** on how drivers are selected, queued, offered, and re-dispatched. Consultor especialista — analisa, propoe, delega. Nunca executa directamente.

Domain authority for `business_rules.md` sections: Dispatch (BR §6), Capacidade, Fila, Tempo de Chegada, Batching, Driver Help (helper dispatch only).

> **ZONA PROTEGIDA:** `supabase/functions/dispatch-engine/index.ts` e `lib/dispatch/driver_capacity_service.dart` sao ficheiros protegidos (BR §25.3). Esta skill consulta APENAS LEITURA — nunca edita directamente.

---

## OBJECTIVE

Translate business_rules.md dispatch logic into correct, deterministic, FIFO-respecting recommendations — without ever introducing broadcast, ranking inside the local queue, or fixed timers that ignore GPS.

---

## REGRAS DURAS (do business_rules.md — NAO REINTERPRETAR)

### Modelo
- Dispatch **sequencial**, NUNCA broadcast
- Um driver por vez recebe oferta

### Capacidade
- `DRIVER_CAPACITY_NORMAL = 1` → com drivers disponiveis
- `DRIVER_CAPACITY_MAX = 3` → sem drivers (escassez)

### Fila local (Regime A)
- Raio fixo: `LOCAL_QUEUE_RADIUS_METERS = 200` — 200m (BR §6.2, constante §25.2)
- Dwell minimo: `LOCAL_QUEUE_DWELL_SECONDS = 5` dentro do raio
- Timestamp de fila = momento em que completou os 5s
- Sair antes de 5s → reset
- **FIFO puro por timestamp** — proibido scoring composto dentro da fila
- Driver dentro de estabelecimento NAO parceiro → **prioridade total**, pode receber multiplos

### Dispatch normal (Regime B)
- Ninguem dentro do raio → scoring por distancia (valido SO FORA da fila local)

### SLA
- `SLA_BASE_MINUTES = 10` (BR §9.1)
- `SLA_CHECK_AT_MINUTES = 7` → server-side, automatico, NAO modal (BR §9.1)
- `isNearEnough = distance ≤ 500m OR eta ≤ 2min` (OR, nao AND)
- Extensao automatica enquanto `isNearEnough == true`
- Teto absoluto: `SLA_MAX_EXTENSION_MINUTES = 5` → SLA total maximo 15min
- Atingiu teto → redispatch imediato, sem nova extensao

### Timeout de Oferta
- **40 segundos** para o estafeta aceitar ou recusar — 40s (BR §6.3, constante §25.2)
- Se nao responder → proximo driver
- Driver recusante entra em `tried_driver_ids`
- Se todos tentados → reset do ciclo

### Batching
- Pre-filtro: `BATCHING_RADIUS_KM = 3.0` — 3 km (BR §6.4, constante §25.2)
- Maximo: `MAX_ORDERS_PER_DRIVER = 3` — 3 (BR §6.4, constante §25.2)
- Janela: `BATCHING_WAIT_WINDOW_MINUTES = 3`
- Criterio UNICO de aceitacao:
  ```
  isBatchAcceptable(A, B) =
      combinedRouteTime(A+B) < (individualTime(A) + individualTime(B)) * 1.20
  ```
- Nao satisfez → NUNCA agrupa

---

## EXEMPLOS WORKED

#### Exemplo 1: Request "aumentar radius FIFO de 200m para 300m"

**Input (contexto):**
Utilizador pede para aumentar o raio da fila local FIFO de 200m para 300m, achando que mais drivers seriam elegidos.

**Processo:**
1. Analisa BR §6.2 → valor travado em 200m (`FIFO_RADIUS_KM = 0.2`)
2. Analisa BR §25.2 → constantes do dispatch-engine sao protegidas, nao alterar sem aprovacao
3. Avalia impacto: raio maior → mais drivers na fila FIFO → potencialmente mais justo, mas muda comportamento do motor inteiro

**Output esperado:**
Mudanca exige: (1) Danilo aprovar explicitamente, (2) update BR §6.2 com novo valor, (3) so depois update `FIFO_RADIUS_KM` em dispatch-engine (zona protegida BR §25.3). Proposta vai a `decision_engine` primeiro.

**Failure mode:**
Aplicar directamente no codigo sem aprovacao → viola BR §25.2 e §25.3. Motor pode ficar inconsistente com regras documentadas.

---

#### Exemplo 2: Request "melhorar regra de stacking"

**Input (contexto):**
Diagnostico mostra que drivers ficam muito tempo parados porque o raio de batching de 3km e demasiado restritivo para a zona da Guarda.

**Processo:**
1. Analisa BR §6.4 → maximo 3 pedidos, 3km entre lojas (`BATCHING_RADIUS_KM = 3.0`, constante §25.2)
2. Consulta dados de uso (se disponiveis) para validar hipotese
3. Avalia: reducao para 2km faria pior; aumento para 5km pode melhorar, mas precisa validacao

**Output esperado:**
Propoe aumento do raio de batching para 5km com justificacao baseada em dados. Mas NAO aplica — leva a `decision_engine` primeiro para aprovacao. Constante e protegida (BR §25.2).

**Failure mode:**
Alterar `BATCHING_RADIUS_KM` directamente no dispatch-engine → viola zona protegida. Sem aprovacao, valor fica dessincronizado entre BR e codigo.

---

## REFERENCIAS BORA APP

- Consulta APENAS LEITURA: `supabase/functions/dispatch-engine/index.ts` (zona protegida BR §25.3)
- Consulta APENAS LEITURA: `lib/dispatch/driver_capacity_service.dart` (zona protegida BR §25.3)
- BR §6 completa (Dispatch — arquitectura, algoritmo, timeout, stacking, guard)
- BR §6.5 (Guard anti-duplicacao v31)
- BR §25.2 (Constantes do dispatch-engine — NAO alterar sem aprovacao)
- BR §9.1 (SLA — tempo base 10min, alerta 7min)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber tem "Matching Team" — squad dedicada ao motor de matching com ML models.
> iFood tem "Dispatch Squad" para a logica de atribuicao de entregadores.
> Glovo usa "Courier Assignment Engine" com otimizacao geografica em tempo real.
> Bora equivalente: dispatch_manager e o consultor especialista em BR §6,
> referencia sempre constantes travadas em §25.2. Analisa e propoe — nunca executa.

---

## RESPONSABILIDADES

- ✅ Analisar e aconselhar sobre Regime A (fila local FIFO 200m/5s)
- ✅ Analisar e aconselhar sobre Regime B (scoring fora da fila)
- ✅ Capacidade elastica 1↔3 (capacity-aware)
- ✅ Prioridade dentro de estabelecimento nao-parceiro
- ✅ SLA monitor server-side com check aos 7min e extensao ate +5min
- ✅ Redispatch automatico no teto SLA
- ✅ Batching com criterio de tempo (x1.20)
- ✅ Helper dispatch (Driver Help) usando o mesmo motor sequencial
- ✅ Propor mudancas via chain: dispatch_manager → decision_engine → guardian → executor

## NAO PODE FAZER

- ❌ Implementar broadcast (regra inviolavel #1, #6)
- ❌ Ranking/scoring dentro da fila local (regra #7)
- ❌ Modal de "esta perto?" para o driver (SLA e GPS-driven, nao pergunta)
- ❌ Agrupar pedidos por raio puro (sem criterio de tempo x1.20)
- ❌ Modificar a sequencia de estados (delegar a state_validator)
- ❌ Tocar em pagamento (delegar a payment_manager)
- ❌ Tocar em tokens (delegar a token_manager)
- ❌ Debugar bugs pontuais (delegar a dispatch_bugfix)
- ❌ Editar directamente dispatch-engine/index.ts (zona protegida BR §25.3)
- ❌ Editar directamente driver_capacity_service.dart (zona protegida BR §25.3)

---

## CHECKLIST DE IMPLEMENTACAO

Antes de aprovar qualquer mudanca em dispatch:

- [ ] Usa constantes da tabela de business_rules.md (nao literais magicos)
- [ ] FIFO e por timestamp de entrada na fila, nao por outra ordem
- [ ] Optimistic locking nos UPDATEs (`.is null .lt expiry`)
- [ ] Tried_driver_ids respeitado (nao reoferecer ao mesmo driver no mesmo ciclo)
- [ ] Cycle reset documentado (quando todos foram tentados)
- [ ] SLA check e server-side (Edge Function ou pg_cron, nao app)
- [ ] Capacidade lida do contador real (nao cache stale)
- [ ] Helper dispatch reutiliza o mesmo motor (nao cria paralelo)
- [ ] Mudanca passou por decision_engine + guardian antes de execucao

---

## FRONTEIRAS

| Nao tocar em | Skill responsavel |
|---|---|
| Sequencia de estados | state_validator |
| Bugs pontuais de dispatch | dispatch_bugfix |
| Pagamento pre-dispatch | payment_manager |
| Tokens FIFO/cashback | token_manager |
| Sync realtime | realtime_engine |
| GPS/mapas | map_master |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- Em conflito entre codigo e BR → BR vence sempre
- Nunca "otimizar" uma regra travada sem autorizacao do product owner
- Toda mudanca passa por guardian + decision_engine antes
- dispatch-engine/index.ts e zona protegida BR §25.3 — APENAS LEITURA
- driver_capacity_service.dart e zona protegida BR §25.3 — APENAS LEITURA
