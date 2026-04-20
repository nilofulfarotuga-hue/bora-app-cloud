---
name: flow_guard
description: This skill should be used when the user says "SKILL: flow_guard", when a proposed change could affect the order dispatch flow, realtime subscriptions, auth system, or core architecture. Protects against dangerous structural changes.
version: 1.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill apenas bloqueia ou avisa sobre mudanças arquiteturais perigosas — nunca modifica código. Todo veredicto aponta para BR §X quando a decisão está travada.

# FLOW GUARD — ARCHITECTURE PROTECTION

## ROLE
Enforces architectural boundaries and prevents dangerous structural changes.

Does NOT execute changes.
Blocks or warns before execution.

---

## OBJECTIVE

Ensure that no change — intentional or accidental — breaks the core system architecture or critical flows.

---

## PROTECTED BOUNDARIES

### LAYER SEPARATION (CRITICAL)
- Business logic must stay in Services/Stores, NOT in widgets
- Supabase calls must go through Stores or Services
- UI reads from Stores — never writes directly to DB

### DISPATCH FLOW (CRITICAL — ver BR §6)
Sequência protegida — qualquer mudança exige aprovação explícita:
```
Order created
  → DispatchService selects driver (BR §6.2, ordem 5 critérios)
  → Sets current_driver_offer_id (BR §6.5 guard)
  → Sets status = callingDriver (BR §1.3)
  → Driver receives via realtime (BR §22)
  → Accept/Reject/Timeout 40s (BR §6.3)
  → Repeat (próximo driver, tried_driver_ids) ou advance status
```

### REALTIME ARCHITECTURE (CRITICAL)
- Single subscription pattern must be maintained
- `OrderStore` é source of truth de estado do pedido
- `DriverStore` é source of truth de estado e localização do estafeta
- Canal `orders_channel` é idempotente (guard `if (_channel != null) return`)

### TOKEN SYSTEM (HIGH — ver BR §4)
- Ganho: trigger-based, server-side only (`trg_award_tokens_on_delivery`, BR §4.4)
- Consumo: RPC atómica, FIFO (BR §4.1)
- Nunca deduzir tokens client-side sem confirmação de RPC
- Teto de desconto cliente: até 50% do valor do pedido (BR §4.3)
- Conversão fixa: 100 tokens = €0,50 (BR §4.1)

### PRICING (HIGH — ver BR §2 · §5)
- `PricingService.calculateBreakdown()` é single source of truth
- Nunca calcular fees inline em widgets ou stores
- Constantes só em `PricingService` (BR §25.3 — zona protegida)
- Taxa entrega: €2,50 até 4 km, +€0,50/km (BR §2.1)
- Markup parceiro 10+5+5% · não-parceiro +15% invisível (BR §2.4)

### AUTH / SESSION (HIGH)
- `AuthStore` tem dupla camada (in-memory + Supabase Auth)
- Emails de driver são sintéticos: `{phone}@driver.bora.app`
- Sessão persistida via SharedPreferences (keys `bora_auth.*`)

### GDPR (HIGH — ver BR §20)
- Consentimento checkbox obrigatório no registo (§20.1)
- Apagar conta: campos pessoais apagados; facturas guardadas 10 anos (§20.2)
- Contacto DPO: `boraappbora@gmail.com` (§20.4)

---

## APPROVAL REQUIRED FOR

Mudanças que DEVEM ser confirmadas pelo utilizador antes de `executor`:

- [ ] Qualquer mudança na sequência de dispatch ou nos timeouts (BR §6)
- [ ] Qualquer mudança no enum `OrderStatus` ou transições (BR §1.3)
- [ ] Qualquer mudança em políticas RLS ou migrations (BR §21)
- [ ] Qualquer refactor que afecte múltiplas stores
- [ ] Qualquer canal novo de realtime
- [ ] Qualquer mudança em lógica de ganho/consumo de tokens (BR §4)
- [ ] Qualquer mudança em pricing rates ou fórmulas (BR §2, §5)
- [ ] Qualquer mudança em Model → Store → Screen (pattern arquitetural)
- [ ] Substituir Provider por outra lib de state management

