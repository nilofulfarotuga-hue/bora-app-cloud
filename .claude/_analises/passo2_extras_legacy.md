# Passo 2 — Análise por Skill · EXTRAS / LEGACY (fora da arquitectura v2)

> Read-only analysis (Sub-fase 2.A). Nenhuma skill foi modificada.
> Fonte: `_skill_profiles.json` + `_skill_sections.json` + mapeamentos curados.

---

### (root) manager (EXTRAS / LEGACY (fora da arquitectura v2))
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\manager.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 92   ·   **H2:** 6   ·   **Tabelas:** 14

**Estado atual:** Strategic coordinator. Decides what to do, when, and with which skill. Does NOT execute directly. Routes to the correct skill. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 205ch, "This skill should be used when..." ✓)
- Completude: **4**  (92 linhas, 6 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **2**  (1 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **0**  (0 refs a lib/supabase, 0 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **0**  (refs código ✗, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.
- Sem secção FRONTEIRAS — risco de overlap com skills vizinhas.
- Sem secção NÃO PODE FAZER — escopo pode ser invadido.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Cross-link para `business_rules.md` (versão + secções relevantes). · Secção `NÃO PODE FAZER` (falta actualmente). · Secção `FRONTEIRAS` com tabela de delegação (falta).

**Referências Bora App que deveriam estar na skill:**
- `all skills`

**Benchmarks Uber/iFood/Glovo relevantes:**
(sem benchmark mapeado)

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### (root) tester (EXTRAS / LEGACY (fora da arquitectura v2))
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\tester.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 107   ·   **H2:** 6   ·   **Tabelas:** 0

**Estado atual:** Simulate real system behavior and validate correctness. Does NOT change code. Only validates logic and flow. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 217ch, "This skill should be used when..." ✓)
- Completude: **4**  (107 linhas, 6 secções H2)
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
- Sem secção FRONTEIRAS — risco de overlap com skills vizinhas.
- Sem secção NÃO PODE FAZER — escopo pode ser invadido.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes). · Secção `NÃO PODE FAZER` (falta actualmente). · Secção `FRONTEIRAS` com tabela de delegação (falta).

**Referências Bora App que deveriam estar na skill:**
- `lib/dispatch/dispatch_engine.dart`
- `lib/stores/order_store.dart`

**Benchmarks Uber/iFood/Glovo relevantes:**
(sem benchmark mapeado)

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### (root) auto_debug (EXTRAS / LEGACY (fora da arquitectura v2))
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\auto_debug.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 108   ·   **H2:** 7   ·   **Tabelas:** 0

**Estado atual:** Passive monitoring and detection agent. Does NOT execute changes. Does NOT modify code. Only: Analyzes → Detects → Reports. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 179ch, "This skill should be used when..." ✓)
- Completude: **4**  (108 linhas, 7 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **2**  (0 refs a lib/supabase, 3 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **0**  (refs código ✗, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero referências a código real do Bora — skill flutua sem ancoragem.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.
- Sem secção FRONTEIRAS — risco de overlap com skills vizinhas.
- Sem secção NÃO PODE FAZER — escopo pode ser invadido.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes). · Secção `NÃO PODE FAZER` (falta actualmente). · Secção `FRONTEIRAS` com tabela de delegação (falta).

**Referências Bora App que deveriam estar na skill:**
- `legacy — not referenced in new architecture`

**Benchmarks Uber/iFood/Glovo relevantes:**
(sem benchmark mapeado)

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### (root) auto_runner (EXTRAS / LEGACY (fora da arquitectura v2))
**Caminho:** `c:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\auto_runner.md`   ·   **Versão:** 2.0.0   ·   **Linhas:** 103   ·   **H2:** 6   ·   **Tabelas:** 0

**Estado atual:** Active continuous monitoring agent. Detects problems silently. Does NOT fix directly. Generates alerts for manager. ---...

**Análise de qualidade (0-10):**
- Clareza do trigger: **8**  (desc 166ch, "This skill should be used when..." ✓)
- Completude: **4**  (103 linhas, 6 secções H2)
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
- Sem secção FRONTEIRAS — risco de overlap com skills vizinhas.
- Sem secção NÃO PODE FAZER — escopo pode ser invadido.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Referências directas a ficheiros `lib/**` ou `supabase/**` do Bora (não abstracto). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes). · Secção `NÃO PODE FAZER` (falta actualmente). · Secção `FRONTEIRAS` com tabela de delegação (falta).

**Referências Bora App que deveriam estar na skill:**
- `legacy — not referenced in new architecture`

**Benchmarks Uber/iFood/Glovo relevantes:**
(sem benchmark mapeado)

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

### (root) memory_store
_(erro a carregar perfil)_

### (plugin) ceo-ai/SKILL (EXTRAS / LEGACY (fora da arquitectura v2))
**Caminho:** `.claude/skills/ceo-ai/SKILL.md`   ·   **Versão:** (no version)   ·   **Linhas:** 263   ·   **H2:** 13   ·   **Tabelas:** 0

**Estado atual:** (no ROLE/OBJECTIVE)...

**Análise de qualidade (0-10):**
- Clareza do trigger: **3**  (desc 9ch, "This skill should be used when..." ✗)
- Completude: **10**  (263 linhas, 13 secções H2)
- Exemplos concretos: **0**  (0 keyword-hits de "exemplo/example/cenário")
- MODO PROTECÇÃO TOTAL: **0**  (0 hits de read-only/approved_by/não modifica)
- Especificidade Bora App: **1**  (1 refs a lib/supabase, 1 refs a Store/Engine/Service)
- Benchmarks Uber/iFood/Glovo: **0**  (0 menções directas)
- Actualização vs código real: **5**  (refs código ✓, refs BR ✗)

**Gaps identificados:**
- Zero exemplos worked — impossível saber como chamar esta skill na prática.
- Zero comparação com Uber/iFood/Glovo — não transmite nível de maturidade da indústria.
- Modo protecção fraco — não é claro que a skill é read-only ou que pede approved_by.
- 1 placeholder(s) por preencher.
- Sem secção FRONTEIRAS — risco de overlap com skills vizinhas.
- Sem secção NÃO PODE FAZER — escopo pode ser invadido.

**Melhorias propostas:**
- **ADICIONAR:** Secção `EXEMPLOS CONCRETOS` com 2–3 cenários reais do Bora (input → saída esperada). · Secção `BENCHMARK` comparando a abordagem com Uber/iFood/Glovo. · Regra explícita de MODO PROTECÇÃO (read-only por default; escrita só com approved_by). · Cross-link para `business_rules.md` (versão + secções relevantes). · Secção `NÃO PODE FAZER` (falta actualmente). · Secção `FRONTEIRAS` com tabela de delegação (falta). · Frontmatter com `version:` (actualmente ausente).
- **REESCREVER:** Remover 1 placeholder(s) (`{modo}`, `TODO`, etc.) e substituir por conteúdo real.

**Referências Bora App que deveriam estar na skill:**
- `.claude/skills/ceo-ai/ (plugin-style, outside main system)`

**Benchmarks Uber/iFood/Glovo relevantes:**
(sem benchmark mapeado)

**Risco de alteração:** BAIXO   ·   **Esforço estimado:** BAIXO

---

