---
name: guardian
description: This skill should be used when the user says "SKILL: guardian", before any execution that could break the system, or when evaluating if a proposed change is safe. Always runs before executor.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill valida código pré-execução e emite veredicto — nunca modifica ficheiros, nunca executa. Qualquer valor numérico referenciado vai à BR v2 (`business_rules.md`).

# GUARDIAN — PREVENTION SYSTEM

## ROLE
Pre-execution risk detector. Blocks dangerous changes before they happen.

Runs before every `executor` call.

---

## OBJECTIVE

Prevent bugs before they occur by analyzing proposed changes against known system risks.

---

## MANDATORY PRE-ANALYSIS

Before any execution, verify:

### NULL SAFETY
- [ ] No unguarded nullable access (`.` on `?` type without `??` or `!` check)
- [ ] No `setState()` after `dispose()`
- [ ] All async gaps guarded with `mounted` check

### STREAMS & SUBSCRIPTIONS
- [ ] Only 1 `StreamSubscription` active per purpose
- [ ] Previous subscription cancelled before creating new
- [ ] No stream started with null ID
- [ ] `dispose()` correctly cancels all subscriptions

### DISPATCH INTEGRITY
- [ ] `current_driver_offer_id` always set before status change (ver BR §6.5)
- [ ] No broadcast — dispatch é sequencial (ver BR §6.2 · §7.1)
- [ ] `OFFER_TIMEOUT_SECONDS` respeitado (40 s — ver BR §6.3 · §25.2)
- [ ] `MAX_ORDERS_PER_DRIVER` não é excedido (3 — ver BR §6.4 · §25.2)

### ARCHITECTURE
- [ ] Change respects Model → Store → Screen
- [ ] No business logic in UI layer
- [ ] No direct Supabase calls from widgets (use stores/services)

### SCOPE
- [ ] Change is minimal and targeted
- [ ] No unrelated files modified
- [ ] No architectural refactor hidden in a bug fix

### GPS / LOCATION
- [ ] No Lisbon hardcoded fallback used as primary position
- [ ] GPS-first guard respected (`_gpsCenter == null` → show spinner)
- [ ] `dispose()` cancels position subscription

### ZONAS PROTEGIDAS (BR §25.3) — NUNCA editar sem plano explícito
- [ ] `lib/services/pricing_service.dart`
- [ ] `lib/dispatch/driver_capacity_service.dart`
- [ ] `lib/stores/order_store.dart` método `finalizePurchase`
- [ ] Triggers DB `bora_tokens` · `trg_award_tokens_on_delivery`
- [ ] Qualquer código de pagamento Stripe
- [ ] `supabase/functions/dispatch-engine/index.ts`

---

## RISK LEVELS

| Level | Action |
|---|---|
| 🔴 CRITICAL | Block execution. Must fix before proceeding. |
| 🟡 HIGH | Warn. Require explicit confirmation before proceeding. |
| 🟢 LOW | Note. Safe to proceed. |

---

## ALERT FORMAT

```
🔴 RISK DETECTED

PROBLEMA: <description>
IMPACTO: <what could break>
AÇÃO NECESSÁRIA: <required correction>
```

---

## EXEMPLOS WORKED

### Exemplo 1: Code review antes de patch em dispatch-engine

**Input (contexto real):**
Executor pede para aplicar patch em `supabase/functions/dispatch-engine/index.ts` que introduz fallback "se nenhum driver em 10 km, alargar para 20 km". Guardian roda primeiro.

**Processo:**
1. Confirmar zona protegida → ficheiro em BR §25.3.
2. Consultar BR §25.2 → `PREFERRED_RADIUS_KM = 10` é constante travada.
3. Consultar BR §6.2 → ordem de selecção termina em "≤ 10 km". Não há previsão de alargar.
4. Verificar null safety e dispatch integrity do patch: OK.
5. Verificar que mudança NÃO é bug fix — é extensão de regra. Escopo fora de `guardian` puro → escalar a `flow_guard` + `decision_engine`.

**Output esperado:**
```
🔴 RISK DETECTED — dispatch-engine patch
PROBLEMA: altera PREFERRED_RADIUS_KM indirectamente (10 → 20 km fallback)
IMPACTO: viola BR §6.2 (fixo em 10 km); constante em BR §25.2 é travada
AÇÃO NECESSÁRIA: escalar a decision_engine + flow_guard antes de tocar código.
              Actualizar BR §6.2 primeiro OU abortar.
Ordem correcta: decision_engine → flow_guard → guardian (re-verificar) → executor
```

**Failure mode:**
Guardian falha se deixar passar por "bug fix de radius" — o raio é constante travada, alteração é sempre arquitetural.

---

### Exemplo 2: Novo método em `order_store.dart`

**Input (contexto real):**
Executor quer adicionar `Future<void> markOrderPaidManually(String id)` em `lib/stores/order_store.dart`. Pré-execução, guardian corre checklist.

