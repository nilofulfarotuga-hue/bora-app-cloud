# Resumo da dívida do Córtex (`_debt.md` + `log.md`)

_Gerado 2026-07-09 — leitura de `.claude/.ai/knowledge/_debt.md` (última confirmação 2026-07-08) e `log.md`._

A régua automática de confiança ainda **não corre a sério** (falta a 1ª corrida real do `cortex_nightly --report`), por isso a dívida é a lista **conhecida à mão**:

- **`INDEX.md` (linha ~78)** — aponta para o vault velho `Desktop\Bora`, já **superado**. Erro factual concreto, zona verde, correção rápida.
- **`permanente/**` sem frontmatter de identidade** — `origem` por carimbar (Bloco 1 faseado). O `log.md` mostra que o `bibliotecario-cerebro` já aplicou frontmatter em `permanente/**` a 2026-07-08, logo pode estar **parcialmente resolvido** — falta reconfirmar.
- **`_importado-velho/**` (33)** — arquivo histórico sem `origem` verificável; manter como arquivo, **não** promover.
- **`inbox/**` (9 sessões)** — em janela de 14 dias; o `cortex_nightly` decide promover/descartar.

**Recomendação — rever primeiro o `INDEX.md`:** é o único item com erro factual (ponteiro para vault superado), é o ficheiro que todos os agentes lêem ao arrancar, e a correção é barata (handoff ao `bibliotecario-cerebro` → apontar `.obsidian-vault/`). A seguir, reconfirmar o frontmatter de `permanente/**` e disparar a 1ª corrida do `cortex_nightly` para tornar a dívida numérica em vez de estimada à mão.
