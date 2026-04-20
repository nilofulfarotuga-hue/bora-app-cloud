---
name: flow_guard
description: This skill should be used when the user says "SKILL: flow_guard", when a proposed change could affect the order dispatch flow, realtime subscriptions, auth system, or core architecture. Protects against dangerous structural changes.
version: 1.0.0
---

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

### DISPATCH FLOW (CRITICAL)
Protected sequence — any change here requires explicit approval:
```
Order created
  → DispatchService selects driver
  → Sets current_driver_offer_id
  → Sets status = callingDriver
  → Driver receives via realtime
  → Accept/Reject/Timeout
  → Repeat or advance status
```

### REALTIME ARCHITECTURE (CRITICAL)
- Single subscription pattern must be maintained
- `OrderStore` is the source of truth for order state
- `DriverStore` is the source of truth for driver state and location

### TOKEN SYSTEM (HIGH)
- Earning: trigger-based, server-side only
- Consuming: `consume_tokens` RPC, FIFO, atomic
- Never deduct tokens client-side without RPC confirmation

### PRICING (HIGH)
- `PricingService.calculateBreakdown()` is the single source of truth
- Never calculate fees inline in widgets or stores
- Rate constants are defined only in `PricingService`

---

## APPROVAL REQUIRED FOR

These changes MUST be confirmed by user before executor runs:

- [ ] Any change to dispatch sequence or timing
- [ ] Any change to `OrderStatus` enum or transitions
- [ ] Any change to Supabase RLS policies or migrations
- [ ] Any refactor affecting multiple stores simultaneously
- [ ] Any new realtime subscription channel
- [ ] Any change to token earning/consuming logic
- [ ] Any change to pricing rates or formulas
- [ ] Any architectural pattern change (Model → Store → Screen)

---

## CAN EXECUTE DIRECTLY (NO APPROVAL NEEDED)

- Bug fixes within a single file
- Adding `const`, fixing lint warnings
- GPS/map improvements that don't touch business logic
- UI styling changes
- Adding new isolated screens

---

## BLOCK FORMAT

When blocking a dangerous change:

```
🛑 FLOW GUARD: EXECUTION BLOCKED

CHANGE REQUESTED: <description>
PROTECTED AREA: <which boundary>
RISK: <what could break>

REQUIRED ACTION:
<what needs to happen before this can proceed>
```

---

## WARN FORMAT

When warning about a risky (but not blocked) change:

```
⚠️ FLOW GUARD: CAUTION

CHANGE: <description>
CONCERN: <potential issue>
RECOMMENDATION: <safer approach>
```

---

## RESPONSABILIDADES

- ✅ Bloquear ou avisar sobre mudanças arquiteturais perigosas
- ✅ Proteger dispatch flow, realtime architecture, token system, pricing, layer separation
- ✅ Exigir aprovação antes de `executor` para mudanças críticas

## FRONTEIRAS (escopo: ARQUITETURA)

flow_guard valida **mudanças arquiteturais** centrais. Não valida código linha-a-linha nem refator estrutural localizado.

| Situação | Skill correta |
|---|---|
| Trocar Provider, mudar layers, alterar fluxo central de dispatch/auth/realtime | **flow_guard** (eu) |
| Refator de 3+ files / rename público / mover responsabilidade | `refactor_guard` |
| Null safety, streams, dispose, GPS leak, dispatch integrity | `guardian` |
| Sequência de status do pedido | `state_validator` |
| RLS / migrations | `flow_guard` (eu) + `supabase_agent` |

**Ordem canônica:** `decision_engine` → **flow_guard** → `refactor_guard` (se aplicável) → `guardian` → `executor`

## NÃO PODE FAZER

- ❌ Validar código linha-a-linha (delegar a `guardian`)
- ❌ Validar refator localizado (delegar a `refactor_guard`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Implementar regras de negócio (delegar a `dispatch_manager` / `payment_manager` / `token_manager`)
