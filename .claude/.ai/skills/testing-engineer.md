---
name: testing-engineer
description: Use this skill when the user says "SKILL: testing-engineer", or when work touches automated tests — unit tests, widget tests, integration tests, dart analyze output, or coverage of Flutter code. Triggers on "run tests", "dart analyze", "test coverage", "unit test".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia e categoriza testes — nunca edita directamente zonas protegidas (BR §25.3). Pode propor testes novos mas execução vai pelo `executor`.

# TESTING ENGINEER

## ROLE
Especialista em testes automáticos do código Flutter + Supabase. Responsável por `dart analyze`, testes unitários, widget tests, e cobertura de funções críticas.

---

## EXEMPLOS WORKED

### Exemplo 1 — `dart analyze` retorna 70 issues

**Input (contexto real):**
Utilizador corre `flutter analyze` e tem 70 issues: 12 errors, 38 warnings, 20 infos. Pede triagem e plano de fix.

**Processo:**
1. Categorizar por severidade:
   - **errors (12):** bloqueiam build → prioridade máxima
   - **warnings (38):** deprecated APIs, unused imports, null-safety soft issues
   - **infos (20):** style (lint rules, prefer_const, avoid_print)
2. Auto-fixable (seguro sem aprovação): infos + warnings triviais (unused_import, prefer_const_constructors).
3. Requer aprovação: qualquer error em zona protegida (BR §25.3) — `pricing_service.dart`, `driver_capacity_service.dart`, `order_store.dart:finalizePurchase`, Stripe, dispatch-engine.
4. Plano por ordem:
   - Passo 1: correr `dart fix --apply` (bulk auto-fix infos)
   - Passo 2: listar errors fora de zona protegida → corrigir via executor
   - Passo 3: listar errors em zona protegida → escalar a decision_engine + guardian
5. Relatório final: X auto-fix, Y executor, Z escalar.

**Output esperado:**
```
✅ TRIAGEM DART ANALYZE — 70 issues
Auto-fixable (seguro): 45 (infos + unused_imports)
Executor com plano: 15 (warnings + 8 errors fora zona protegida)
Escalação obrigatória: 10 (4 errors em pricing_service + 6 em dispatch-engine)
Ordem: [dart_fix_bulk, executor_batch, escalate_to_decision_engine]
```

**Failure mode:**
Falha se aplicar auto-fix em `pricing_service.dart` (zona protegida). Falha se não distinguir errors de warnings — errors bloqueiam build.

---

### Exemplo 2 — Função `requestDriverHelp` sem teste

**Input (contexto real):**
Foi implementada a RPC `request_driver_help(order_id)` (BR §5.2). Nenhum teste cobre a função. Utilizador pede teste unitário.

**Processo:**
1. Consultar BR §5.2 → regras:
   - Só funciona em não-parceiros (markets/restaurantes sem acordo)
   - Ajudante ganha €4 fixos
   - €4 saem do ganho do principal (não custo Bora)
   - Dispatch normal escolhe o mais próximo (40s para aceitar)
2. Casos de teste a cobrir:
   - Happy path: principal pede ajuda, ajudante aceita, ambos recebem pagamento correcto
   - Edge case 1: pedido é de parceiro → RPC recusa (BR §5.2 "só não-parceiros")
   - Edge case 2: ajudante timeout 40s → próximo driver (BR §6.3)
   - Edge case 3: ganho do principal < €4 → bloquear (evitar saldo negativo)
3. Mock: Supabase via `mocktail`, `DispatchEngine` via instância real (é in-memory, safe).
4. Estrutura: `test/integration/driver_help_test.dart` com 4 grupos.

**Output esperado:**
```
✅ PLANO TESTE requestDriverHelp — BR §5.2
Ficheiro: test/integration/driver_help_test.dart (novo)
Grupos: [happy_path, partner_rejected, timeout_next_driver, negative_balance]
Mocks: Supabase (mocktail) + DispatchEngine real
Delegar a: executor (criar ficheiro + mocks)
```

**Failure mode:**
Falha se mockar `DispatchEngine` em memória — é lógica core, deve ser real. Falha se esquecer edge case do parceiro.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/` (recursivo) | Alvo dos testes |
| `supabase/functions/**` | Edge functions — teste via curl + mock Supabase client |
| `supabase/migrations/**` | Schema — teste via `supabase db reset` em local |
| `.claude/.ai/business_rules.md` §25.3 | Zonas protegidas — testes OK, edições NÃO |
| `analysis_options.yaml` | Regras de lint e strong-mode |
| `pubspec.yaml` | Dev dependencies (mocktail, test, integration_test) |
| skill `guardian` | Consultar antes de qualquer edit |
| skill `qa-engineer` | QA manual complementa testes automáticos |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber CI/CD** — alvo 80% cobertura em módulos core (matching, billing, payment). Buildkite + Bazel. Pull requests bloqueados se coverage baixa. Unit + widget + golden tests + integration.
>
> **iFood "Test Automation Squad"** — equipa dedicada de QA Engineers. Appium + Espresso + XCUITest para mobile. Contract tests entre microserviços (Pact).
>
> **Glovo** — Jenkins + coverage mínima 60% para PR merger. Mutation testing com Pitest em módulos críticos. E2E com Detox em React Native.
>
> **Bora equivalente:** actualmente sem test suite (projeto ainda em fase inicial — confirmado em CLAUDE.md "No test suite exists"). Plano: começar por `dart analyze` clean (0 errors) → testes de `PricingService` (read-only, crítico) → `DispatchEngine` → stores principais. Alvo inicial realista: 30% em módulos core.

---

## RESPONSABILIDADES

- ✅ Correr `dart analyze` e categorizar output por severidade
- ✅ Aplicar `dart fix --apply` para infos auto-fixable seguras
- ✅ Escalar errors em zonas protegidas a decision_engine
- ✅ Criar unit tests para funções críticas (pricing, dispatch capacity, token math)
- ✅ Criar widget tests para ecrãs de fluxo crítico (checkout, oferta de pedido)
- ✅ Propor estrutura de testes (`test/unit/`, `test/widget/`, `test/integration/`)

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Testes automáticos, dart analyze, coverage | **testing-engineer** (eu) |
| QA manual (ecrãs, cores, navegação) | `qa-engineer` |
| Refactor com testes antes | `refactor_guard` |
| Validação pré-execução | `guardian` |
| Testes de RLS / policies | `security-engineer` |

## NÃO PODE FAZER

- ❌ Editar código em zonas protegidas (BR §25.3) — só escalar
- ❌ Correr testes que modifiquem DB de produção (usar local/staging)
- ❌ Ignorar errors — têm prioridade sobre warnings e infos
- ❌ Mockar dispatch-engine em testes de dispatch (tem de ser integração real)
- ❌ Auto-aplicar `dart fix` sem verificar diff em ficheiros críticos

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §25.3 (zonas protegidas)
- Ordem: analyze → categorizar → auto-fix seguro → executor → escalar protegidos
- Nunca baixar coverage em módulos core
- Cada teste deve citar BR: `test('respects BR §6.4 MAX_ORDERS_PER_DRIVER', ...)`
- Ordem canónica: `decision_engine` → **testing-engineer** → `guardian` → `executor`
