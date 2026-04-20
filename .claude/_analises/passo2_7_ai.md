# Passo 2 — Análise por Skill · Camada 7 — AI

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### prompt_engine/rules (Camada 7 — AI)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\prompt_engine\rules.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 73   ·   **H2:** 9   ·   **Tabelas:** 5

**Estado atual:** Defines structural rules for all Bora prompts. Every prompt generated for this system must follow these conventions. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 179ch, "This skill should be used when..." ✗)
- Completude: **3**  (73 linhas, 9 secções H2)
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
- 5 placeholder(s) por preencher.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by).
- **REESCREVER:** Remover 5 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `.claude/.ai/skills/ (meta)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Anthropic: "Write prompts like PRs"; OpenAI: prompt versioning with test suite.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

### prompt_engine/generator (Camada 7 — AI)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\prompt_engine\generator.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 164   ·   **H2:** 10   ·   **Tabelas:** 5

**Estado atual:** Library of concrete, ready-to-use prompts for common Bora development scenarios. Replaces ad-hoc prompt writing with battle-tested templates. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 189ch, "This skill should be used when..." ✗)
- Completude: **7**  (164 linhas, 10 secções H2)
- Exemplos concretos: **2**  (1 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **6**  (3 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (0 refs a lib/supabase, 1 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **3**  (refs código ✗, refs BR ✓)

**Gaps identificados:**
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.

**Melhorias propostas:**
- **ADICIONAR:** Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo.

**Referências Bora App que deveriam estar na skill:**
- `.claude/.ai/skills/ (meta)`

**Benchmarks Uber/iFood/Glovo relevantes:**
Anthropic prompt library; LangChain PromptTemplate with few-shot examples.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### prompt_engine/optimizer (Camada 7 — AI)
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\skills\prompt_engine\optimizer.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 66   ·   **H2:** 8   ·   **Tabelas:** 5

**Estado atual:** Cleans and simplifies existing prompts. Read-only analysis of input prompt → produce leaner version preserving full meaning. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **6**  (desc 176ch, "This skill should be used when..." ✗)
- Completude: **3**  (66 linhas, 8 secções H2)
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
- `.claude/.ai/skills/ (meta)`

**Benchmarks Uber/iFood/Glovo relevantes:**
DSPy: automated prompt optimization with metrics.

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** MÉDIO

---

