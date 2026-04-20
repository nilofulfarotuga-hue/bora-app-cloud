# Passo 2 — Análise por Skill · Camada 2 — CONTROLE

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### guardian (Camada 2 — CONTROLE)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\guardian.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 117   ·   **H2:** 9   ·   **Tabelas:** 12

**Estado atual:** Pre-execution risk detector. Blocks dangerous changes before they happen. Runs before every `executor` call. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 191ch, "This skill should be used when..." ✓)
- Completude: **5**  (117 linhas, 9 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **0**  (refs código ✗, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes).

**Referências Bora App que deveriam estar na skill:**
- `lib/dispatch/dispatch_engine.dart (offer timer)`
- `lib/stores/driver_store.dart (realtime sub)`
- `lib/services/location_service.dart (GPS)`
- `lib/main.dart (ChangeNotifierProxyProvider chain)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: mobile-code pre-commit checklist (dispose/stream lifecycle); DoorDash: "null-safety lint" as blocker.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### flow_guard (Camada 2 — CONTROLE)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\flow_guard.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 142   ·   **H2:** 10   ·   **Tabelas:** 7

**Estado atual:** Enforces architectural boundaries and prevents dangerous structural changes. Does NOT execute changes. Blocks or warns before execution. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 232ch, "This skill should be used when..." ✓)
- Completude: **6**  (142 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **2**  (1 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **3**  (0 refs a lib/supabase, 5 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **2**  (refs código ✗, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Cross-link para `business_rules.md` (versão + secções relevantes).

**Referências Bora App que deveriam estar na skill:**
- `lib/main.dart (_RootNavigator + provider tree)`
- `lib/auth/auth_store.dart (dual-layer auth)`
- `lib/dispatch/dispatch_engine.dart (sequential loop)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: "Critical Path Protection" — any change to core auth/dispatch needs 2 approvals; iFood: blast-radius matrix.

**Risco de alteração:** MÉDIO   ·   **Esforço estimado:** MÉDIO

---

### refactor_guard (Camada 2 — CONTROLE)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\refactor_guard.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 122   ·   **H2:** 10   ·   **Tabelas:** 13

**Estado atual:** Analyses proposed changes before execution to detect refactor risk and suggest safer approaches. Does NOT execute. Blocks or redirects. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 226ch, "This skill should be used when..." ✓)
- Completude: **5**  (122 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **0**  (refs código ✗, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `lib/screens/driver_home_screen.dart (God Object risk)`
- `lib/stores/order_store.dart (~800 LoC)`
- `lib/services/pricing_service.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Google: "large refactor RFC"; Uber: multi-file refactor preview in CI.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### state_validator/rules (Camada 2 — CONTROLE)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\state_validator\rules.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 79   ·   **H2:** 9   ·   **Tabelas:** 6

**Estado atual:** Enforces the immutable OrderStatus state machine and prevents contradictory or invalid state transitions. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 188ch, "This skill should be used when..." ✗)
- Completude: **3**  (79 linhas, 9 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **5**  (0 refs a lib/supabase, 7 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **5**  (refs código ✗, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `lib/models/order_service_type.dart`
- `lib/stores/order_store.dart (_statusFlow + _advanceStatus)`
- `lib/screens/driver_order_action_helper.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber Eats: order state machine enforced as explicit FSM (not string); DoorDash: status transitions logged as append-only events.

**Risco de alteração:** MÉDIO   ·   **Esforço estimado:** MÉDIO

---

### state_validator/validation (Camada 2 — CONTROLE)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\state_validator\validation.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 75   ·   **H2:** 8   ·   **Tabelas:** 5

**Estado atual:** Step-by-step validation procedure. Run before AND after any change to order state or status. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 113ch, "This skill should be used when..." ✗)
- Completude: **3**  (75 linhas, 8 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (0 refs a lib/supabase, 2 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **3**  (refs código ✗, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `lib/stores/order_store.dart (_advanceStatus, _statusFlow)`
- `lib/models/order_model.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Same — FSM with invariant checks per transition.

**Risco de alteração:** MÉDIO   ·   **Esforço estimado:** MÉDIO

---

