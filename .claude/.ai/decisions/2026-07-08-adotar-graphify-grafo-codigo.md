# ADR 2026-07-08 — Adotar Graphify (grafo de CÓDIGO do Bora)

**Estado:** aceite · **Zona:** 🟢 verde (aditivo, reversível, só leitura de código)

## Contexto

O Córtex guarda conhecimento de **negócio**. Faltava um mapa do **código** (Dart/SQL/Edge
Functions) consultável, para os agentes pararem de reler ficheiros inteiros a cada tarefa —
o principal desperdício de tokens. Grafos de dependências mantidos à mão apodrecem.

## Decisão

Adotar **Graphify** (`graphifyy` no PyPI, comando `graphify`, repo `safishamsi/graphify`),
que extrai um grafo por **AST (tree-sitter), 0 tokens**, determinístico e auto-atualizável.

- Grafo em `graphify-out/` (**gitignored** — regenerável).
- Fresco por **git hook `post-commit`** (re-extrai só ficheiros alterados).
- Acesso **read-only** via MCP (`graphify-mcp`, 10 ferramentas de leitura) — registado em
  `.mcp.json` para o Claude Code; config do Hermes/ponte web documentada no relatório.

## Porquê (vs alternativas)

- **vs reler ficheiros:** `query`/`explain`/`path`/`affected` devolvem o subgrafo relevante a
  custo ~0, em vez de N×Read. Economia directa de tokens — o objetivo.
- **vs grafo manual:** o AST reconstrói-se a cada commit; não há drift.
- **vs só o Córtex:** complementar — Córtex = negócio, Graphify = código. Não se sobrepõem.

## Envelope de segurança (Trava tem prioridade absoluta)

- Graphify **só LÊ** código; **nunca** altera. Aditivo e reversível (`graphify uninstall --purge`).
- **NÃO** foi corrido `graphify claude install` — ele reescreve `settings.json` (a Trava) + CLAUDE.md.
  O hook opcional de "nudge" ficou como referência opt-in em `.claude/settings.example.json`.
- `settings.json`/`settings.local.json` **intactos**; **selftest da Trava 12/12** antes e depois.

## Consequências

- **+** Consultas de arquitetura baratas; onboarding de agentes mais rápido; mapa sempre fresco.
- **−** ~18 MB de `graph.json` local (gitignored); `post-commit` acrescenta latência pequena por
  commit; SQL só entra como ficheiro/nó (sem tree-sitter SQL) — schema vivo via `--postgres DSN`
  fica como melhoria futura.

Doc de uso: `docs/graphify.md`.