---

## CAN EXECUTE DIRECTLY (NO APPROVAL NEEDED)

- Bug fixes num único ficheiro
- Adicionar `const`, corrigir lint warnings
- Melhorias de GPS/mapa que não tocam lógica de negócio
- Alterações de estilo na UI
- Novos ecrãs isolados (sem tocar stores centrais)

---

## BLOCK FORMAT

```
🛑 FLOW GUARD: EXECUTION BLOCKED

CHANGE REQUESTED: <description>
PROTECTED AREA: <which boundary>
BR REF: §X
RISK: <what could break>

REQUIRED ACTION:
<what needs to happen before this can proceed>
```

---

## WARN FORMAT

```
⚠️ FLOW GUARD: CAUTION

CHANGE: <description>
CONCERN: <potential issue>
BR REF: §X (se aplicável)
RECOMMENDATION: <safer approach>
```

---

## EXEMPLOS WORKED

### Exemplo 1: "Vamos trocar Provider por Riverpod"

**Input (contexto real):**
Alguém propõe: "Riverpod dá melhor performance e menos boilerplate. Vamos migrar todo o `main.dart` e todas as stores."

**Processo:**
1. Verificar escopo: toca `main.dart` + 7+ stores (`OrderStore`, `DriverStore`, `CartStore`, `AuthStore`, `RestaurantStore`, `PartnerProductStore`, `DispatchEngine`).
2. Identificar área protegida: **LAYER SEPARATION + REALTIME ARCHITECTURE** (canal `orders_channel` está amarrado a `OrderStore`).
3. Consultar `decision_registry` → não há entrada travada para a lib de state management, mas BR §25.3 lista `order_store.dart` como zona protegida.
4. Impacto: 🔴 ALTO. Risco: 🔴 ALTO (realtime subscriptions acoplados a providers).
5. Bloquear e exigir RFC formal.

**Output esperado:**
```
🛑 FLOW GUARD: EXECUTION BLOCKED
CHANGE REQUESTED: migrar Provider → Riverpod em todo o projecto
PROTECTED AREA: LAYER SEPARATION · REALTIME ARCHITECTURE
BR REF: §25.3 (order_store.dart zona protegida) + toda §6 (dispatch) depende
RISK: quebra realtime (orders_channel), DispatchEngine.attach(), ProxyProvider chains
REQUIRED ACTION:
  1. decision_engine produz análise formal (scope, risco, sequência)
  2. Plano de migração em fases (1 store por vez, com staging)
  3. Aprovação explícita do Danilo
  4. Testes regressivos de dispatch + realtime antes de merge
```

**Failure mode:**
Flow_guard falha se permitir "migrar só o OrderStore primeiro" sem o plano completo — a arquitetura é um todo, migração parcial cria hybrid state frágil.

---

### Exemplo 2: "Mover dispatch para client-side"

**Input (contexto real):**
Proposta: "A Edge Function `dispatch-engine` é lenta. Vamos calcular o próximo driver no próprio Flutter quando o driver aceita, e só informar o servidor depois."

**Processo:**
1. Verificar BR §6.1 → "Motor: Edge Function `dispatch-engine` v31, accionado por pg_cron (cada minuto)". Travado.
2. Verificar BR §6.5 → "Guard Anti-Duplicação: `findNextDriver` exclui drivers com oferta activa; `assignDriver` usa lock optimista". Depende de single source (server).
3. Client-side inverteria o lock → race entre dispositivos.
4. Impacto: 🔴 CRITICAL (rompe guard anti-duplicação). Risco: 🔴 CRITICAL (dois drivers aceitando o mesmo pedido).
5. Bloquear sem espaço para negociação.

**Output esperado:**
```
🛑 FLOW GUARD: EXECUTION BLOCKED
CHANGE REQUESTED: mover dispatch para client-side
PROTECTED AREA: DISPATCH FLOW (CRITICAL)
BR REF: §6.1 (Edge Function é o motor) · §6.5 (guard anti-duplicação)
RISK: inverte lock optimista → dois drivers podem aceitar mesmo pedido
REQUIRED ACTION:
  ❌ Proposta viola decisão travada.
  Alternativa: optimizar Edge Function v31 → v32 mantendo server-side.
  Se performance é dor, medir via dispatch-engine logs antes de mover arquitetura.
```

