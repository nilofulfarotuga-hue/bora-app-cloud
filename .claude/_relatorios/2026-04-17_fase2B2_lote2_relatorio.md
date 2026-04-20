# RELATÓRIO FASE 2.B.2 — LOTE 2 (CONTROLE)

**Data:** 2026-04-17
**Modo:** PROTECÇÃO TOTAL
**Escopo:** Camada 2 (Controle) — 5 ficheiros (3 skills + 2 sub-skills)
**Source of truth:** `.claude/.ai/business_rules.md` v2 (26 secções)

---

## 1. Backup

- **Localização:** `.claude/_backups/2026-04-17_fase2B2_lote2/` (+ subdir `state_validator/`)
- **5 ficheiros preservados:**
  - guardian.md (116 linhas · v2.0.0)
  - flow_guard.md (141 linhas · v1.0.0)
  - refactor_guard.md (121 linhas · v1.0.0)
  - state_validator/rules.md (78 linhas · v2.0.0)
  - state_validator/validation.md (74 linhas · v2.0.0)
- **Total preservado:** 530 linhas.

---

## 2. Skills modificadas

### 2.1 guardian.md
- **Antes / depois:** 116 / 223 linhas · v2.0.0 → **v2.1.0**
- **protection_mode:** read-only
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - Checklist DISPATCH INTEGRITY agora referencia BR §6.2, §6.3, §6.4, §6.5, §25.2
  - Nova secção ZONAS PROTEGIDAS (espelho BR §25.3) no checklist pré-execução
  - 2 Exemplos Worked:
    - Patch em `dispatch-engine` que altera PREFERRED_RADIUS_KM
    - Novo método `markOrderPaidManually` em `order_store.dart` (detecta uso de String vs OrderStatus + status inválido)
  - Secção REFERÊNCIAS BORA APP (9 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Code Quality Bar · Tech Review Committee · Pre-commit gates)
- **Substituições hardcoded → BR §X:**
  - Dispatch timing (40s · 3 max · 200m) agora citam §6.3 · §6.4 · §25.2
- **Secções originais preservadas:** ROLE, OBJECTIVE, RISK LEVELS, ALERT FORMAT, RESPONSABILIDADES, FRONTEIRAS, NÃO PODE FAZER, RULES ✅

### 2.2 flow_guard.md
- **Antes / depois:** 141 / 263 linhas · v1.0.0 → **v1.1.0**
- **protection_mode:** read-only
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - Secção PROTECTED BOUNDARIES alargada: cada boundary agora cita BR §X
  - Nova subsecção AUTH / SESSION (HIGH)
  - Nova subsecção GDPR (HIGH · §20)
  - DISPATCH FLOW agora mostra referências cruzadas (§6.2 · §6.3 · §6.5 · §7.1)
  - TOKEN SYSTEM detalhado com teto 50% (§4.3), conversão 100=€0,50 (§4.1), trigger (§4.4)
  - PRICING detalhado com markup 10+5+5% (§2.4), taxa entrega (§2.1), zona protegida (§25.3)
  - APPROVAL REQUIRED FOR agora cita BR §X por item
  - 2 Exemplos Worked:
    - Migrar Provider → Riverpod (bloqueia por realtime coupling)
    - Mover dispatch para client-side (bloqueia por BR §6.1 · §6.5)
  - Secção REFERÊNCIAS BORA APP (12 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Platform Review Board · RFC · Feature Flag Gates)
- **Substituições hardcoded → BR §X:**
  - Dispatch sequence, tokens, pricing, RLS, auth, GDPR — todos ancorados em §X
- **Secções originais preservadas** ✅

