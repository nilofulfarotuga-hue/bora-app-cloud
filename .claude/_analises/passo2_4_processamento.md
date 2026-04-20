# Passo 2 — Análise por Skill · Camada 4 — PROCESSAMENTO

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### performance_watcher (Camada 4 — PROCESSAMENTO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\performance_watcher.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 118   ·   **H2:** 10   ·   **Tabelas:** 12

**Estado atual:** Analyses the app for performance issues, excessive resource usage, and battery drain. Does NOT change code. Identifies issues and suggests optimisations. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 195ch, "This skill should be used when..." ✓)
- Completude: **5**  (118 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
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
- `lib/services/location_service.dart (GPS polling)`
- `lib/services/driver_location_service.dart (12-step animation)`
- `lib/stores/driver_store.dart`
- `lib/stores/order_store.dart (3s Timer.periodic)`
- `lib/screens/driver_map_screen.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: Firebase Performance + custom traces; iFood: Datadog RUM on mobile.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### system_validator (Camada 4 — PROCESSAMENTO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\system_validator.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 124   ·   **H2:** 9   ·   **Tabelas:** 7

**Estado atual:** Validates the complete bora_app system end-to-end. Does NOT change code. Only validates and reports. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 236ch, "This skill should be used when..." ✓)
- Completude: **5**  (124 linhas, 9 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (0 refs a lib/supabase, 1 refs a Store/Engine/Service)
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
- `All stores + services`
- `supabase/migrations/ (RLS)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: "Ready for Production" checklist per service; Glovo: auto-smoke tests post-deploy.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### fix_realtime (Camada 4 — PROCESSAMENTO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\fix_realtime.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 90   ·   **H2:** 8   ·   **Tabelas:** 7

**Estado atual:** Investigates and proposes fixes for specific realtime synchronization bugs between Flutter and Supabase. Bug-fixer only — for policy/architecture changes delegate to `realtime_engine`. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 230ch, "This skill should be used when..." ✓)
- Completude: **4**  (90 linhas, 8 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
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
- `lib/stores/order_store.dart (orders_channel)`
- `lib/stores/driver_store.dart (public:drivers)`
- `supabase/migration_backend_dispatch.sql`

**Benchmarks Uber/iFood/Glovo relevantes:**
Glovo: driver-location sync lag SLO <2s; Uber: WebSocket reconnection with jittered backoff.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### fix_auth (Camada 4 — PROCESSAMENTO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\fix_auth.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 111   ·   **H2:** 10   ·   **Tabelas:** 19

**Estado atual:** Investigates and proposes fixes for authentication and authorization bugs against Supabase Auth + RLS. Specialist in distinguishing client-side, JWT, RLS, and session-persistence root causes. Runs BEFORE any auth-related...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 235ch, "This skill should be used when..." ✓)
- Completude: **4**  (111 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **3**  (5 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **8**  (refs código ✓, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `lib/auth/auth_store.dart`
- `lib/services/auth_service.dart`
- `lib/screens/driver_signup_screen.dart`
- `lib/stores/session_store.dart`
- `supabase/migrations/20260413000000_bora_tokens_rls.sql`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: identity service with explicit per-role auth matrix (rider/driver/restaurant); iFood: multi-tenant JWT with role claim.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### dispatch_bugfix (Camada 4 — PROCESSAMENTO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\dispatch_bugfix.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 122   ·   **H2:** 10   ·   **Tabelas:** 8

**Estado atual:** Investigates and corrects pontual bugs in the existing sequential dispatch implementation. Never implements new business rules — only fixes regressions and incidents. For new rules (queue 200m/5s, capacity 1↔3, in-store ...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 321ch, "This skill should be used when..." ✓)
- Completude: **5**  (122 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
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
- `lib/dispatch/dispatch_engine.dart`
- `lib/dispatch/dispatch_service.dart`
- `lib/dispatch/driver_assignment_service.dart`
- `lib/dispatch/driver_capacity_service.dart`
- `supabase/migration_trigger_dispatch.sql`

**Benchmarks Uber/iFood/Glovo relevantes:**
DoorDash: dispatch incident playbook; Uber: "Re-bid" fallback when offer times out.

**Risco de alteração:** ALTO   ·   **Esforço estimado:** MÉDIO

---

