# Passo 2 — Análise por Skill · Camada 6 — BACKEND

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### supabase_agent/rules (Camada 6 — BACKEND)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\supabase_agent\rules.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 70   ·   **H2:** 8   ·   **Tabelas:** 6

**Estado atual:** Defines and enforces the policy for all Supabase interactions. Every backend operation must comply with these rules before execution. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 178ch, "This skill should be used when..." ✗)
- Completude: **3**  (70 linhas, 8 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (1 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **8**  (refs código ✓, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `MCP client config`
- `supabase/ (general)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Stripe: API-only; no raw SQL from app (parity).

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### supabase_agent/executor (Camada 6 — BACKEND)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\supabase_agent\executor.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 78   ·   **H2:** 8   ·   **Tabelas:** 6

**Estado atual:** Step-by-step protocol for executing Supabase API operations safely. Runs only after `supabase_agent/rules.md` policy is satisfied. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 204ch, "This skill should be used when..." ✗)
- Completude: **3**  (78 linhas, 8 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (1 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **8**  (refs código ✓, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `MCP tool schemas`
- `supabase/functions/`

**Benchmarks Uber/iFood/Glovo relevantes:**
Supabase MCP docs (SELECT-first pattern).

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### supabase_engine/rules (Camada 6 — BACKEND)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\supabase_engine\rules.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 77   ·   **H2:** 9   ·   **Tabelas:** 6

**Estado atual:** Manages all Supabase backend access with safety, precision, and minimal alteration. Works alongside `supabase_agent` for policy compliance and executes via MCP. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 203ch, "This skill should be used when..." ✗)
- Completude: **3**  (77 linhas, 9 secções H2)
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
- `supabase/migrations/ (all)`

**Benchmarks Uber/iFood/Glovo relevantes:**
PostgreSQL engineering: migration-as-code; reversible by default.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

### supabase_engine/debug (Camada 6 — BACKEND)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\supabase_engine\debug.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 84   ·   **H2:** 8   ·   **Tabelas:** 6

**Estado atual:** Investigation and correction protocol for backend Supabase issues. Works within `supabase_engine` policy constraints. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 172ch, "This skill should be used when..." ✗)
- Completude: **3**  (84 linhas, 8 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (1 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **8**  (refs código ✓, refs BR ✓)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).

**Referências Bora App que deveriam estar na skill:**
- `supabase/debug_dispatch.sql`
- `supabase/0_audit.sql`

**Benchmarks Uber/iFood/Glovo relevantes:**
Supabase: pg_stat_statements + realtime logs.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### supabase_engine/queries (Camada 6 — BACKEND)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\supabase_engine\queries.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 78   ·   **H2:** 8   ·   **Tabelas:** 5

**Estado atual:** Step-by-step protocol for executing database queries efficiently and safely via Supabase MCP. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 175ch, "This skill should be used when..." ✗)
- Completude: **3**  (78 linhas, 8 secções H2)
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
- `supabase/migrations/ (SELECT-first patterns)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Supabase: RLS-aware queries only; never bypass via service_role in app.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