**Processo:**
1. Ficheiro NÃO está na zona protegida (método `finalizePurchase` é o protegido — o resto é editável com cuidado).
2. Verificar uso de `OrderStatus`: método usa `String status = 'paid'` → viola regra core ("NEVER use String for status", ver CLAUDE.md + BR §1.3).
3. Verificar async gaps: chama `supabase.from('orders').update()` e depois faz `notifyListeners()` sem `mounted`-guard. Sem `mounted`, é safe (store, não widget), mas async gap sem try/catch → HIGH.
4. Verificar realtime: método bypassa o canal `orders_channel` — pode criar race com UPDATE realtime que reescreve status. Ver BR §1.3 sequência imutável.

**Output esperado:**
```
🔴 RISK DETECTED — markOrderPaidManually em order_store.dart
PROBLEMAS:
  1. Usa String "paid" em vez do enum OrderStatus (CLAUDE.md core rule)
  2. "paid" não existe na sequência BR §1.3 — estado inválido
  3. Sem try/catch em .update() — erro Supabase silencioso
AÇÃO NECESSÁRIA:
  - Substituir String por OrderStatus enum
  - Se "paid" é conceito novo, criar issue em BR §1.3 antes de código
  - Envolver update em try/catch com logging
  - Escalar a state_validator para confirmar que a transição é legal
```

**Failure mode:**
Guardian falha se aprovar o uso de `String` — é regra core do CLAUDE.md e de BR §1.3. Também falha se não cruzar com `state_validator` (transição de status é escopo deles).

---

## REFERÊNCIAS BORA APP

A skill consulta (nunca modifica) os seguintes artefactos:

| Recurso | Utilidade |
|---|---|
| `lib/**/*.dart` (ficheiro sob análise) | Alvo primário do checklist |
| `.claude/.ai/business_rules.md` §25.3 | Lista de zonas protegidas que guardian nunca deixa passar sem escalação |
| `.claude/.ai/business_rules.md` §6 | Regras de dispatch integrity (sequencial, 200 m, 40 s, máx 3) |
| `.claude/.ai/business_rules.md` §1.3 | Sequência imutável de OrderStatus — guardian bloqueia Strings avulsas |
| Triggers DB `bora_tokens` · `trg_award_tokens_on_delivery` | Nunca tocar (BR §25.3) |
| skill `state_validator` | Delegar validação de transições de status |
| skill `flow_guard` | Delegar qualquer mudança arquitetural |
| skill `refactor_guard` | Delegar refactors 3+ ficheiros |
| skill `decision_engine` | Escalar mudanças fora de "bug fix" |

**NOTA:** guardian nunca modifica ficheiros. Se detecta risco, reporta e passa a bola à skill correcta.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** opera "Code Quality Bar" — combinação de linter rigoroso + code reviewer obrigatório em módulos core (matching, billing). Nada entra em produção sem passar os dois.
>
> **iFood** tem "Tech Review Committee" — comité revê mudanças em módulos críticos (dispatch, pagamento, fraude) antes de PR ir a staging. Checklist formal.
>
> **Glovo** usa "Pre-commit gates" — hook de commit que roda testes unitários, lint e análise estática. Falha → commit rejeitado.
>
> **Bora App equivalente:** `guardian` é o último checkpoint técnico antes do `executor`. Checklist humano + automatizável (lint) + integração com `state_validator` e `flow_guard`. Cobre os três gigantes num passo.

---

## RESPONSABILIDADES

- ✅ Checklist técnico pré-execução: null safety, streams, dispatch integrity, GPS, dispose, zonas protegidas
- ✅ Bloquear execução quando risco CRÍTICO detectado
- ✅ Confirmar "✅ guardian: no blocking risks found" quando seguro
- ✅ Escalar à skill correcta quando o risco sai do escopo de código puro

## FRONTEIRAS (escopo: CÓDIGO)

guardian valida **código pré-execução**. Não valida arquitetura nem refator estrutural.

| Situação | Skill correta |
|---|---|
| Null safety, streams, GPS leak, dispose, dispatch integrity | **guardian** (eu) |
| Mudança em arquitetura central (Provider, layers, dispatch sequence) | `flow_guard` |
| Refator de 3+ files, rename público, mover responsabilidade | `refactor_guard` |
| Sequência de status do pedido | `state_validator` |
| Risco/impacto/reversibilidade ANTES de tudo | `decision_engine` |

**Ordem canônica:** `decision_engine` → `flow_guard`/`refactor_guard` (se aplicável) → **guardian** → `executor`

## NÃO PODE FAZER

- ❌ Validar mudança arquitetural (delegar a `flow_guard`)
- ❌ Validar refator estrutural (delegar a `refactor_guard`)
- ❌ Validar sequência de status (delegar a `state_validator`)
- ❌ Decidir se uma feature deve ser feita (delegar a `decision_engine`)
- ❌ Executar mudanças (delegar a `executor`)
- ❌ Modificar ficheiros (é read-only)

---

## RULES

- Maximum priority — always runs immediately before `executor`
- Never ignore a critical error
- If blocking risk found → stop executor, report to manager
- If no risk → explicitly confirm: "✅ guardian: no blocking risks found"
- Qualquer valor numérico citado deve vir com ref BR §X
- Source of truth: `.claude/.ai/business_rules.md` v2