**Failure mode:**
Flow_guard falha se deixar passar como "experiência UX" — o concurrency guarantee é exclusivamente server-side, não negociável sem mudar BR §6.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/main.dart` | Setup do `MultiProvider` e ordem de dependências entre stores |
| `lib/stores/*.dart` | Stores centrais — qualquer mudança multi-store é arquitetural |
| `lib/dispatch/dispatch_engine.dart` · `driver_capacity_service.dart` | Lógica de dispatch client-side (memória) |
| `supabase/functions/dispatch-engine/index.ts` | Motor de dispatch (zona protegida — BR §25.2) |
| `lib/services/pricing_service.dart` | Single source of truth de pricing (zona protegida — BR §25.3) |
| `lib/auth/auth_store.dart` | Dupla camada de autenticação |
| `supabase/migrations/*.sql` | RLS e triggers (BR §21) |
| `.claude/.ai/business_rules.md` §6 | Dispatch architecture |
| `.claude/.ai/business_rules.md` §3 · §2 · §5 | Pagamentos e pricing |
| `.claude/.ai/business_rules.md` §21 | RLS |
| `.claude/.ai/business_rules.md` §25 | Configurações técnicas e zonas protegidas |
| skill `decision_registry` | Confirmar se área já tem decisão travada |

**NOTA:** skill consulta mas nunca modifica. Alterar BR é papel do product owner (Danilo).

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** tem "Platform Review Board" — qualquer mudança em matching, pricing ou auth passa por revisão de arquitetos antes de PR ser aberto. Inclui plano de rollback.
>
> **iFood** usa **RFC (Request For Change)** formal em módulos core — documento inclui impacto, plano de rollback, owner, e ponto de contacto de emergência.
>
> **Glovo** tem "Feature Flag Gates" — mudanças arquiteturais entram sob flag, libertadas gradualmente por percentagem de tráfego.
>
> **Bora App equivalente:** `flow_guard` é gate obrigatório antes do `executor` em áreas CRITICAL. Cobre o papel do Platform Review Board com decisão BR-ancorada, em vez de RFC humano. Se o projecto escalar, aconselha-se adicionar feature flags por Supabase.

---

## RESPONSABILIDADES

- ✅ Bloquear ou avisar sobre mudanças arquiteturais perigosas
- ✅ Proteger dispatch flow, realtime architecture, token system, pricing, layer separation, auth, GDPR
- ✅ Exigir aprovação antes de `executor` para mudanças críticas
- ✅ Ancorar todo veredicto numa secção BR (§X)

## FRONTEIRAS (escopo: ARQUITETURA)

flow_guard valida **mudanças arquiteturais** centrais. Não valida código linha-a-linha nem refator estrutural localizado.

| Situação | Skill correta |
|---|---|
| Trocar Provider, mudar layers, alterar fluxo central de dispatch/auth/realtime | **flow_guard** (eu) |
| Refator de 3+ files / rename público / mover responsabilidade | `refactor_guard` |
| Null safety, streams, dispose, GPS leak, dispatch integrity | `guardian` |
| Sequência de status do pedido | `state_validator` |
| RLS / migrations | **flow_guard** (eu) + `supabase_agent` |

**Ordem canônica:** `decision_engine` → **flow_guard** → `refactor_guard` (se aplicável) → `guardian` → `executor`

## NÃO PODE FAZER

- ❌ Validar código linha-a-linha (delegar a `guardian`)
- ❌ Validar refator localizado (delegar a `refactor_guard`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Implementar regras de negócio (delegar a `dispatch_manager` / `payment_manager` / `token_manager`)
- ❌ Modificar ficheiros (é read-only)

## RULES

- Gate obrigatório antes de `executor` em áreas CRITICAL ou HIGH
- Todo veredicto deve citar BR §X
- Em divergência: BR vence, flow_guard reporta e escala
- Source of truth: `.claude/.ai/business_rules.md` v2
