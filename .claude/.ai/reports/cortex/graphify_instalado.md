# Graphify instalado — relatório (2026-07-08)

Grafo de **CÓDIGO** do Bora, partilhado (Claude Code + Hermes + ponte web). Autónomo, zona verde,
aditivo e reversível. **A Trava do banco tem prioridade absoluta e ficou 100% intacta.**

---

## ✅ Passo 1 — Trava preservada (prioridade absoluta)

- Backup de `settings.json` **e** `settings.local.json` antes de tocar em nada
  (`.claude/settings.json.bak_preGraphify_20260708_194503` + `.local`).
- **NÃO corri `graphify claude install`** — ele reescreve `.claude/settings.json` (o ficheiro da
  Trava, negado a Edit/Write por design) e mexe no CLAUDE.md. Confirmei no código-fonte do pacote
  (`__main__.py::_install_claude_hook`) que ele faz `json.dumps` sobre o settings.json protegido.
- O hook opcional de "nudge" do Graphify (sugerir `graphify query` antes de grep/read — **não
  bloqueia nada**) ficou como **referência opt-in** em `.claude/settings.example.json`, com
  instruções de merge manual (só o Danilo pode escrever settings.local.json).
- **Selftest da Trava: 12/12 ANTES e 12/12 DEPOIS.** `git diff` de `settings.json` +
  `settings.local.json` = **vazio** (byte-a-byte intactos). Os 2 hooks (`protege-banco.sh` +
  `protege-dinheiro.sh`) continuam a disparar.

## ✅ Passo 2 — Instalado

- Pré-req: Python 3.12.10 ✅. **`uv` não existia** → instalei via `pip install uv` (uv 0.11.28).
- `uv tool install "graphifyy[mcp]"` → **graphify 0.9.10**. Exes em `C:\Users\danil\.local\bin\`
  (`graphify.exe`, `graphify-mcp.exe`). O extra `[mcp]` foi necessário para o servidor MCP arrancar.

## ✅ Passo 3 — Grafo gerado

- `graphify update .` (AST, **0 tokens · 0 input · 0 output**).
- **18 993 nós · 24 828 arestas · 1 098 comunidades** · 1 884 ficheiros.
- **Sem imagens/media** (naturalmente 0 nós no modo código) + `.graphifyignore` a excluir o vault
  Obsidian, `assets/`, backups/relatórios e **JS minificado de crawlers** (2ª passagem
  20 438→18 993 nós, tirou o ruído de símbolos de 1 letra).
- SQL: os `.sql` entram como ficheiros/nós no grafo (não há tree-sitter SQL para símbolos finos;
  schema vivo via `--postgres DSN` = melhoria futura, exige DSN — não corrido por prudência 🔴).
- Saída: `graph.json` (18 MB), `GRAPH_REPORT.md`, **`GRAPH_TREE.html`** (viz D3, 1,2 MB),
  `manifest.json`. Pasta `graphify-out/` **gitignored**.
- **Benchmark: 78,2× menos tokens por consulta** (~16 k vs ~1,27 M naive). Validado end-to-end:
  `query "order status flow"` → order_model/advance_status/dispatch; `explain "OrderStore"` →
  ChangeNotifier + 47 ecrãs.
- Git hook `post-commit`+`post-checkout` instalados (`.git/hooks/`, **separados** da Trava em
  `.claude/hooks/` — sem colisão) → grafo auto-atualiza a cada commit.

## ✅ Passo 4 — Partilha

- **Claude Code:** servidor MCP **read-only** registado em `.mcp.json` (stdio). Ativo na próxima
  sessão (nano-banana preservado). 10 ferramentas, **todas de leitura** — `query_graph`, `get_node`,
  `get_neighbors`, `get_community`, `god_nodes`, `graph_stats`, `shortest_path`, `list_prs`,
  `get_pr_impact`, `triage_prs`. **Zero ferramentas de escrita** → o filtro "só leitura" é
  garantido por design.
- **Hermes (VPS):** **não liguei autonomamente** (mexer na config de produção do Hermes à noite é
  sensível; além disso o grafo vive neste PC e a ponte é PC→VPS, unidirecional). Config pronta:
  - Skill: `graphify install --platform hermes` (dropa `SKILL.md` em
    `%LOCALAPPDATA%\hermes\skills\graphify\`) — correr onde o Hermes correr.
  - MCP no `config.yaml` do Hermes (só leitura):
    ```yaml
    mcp_servers:
      graphify:
        command: "C:/Users/danil/.local/bin/graphify-mcp.exe"
        args: ["--graph", "graphify-out/graph.json", "--transport", "stdio"]
        allowed_tools: [query_graph, get_node, get_neighbors, get_community,
                        god_nodes, graph_stats, shortest_path]
    ```
  - Confirmar depois com `hermes mcp list`.
- **Ponte web (opcional):** `graphify-mcp` suporta HTTP + api-key nativamente —
  `graphify-mcp --transport http --host 127.0.0.1 --port 8080 --api-key <KEY>` (env
  `GRAPHIFY_API_KEY`), atrás de HTTPS como o Córtex. Deixado como **nota** (exige
  reverse-proxy/domínio — "trabalho grande", não bloqueia o resto).

## ✅ Passo 5 — Registado no Córtex

- Página proposta na Central do Córtex: `wiki/codigo/graphify` → **`prop-1b6b914b`** (write está
  off → usei `cortex_propor`; fila de aprovação do admin).
- ADR no repo: `.claude/.ai/decisions/2026-07-08-adotar-graphify-grafo-codigo.md`.
- Doc de uso: `docs/graphify.md`.

---

## ⚠️ Bugs / riscos

- **NENHUM chegou perto da Trava** — ela foi tratada primeiro e reconfirmada (12/12) no fim.
- **Bug do pacote (upstream):** `graphify-mcp` falha com `ModuleNotFoundError: mcp` se instalado
  sem o extra — o `README`/help sugere `graphify claude install` mas não avisa que o servidor MCP
  precisa de `graphifyy[mcp]`. Resolvido reinstalando com o extra.
- **Aviso do extractor:** 114 ficheiros (JSON de dados `.ai_*`, etc.) produzem 0 nós — esperado
  (não são código); ficam fora do grafo.
- **Risco menor:** o hook `post-commit` acrescenta latência pequena a cada commit (re-extrai só os
  ficheiros alterados). Reversível: `graphify hook uninstall`.
- **Reverter tudo:** `graphify hook uninstall` + `graphify uninstall --purge` + remover a entrada
  `graphify` de `.mcp.json`.

## Ficheiros versionados nesta tarefa

`.gitignore` (+graphify-out/), `.graphifyignore`, `.claude/settings.example.json`, `docs/graphify.md`,
`.claude/.ai/decisions/2026-07-08-adotar-graphify-grafo-codigo.md`, este relatório.
(Não versionado: `graphify-out/`, `.mcp.json` e backups `*.bak` — gitignored.)
