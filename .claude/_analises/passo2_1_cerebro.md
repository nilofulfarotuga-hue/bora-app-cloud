# Passo 2 — Análise por Skill · Camada 1 — CÉREBRO

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### decision_engine (Camada 1 — CÉREBRO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\decision_engine.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 121   ·   **H2:** 10   ·   **Tabelas:** 26

**Estado atual:** Evaluates proposed changes before execution and recommends the best course of action. Does NOT execute. Informs and recommends. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 232ch, "This skill should be used when..." ✓)
- Completude: **5**  (121 linhas, 10 secções H2)
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
- `CLAUDE.md (Validation Gate)`
- `lib/dispatch/*.dart (high-risk area)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: "decision memos" pre-implementation; iFood: RFC template before changes; Glovo: risk-impact matrix for backend changes.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### memory (Camada 1 — CÉREBRO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\memory.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 116   ·   **H2:** 9   ·   **Tabelas:** 6

**Estado atual:** Manages the project's long-term memory. Reads and writes `.claude/.ai/memory/memory_store.md`. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 212ch, "This skill should be used when..." ✓)
- Completude: **5**  (116 linhas, 9 secções H2)
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
- `.claude/.ai/memory/memory_store.md`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: Post-Mortem database (searchable incident log); Glovo: ADR (Architecture Decision Records).

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### learning_engine (Camada 1 — CÉREBRO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\learning_engine.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 142   ·   **H2:** 11   ·   **Tabelas:** 6

**Estado atual:** Analyses the project's history to detect recurring patterns, predict problems, and improve future decisions. ❌ Does NOT execute changes ❌ Does NOT suggest specific code ✅ Analyses patterns and suggests process improvemen...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 216ch, "This skill should be used when..." ✓)
- Completude: **6**  (142 linhas, 11 secções H2)
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
- `.claude/.ai/memory/memory_store.md`
- `git log (recent commits)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Netflix/Uber: post-incident retrospective protocol; iFood: weekly bug-pattern retro.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### product_analyst (Camada 1 — CÉREBRO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\product_analyst.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 114   ·   **H2:** 10   ·   **Tabelas:** 12

**Estado atual:** Analyzes the app from a product and user experience perspective. ❌ Does NOT execute code ❌ Does NOT modify files ❌ Does NOT alter the system ✅ Only suggests — formatted, prioritized, actionable ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 214ch, "This skill should be used when..." ✓)
- Completude: **5**  (114 linhas, 10 secções H2)
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
- `lib/screens/client_home_screen.dart`
- `lib/screens/cart_screen.dart`
- `lib/screens/driver_home_screen.dart`
- `lib/screens/partner_dashboard_screen.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber: North Star metric + RICE scoring; iFood: quarterly UX audits per persona (client/driver/partner); Glovo: conversion funnel deep-dive per market.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### decision_registry (Camada 1 — CÉREBRO)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\decision_registry.md`   ·   **Versão:** 1.0.0   ·   **Linhas:** 162   ·   **H2:** 10   ·   **Tabelas:** 67

**Estado atual:** Indexed lookup of every locked decision in the Bora project. Complement to `memory` (which is append-only and chronological) — registry is queryable by topic. Always consulted BEFORE proposing changes to dispatch, paymen...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 250ch, "This skill should be used when..." ✓)
- Completude: **6**  (162 linhas, 10 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **2**  (1 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **3**  (refs código ✗, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo.

**Referências Bora App que deveriam estar na skill:**
- `.claude/.ai/business_rules.md (source of truth)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Uber/Stripe: "Tech Radar" + decision log; Glovo: BR versioning with auto-diff alerts.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