### 2.3 refactor_guard.md
- **Antes / depois:** 121 / 259 linhas · v1.0.0 → **v1.1.0**
- **protection_mode:** read-only
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - Nova secção ESCALA DE IMPACTO (git-aware) com tabela 1–2 / 3–5 / 6–10 / 10+
  - Checklist REVERSIBILITY agora menciona zonas protegidas BR §25.3
  - OUTPUT FORMAT inclui campo `BR REF: §X`
  - Nova linha em SAFER ALTERNATIVES: "Split God Object" + "Rename DB column"
  - 2 Exemplos Worked:
    - Dividir `OrderStore` em 3 stores (BLOCKED sem plano em 3 fases)
    - Rename `driverId` → `deliveryPartnerId` (CAUTION, cruza RLS e push payloads)
  - Secção REFERÊNCIAS BORA APP (10 recursos incluindo `git log --numstat`)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Refactoring Playbook · Change Impact Analysis · Deprecation Period)
- **Substituições hardcoded → BR §X:** zonas protegidas sempre a apontar §25.3; RLS a §21; dispatch-engine a §25.2.
- **Secções originais preservadas** ✅

### 2.4 state_validator/rules.md
- **Antes / depois:** 78 / 215 linhas · v2.0.0 → **v2.1.0**
- **protection_mode:** read-only
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - SEQUÊNCIA IMUTÁVEL (DELIVERY) ancorada em BR §1.3
  - Nova secção SEQUÊNCIA IMUTÁVEL (RESERVA) ancorada em BR §1.4 · §14.8
  - Estados terminais legítimos documentados (delivered / rejected / cancelled)
  - Excepções documentadas: `driverAccepted → callingDriver` via `driver_cancel_order()` (BR §7.7)
  - VALIDAÇÕES OBRIGATÓRIAS agora cita BR §7.3 (código 4 dígitos) e §7.4 (isPurchaseFinalized)
  - 2 Exemplos Worked:
    - Tentativa de saltar `preparing → driverAccepted` (ilegal + contorna guard BR §6.5)
    - Tentativa de saltar `pickedUp → delivered` (ilegal + bypass código 4 dígitos BR §7.3)
  - Secção REFERÊNCIAS BORA APP (10 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Trip State Machine · Order Status FSM · State Machine Tests)
- **Substituições hardcoded → BR §X:** sequência delivery → §1.3; reserva → §1.4; cancel → §7.7
- **Secções originais preservadas** ✅

### 2.5 state_validator/validation.md
- **Antes / depois:** 74 / 235 linhas · v2.0.0 → **v2.1.0**
- **protection_mode:** read-only
- **Adicionado:**
  - Frontmatter `protection_mode: read-only`
  - PASSO 1 ANALISAR agora inclui tipo de pedido (BR §1.2 · §10)
  - Nova secção PRÉ-CONDIÇÕES POR TRANSIÇÃO (cobre 7 transições da FSM delivery + cancel)
    - Cada transição lista checks específicos ancorados em BR §3.2, §3.3, §4.2, §4.4, §6.3, §6.4, §7.3, §7.4, §7.5, §7.6, §7.7
  - CHECKLIST PÓS-MUDANÇA expandido: tokens +40 (§4.2), cashback 3% (§4.2), push (§22.1), payout (§3.4)
  - 2 Exemplos Worked:
    - Validar `pickedUp → onTheWay` em não-parceiro (cita §7.4 + §22.1)
    - Validar `onTheWay → delivered` com código 4 dígitos (cita §1.3 + §7.3 + §4.2 + §4.4 + §23.1)
  - Secção REFERÊNCIAS BORA APP (11 recursos)
  - Secção BENCHMARK UBER / IFOOD / GLOVO (Pre/Post Condition Checks · Status Event Sourcing · Contract Tests)
- **Substituições hardcoded → BR §X:** código 4 dígitos → §7.3; isPurchaseFinalized → §7.4; tokens → §4.2 · §4.4; timeouts → §6.3 · §6.4
- **Secções originais preservadas** ✅

---

## 3. Verificação global

