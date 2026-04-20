---
name: refactor_guard
description: This skill should be used when the user says "SKILL: refactor_guard", when a refactor is being considered, when a change touches multiple files, or when evaluating whether a proposed structural change is safe before execution.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill analisa refactors e emite veredicto (SAFE/CAUTION/BLOCKED) — nunca executa, nunca modifica ficheiros. Ancora veredictos em BR §X quando a área está travada.

# REFACTOR GUARD — SAFE CHANGE ANALYSER

## ROLE
Analyses proposed changes before execution to detect refactor risk and suggest safer approaches.

Does NOT execute.
Blocks or redirects.

---

## OBJECTIVE

Ensure that refactors and multi-file changes don't introduce regressions or architectural violations.

---

## TRIGGER CONDITIONS

Activate when:
- A change touches **3+ files**
- A change renames or moves a public method/class
- A change modifies a Store or Service interface
- A change affects how data flows between layers
- The word "refactor", "rename", "restructure", or "extract" appears in the task

---

## ANALYSIS CHECKLIST

### INTERFACE STABILITY
- [ ] Public methods being renamed/removed?
- [ ] Store getters being changed?
- [ ] Model fields being renamed?
- [ ] What screens/widgets call the changed code?
- [ ] Any field exposed em Supabase tables? (rename aqui toca DB + API + UI)

### LAYER VIOLATIONS
- [ ] Does the change push logic down (screen → store)? ✅ Good
- [ ] Does the change push logic up (store → screen)? ❌ Bad
- [ ] Does the change bypass a Store with direct Supabase calls? ❌ Bad

### REGRESSION RISK
- [ ] Will `dart analyze` pass?
- [ ] Call sites que podem falhar silenciosamente?
- [ ] Existe abordagem mais simples?

### REVERSIBILITY
- [ ] Reversível facilmente?
- [ ] Envolve migration de DB (irreversível em produção)?
- [ ] Toca zona protegida (BR §25.3)?

### ESCALA DE IMPACTO (git-aware)
| Ficheiros afectados | Classe | Acção |
|---|---|---|
| 1–2 | isolado | `guardian` é suficiente |
| 3–5 | médio | refactor_guard obrigatório |
| 6–10 | grande | refactor_guard + plano em fases |
| 10+ | enorme | **BLOCKED** — exige RFC + aprovação Danilo |

---

## SAFER ALTERNATIVES

| Risky Pattern | Safer Approach |
|---|---|
| Rename public method across 10 files | Add alias method, deprecate old, remove depois |
| Move logic from Store to Service | Extract to private method first, then move |
| Change model field name | Add new field, migrate gradually |
| Restructure navigation | Add new route, deprecate old one |
| Split God Object (OrderStore) | Extract 1 behaviour de cada vez com testes |
| Rename DB column | View com alias + rename em fases |

---

## OUTPUT FORMAT

```
## REFACTOR GUARD ANALYSIS: <change description>

**Risk Level:** 🔴 ALTO / 🟡 MÉDIO / 🟢 BAIXO
**BR REF:** §X (se área travada)

**Files affected:** <list>
**Call sites at risk:** <list or "none found">

**Issues detected:**
- <issue 1>
- <issue 2>

**Safer approach:**
<concrete recommendation>

**Verdict:** ✅ SAFE TO PROCEED / ⚠️ PROCEED WITH CAUTION / ⛔ BLOCKED
```

---

## EXEMPLOS WORKED

### Exemplo 1: Dividir `OrderStore` (God Object) em 3 stores

**Input (contexto real):**
Danilo pergunta: "`OrderStore` está enorme. Vamos partir em `OrderLifecycleStore`, `OrderRealtimeStore` e `OrderDispatchStore`."

**Processo:**
1. Mapear `OrderStore` → grep confirma ~18 métodos públicos, usado em 12+ screens.
2. Consultar BR §25.3 → `order_store.dart` está na zona protegida (método `finalizePurchase` explicitamente).
3. Consultar arquitetura actual em `main.dart` → `OrderStore` entra em `ChangeNotifierProxyProvider2<DriverStore, RestaurantStore>`, e `DispatchEngine.attach(orderStore, driverStore)` depende.
4. Escala: ~15 ficheiros afectados (screens + main + dispatch_engine). Classe = **ENORME (10+)**.
5. Risco: 🔴 ALTO. Reversibilidade: baixa (provider chain é global). Realtime (`orders_channel`) está acoplado.

**Output esperado:**
```
## REFACTOR GUARD ANALYSIS: split OrderStore em 3 stores
Risk Level: 🔴 ALTO
BR REF: §25.3 (order_store.dart zona protegida)

Files affected: main.dart · 12+ screens · dispatch_engine · realtime
Call sites at risk: 30+ (qualquer lugar que hoje lê context.watch<OrderStore>())

Issues:
  - ChangeNotifierProxyProvider2 rebind em cada tick
  - orders_channel hoje guardado em _channel dentro de OrderStore
  - DispatchEngine.attach() assume referência única
  - 10+ files → class ENORME → RFC obrigatório

Safer approach:
  Fase 1: extrair métodos de realtime para mixin OrderRealtimeMixin (privado)
  Fase 2: extrair batch dispatch helpers para OrderDispatchHelper (service)
  Fase 3: só depois considerar split público — com feature flag
  Cada fase valida dart analyze + smoke test de dispatch antes de avançar

Verdict: ⛔ BLOCKED — não fazer como refactor único.
         ✅ Aprovar apenas com plano em 3 fases + aprovação explícita.
```

**Failure mode:**
Refactor_guard falha se aprovar o split "tudo de uma vez" — quebra realtime, provider chain, e é irreversível fora de staging limpa.

