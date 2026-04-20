# Passo 2 — Análise por Skill · Camada 5 — ESPECIALISTAS DE DOMÍNIO

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### realtime_engine/rules (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\realtime_engine\rules.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 68   ·   **H2:** 8   ·   **Tabelas:** 6

**Estado atual:** Defines and enforces realtime sync architecture for the Bora app. Policy layer — not a bug fixer. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 176ch, "This skill should be used when..." ✗)
- Completude: **3**  (68 linhas, 8 secções H2)
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
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `lib/stores/order_store.dart`
- `lib/stores/driver_store.dart`
- `lib/stores/chat_store.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: fan-out to only subscribed clients (per-order channel); Glovo: Redis pub-sub for driver pings.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

### realtime_engine/sync (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\realtime_engine\sync.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 71   ·   **H2:** 7   ·   **Tabelas:** 6

**Estado atual:** Step-by-step procedure for establishing, maintaining, and tearing down a Supabase Realtime channel correctly. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 129ch, "This skill should be used when..." ✗)
- Completude: **3**  (71 linhas, 7 secções H2)
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
- `lib/stores/order_store.dart (_subscribeToChannel)`
- `lib/stores/driver_store.dart (interpolation)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: Pelican system (per-entity streams); iFood: event-sourced order updates.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

### realtime_engine/debug (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\realtime_engine\debug.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 62   ·   **H2:** 7   ·   **Tabelas:** 5

**Estado atual:** Quick triage tool for realtime issues. Identify failure point before calling `fix_realtime` for full investigation. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 170ch, "This skill should be used when..." ✗)
- Completude: **2**  (62 linhas, 7 secções H2)
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
- `supabase logs (realtime channel)`
- `lib/stores/order_store.dart (_resubscribeWithDelay)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: realtime latency heatmaps; Glovo: per-channel subscription audit.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

### map_master (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\map_master.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 123   ·   **H2:** 10   ·   **Tabelas:** 7

**Estado atual:** Expert in all map, GPS, and location tracking concerns for the bora_app. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 251ch, "This skill should be used when..." ✓)
- Completude: **5**  (123 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **6**  (4 refs a lib/supabase, 5 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **10**  (refs código ✓, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `lib/config/maps_config.dart (Google API key)`
- `lib/services/location_service.dart`
- `lib/services/directions_service*.dart`
- `lib/utils/map_utils.dart (toGMaps extension)`
- `lib/screens/driver_map_screen.dart`
- `lib/screens/map_screen.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: H3 hex grid for geospatial indexing; iFood: pre-cached routing corridors; Glovo: driver-mesh GPS dedup.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### dispatch_manager (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\dispatch_manager.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 121   ·   **H2:** 8   ·   **Tabelas:** 8

**Estado atual:** Owns all dispatch business rules. The single skill responsible for implementing how drivers are selected, queued, offered, and re-dispatched. Domain authority for `business_rules.md` sections: Dispatch, Capacidade, Fila,...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 288ch, "This skill should be used when..." ✓)
- Completude: **5**  (121 linhas, 8 secções H2)
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
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `lib/dispatch/dispatch_engine.dart (_offerTimeout 10s)`
- `lib/dispatch/driver_capacity_service.dart (1↔3 capacity, 800m batching)`
- `lib/dispatch/dispatch_service.dart`
- `supabase/migrations/20260415140000_dispatch_trigger_pgcron.sql`
- `lib/config/business_rules.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: MOE/POE (Matching Optimization Engine) with capacity-aware; DoorDash: "Batch matching" score `combined_time < indiv × 1.2` (exact mirror); Glovo: priority lanes for in-store shoppers.

**Risco de alteração:** ALTO   ·   **Esforço estimado:** MÉDIO

---

### payment_manager (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\payment_manager.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 118   ·   **H2:** 8   ·   **Tabelas:** 7

**Estado atual:** Owns all financial flows. Single skill responsible for charging, refunding, reconciling, and enforcing the +15% invisible markup and cancellation fees. Domain authority for `business_rules.md` sections: Pagamento, Não Pa...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 332ch, "This skill should be used when..." ✓)
- Completude: **5**  (118 linhas, 8 secções H2)
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
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `lib/services/payment_service.dart (Stripe/MBWay/Cash)`
- `supabase/functions/create-payment-intent/`
- `supabase/functions/confirm-mbway-payment/`
- `supabase/functions/stripe-webhook/`
- `supabase/migrations/20260409000001_order_financial_split.sql`
- `supabase/migrations/20260409000002_financial_ledger.sql`
- `supabase/migrations/20260409000005_financial_hardening.sql`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: PaymentIntent + 3DS SCA (EU); iFood: MBWay integration via SIBS; Glovo: escrow pre-auth before dispatch (identical to BR #14).

**Risco de alteração:** ALTO   ·   **Esforço estimado:** ALTO

---

### token_manager (Camada 5 — ESPECIALISTAS DE DOMÍNIO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\token_manager.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 101   ·   **H2:** 8   ·   **Tabelas:** 6

**Estado atual:** Owns the token economy. Single skill responsible for earning, consuming, expiring, and converting tokens. Domain authority for `business_rules.md` section: Tokens. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 232ch, "This skill should be used when..." ✓)
- Completude: **4**  (101 linhas, 8 secções H2)
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
- 1 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `supabase/migrations/20260404000000_bora_tokens.sql`
- `supabase/migrations/20260404000001_bora_tokens_type_fix.sql`
- `supabase/migrations/20260404000002_consume_tokens.sql`
- `supabase/migrations/20260413000000_bora_tokens_rls.sql`
- `lib/services/pricing_service.dart`
- `lib/screens/cart_screen.dart (token toggle)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber Rewards: FIFO expiry + cap per ride; iFood: cashback with configurable discount ceiling; Glovo Prime: credits with TTL.

**Risco de alteração:** ALTO   ·   **Esforço estimado:** ALTO

---