| Critério | guardian | flow_guard | refactor_guard | state_validator/rules | state_validator/validation |
|---|:-:|:-:|:-:|:-:|:-:|
| Frontmatter `protection_mode: read-only` | ✅ | ✅ | ✅ | ✅ | ✅ |
| EXEMPLOS WORKED (≥2) | ✅ | ✅ | ✅ | ✅ | ✅ |
| REFERÊNCIAS BORA APP | ✅ | ✅ | ✅ | ✅ | ✅ |
| BENCHMARK UBER/IFOOD/GLOVO | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hardcoded → BR §X | ✅ | ✅ | ✅ | ✅ | ✅ |
| Secções originais preservadas | ✅ | ✅ | ✅ | ✅ | ✅ |
| Versão incrementada | 2.0.0 → 2.1.0 | 1.0.0 → 1.1.0 | 1.0.0 → 1.1.0 | 2.0.0 → 2.1.0 | 2.0.0 → 2.1.0 |

### Invariantes respeitadas
- ✅ Código Bora App (`lib/`, `supabase/`) **NÃO** foi tocado
- ✅ `business_rules.md` v2 **NÃO** foi tocado
- ✅ Outras skills fora do Lote 2 **NÃO** foram tocadas (Lote 1 intacto, executor/managers intactos)
- ✅ Backup íntegro em `.claude/_backups/2026-04-17_fase2B2_lote2/`
- ✅ Todas as referências `BR §X` verificadas contra BR v2 (2026-04-17)
- ✅ Ordem canônica documentada de forma consistente em todas: `decision_engine → flow_guard → refactor_guard → guardian → executor`

---

## 4. Observações

### Padrões detectados nas 5 skills
- **Ordem canônica agora é consistente em todas as 3 skills guard** (guardian, flow_guard, refactor_guard) — todas apontam para a mesma sequência. Antes era só guardian.
- **state_validator (rules + validation) agora cobre reserva de mesa** (BR §1.4 / §14.8) — anteriormente só documentava delivery. Lacuna fechada.
- **BR §25.3 (zonas protegidas) está agora citada nas 3 guards** — guardian, flow_guard, refactor_guard. Dá defesa em profundidade.
- **BENCHMARK alinha com o framework dos gigantes:** Uber aparece em todas (Code Quality Bar, Platform Review Board, Change Impact Analysis, Trip State Machine, Pre/Post Conditions) — porque é a referência mais pública.

### Duplicações residuais
- `guardian` e `state_validator` tocam ambos o enum `OrderStatus`. Separação ficou clara: guardian detecta uso de **String** em vez de enum (erro de código); state_validator valida **sequência** de transições (erro de FSM). Documentado em ambas.
- `flow_guard` e `refactor_guard` ambos podem vetar mudanças em `order_store.dart`. Divisão clara: flow_guard se for **arquitetura** (quebra pattern), refactor_guard se for **estrutural** (quebra interface). Documentado.

### Dúvidas arquiteturais
- `dispatch_manager`, `payment_manager`, `token_manager`, `realtime_engine` são mencionados como delegatários mas **não estavam no Lote 2** — serão Lote 3 ou posterior.
- Excepção legal `driverAccepted → callingDriver` via `driver_cancel_order()` RPC está documentada em rules.md, mas **a própria FSM em `OrderStore._statusFlow`** não expõe isto. Vale uma auditoria futura (fora do escopo deste lote, pois tocaria `lib/stores/order_store.dart`).

---

## 5. Próximo passo

**Lote 3 — Execução:**
- `.claude/.ai/skills/executor.md`
- `.claude/.ai/skills/auto_orchestrator/rules.md`
- `.claude/.ai/skills/auto_orchestrator/flow.md`
- `.claude/.ai/skills/auto_orchestrator/decision.md`
- `.claude/.ai/skills/auto_orchestrator/loop.md`

Mesma transformação (protection_mode, 2 exemplos, referências, benchmark, substituições hardcoded).

---

*Relatório — Fase 2.B.2 Lote 2 (Controle) — 2026-04-17*