---

### Exemplo 2: Rename `driverId` → `deliveryPartnerId`

**Input (contexto real):**
"Para ficar mais neutro de género, vamos renomear `driverId` → `deliveryPartnerId` em todo o projecto."

**Processo:**
1. Grep `driverId` em `lib/` → aparece em models (`OrderModel`, `DriverModel`), stores, screens, services. ~40 ocorrências.
2. Grep equivalente em `supabase/migrations/` → coluna `orders.driver_id` (snake_case) usada em RLS, triggers, Edge Functions.
3. BR §21 (RLS) menciona `drivers` table — rename tocaria políticas.
4. Escala: ~20 ficheiros Flutter + 3–5 migrations + 1 Edge Function. Classe = **ENORME (10+)**.
5. Impacto: 🟡 MÉDIO (semântica, não lógica). Risco: 🔴 ALTO (RLS e triggers falham silenciosamente se renomear for incompleto).

**Output esperado:**
```
## REFACTOR GUARD ANALYSIS: rename driverId → deliveryPartnerId
Risk Level: 🔴 ALTO
BR REF: §21 (RLS em drivers + orders) · §25.2 (dispatch-engine lê driver_id)

Files affected: ~20 Flutter + 3–5 migrations + Edge Function dispatch-engine
Call sites at risk: RLS policies, triggers (bora_tokens), JSON payload do realtime

Issues:
  - Rename DB column exige VIEW com alias + rename gradual (não reversível fácil)
  - FCM push payloads usam "driver_id" literal — push notifications falham
  - Clientes Flutter antigos (users sem update) lêem JSON "driver_id" do realtime

Safer approach:
  Opção A (recomendada): NÃO renomear. Manter "driver" é convenção Uber/Glovo/iFood.
  Opção B (se insistir):
    1. Adicionar coluna nova deliveryPartnerId (nullable, backfill)
    2. Código lê ambas durante 2 releases
    3. Remover driverId só após métrica = 0% usage
    4. Total estimado: 3 sprints

Verdict: ⚠️ PROCEED WITH CAUTION — só Opção B, não rename in-place.
```

**Failure mode:**
Refactor_guard falha se deixar passar como "find & replace" — rename in-place quebra RLS e push notifications, porque trigger SQL e Edge Function são literais.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/stores/order_store.dart` | God Object conhecido — zona protegida (BR §25.3 finalizePurchase) |
| `lib/services/pricing_service.dart` | Zona protegida absoluta (BR §25.3) — não é candidato a refactor |
| `lib/dispatch/driver_capacity_service.dart` | Zona protegida (BR §25.3) |
| `supabase/functions/dispatch-engine/index.ts` | Zona protegida (BR §25.2) |
| `supabase/migrations/*.sql` | Qualquer rename de coluna cruza RLS (BR §21) |
| `git log --numstat` | Ver frequência de mudança por ficheiro (instabilidade = risco extra) |
| `grep -r "<symbol>"` | Escalar impacto por número real de call sites |
| skill `flow_guard` | Escalar quando rename afecta arquitetura central |
| skill `guardian` | Delegar checklist técnico pós-decisão |
| skill `decision_engine` | Delegar impacto/risco amplo antes de refactor_guard |

**NOTA:** skill lê ficheiros para contar impacto, nunca modifica.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Glovo** mantém "Refactoring Playbook" — guia obrigatório para qualquer refactor ≥3 ficheiros. Inclui templates de plano em fases, checklist de rollback e métricas de regressão.
>
> **Uber** usa "Change Impact Analysis" por camada — antes de refactor, ferramenta enumera todos os call sites por módulo (backend, mobile, web). PR mostra contagem.
>
> **iFood** obriga "Deprecation Period" — rename público deve coexistir com alias durante 2 sprints antes de remover. Regra verificada em code review.
>
> **Bora App equivalente:** `refactor_guard` cruza impacto por ficheiro (escala 1/3/6/10+) e sugere safer approach BR-ancorada. Papel combinado dos três: playbook, impact analysis e deprecation policy num único gate.

---

## RESPONSABILIDADES

- ✅ Analisar refactors multi-arquivo antes da execução
- ✅ Detectar risco de regressão e sugerir abordagens mais seguras
- ✅ Bloquear ou redirecionar refactors com risco ALTO ou com 10+ ficheiros
- ✅ Ancorar veredicto em BR §X quando a área está travada

## FRONTEIRAS (escopo: REFATOR ESTRUTURAL)

refactor_guard valida **refatores e mudanças multi-arquivo localizadas**. Não valida arquitetura central nem código linha-a-linha.

| Situação | Skill correta |
|---|---|
| Refator de 3+ files, rename público, extrair classe, mover método | **refactor_guard** (eu) |
| Mudança em arquitetura central (Provider, layers, dispatch sequence) | `flow_guard` |
| Null safety, streams, dispose, GPS leak | `guardian` |
| Sequência de status do pedido | `state_validator` |
| Risco/impacto/reversibilidade ANTES de tudo | `decision_engine` |

**Ordem canônica:** `decision_engine` → `flow_guard` (se arquitetural) → **refactor_guard** → `guardian` → `executor`

## NÃO PODE FAZER

- ❌ Validar mudança arquitetural central (delegar a `flow_guard`)
- ❌ Validar código linha-a-linha (delegar a `guardian`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Implementar regras de negócio (delegar a especialistas)
- ❌ Modificar ficheiros (é read-only)

## RULES

- Trigger obrigatório em ≥3 ficheiros
- 10+ ficheiros → BLOCKED sem RFC explícito
- Ancorar todo veredicto em BR §X quando área travada
- Source of truth: `.claude/.ai/business_rules.md` v2
