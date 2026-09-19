# Graphify — mapa de CÓDIGO do Bora (grafo consultável)

**O quê:** transforma o repo `bora_app` num grafo de código consultável (`graphify-out/graph.json`)
para os agentes **pararem de reler ficheiros inteiros** — pergunta-se ao grafo em vez de fazer
grep/Read às cegas. Extração por **AST (tree-sitter), 0 tokens** — determinística, não gasta LLM.

- Pacote PyPI: `graphifyy` (dois "y") · comando: `graphify` · repo: `safishamsi/graphify`
- Instalado via `uv tool install "graphifyy[mcp]"` → exes em `C:\Users\danil\.local\bin\`
  (`graphify.exe`, `graphify-mcp.exe`). **Não está no PATH** por defeito — usar caminho absoluto
  ou `uv tool update-shell` + novo terminal.

## Estado do grafo (última extração)

- **18 993 nós · 24 828 arestas · 1 098 comunidades** · 1 884 ficheiros · **custo: 0 tokens**
- Saída em `graphify-out/` (**gitignored** — regenerável, não versionado):
  `graph.json` (18 MB), `GRAPH_REPORT.md`, `GRAPH_TREE.html` (viz D3), `manifest.json`.
- Só CÓDIGO + docs estruturais. Exclusões em `.graphifyignore`: vault Obsidian, `assets/`,
  imagens/media, JS minificado de crawlers, backups/relatórios do Cérebro.

## Consultar (read-only, 0 tokens)

```bash
GR="C:/Users/danil/.local/bin/graphify"
"$GR" query "how does an order advance through its status flow"   # BFS por uma pergunta
"$GR" explain "OrderStore"                                        # nó + vizinhos (quem usa)
"$GR" path "checkout_screen.dart" "PricingService"               # caminho mais curto A→B
"$GR" affected "PricingService"                                  # o que é impactado por X
"$GR" tree                                                       # regenera GRAPH_TREE.html
```

## Manter fresco

- **Automático:** git hook `post-commit` (em `.git/hooks/`, instalado por `graphify hook install`)
  re-extrai os ficheiros alterados e reconstrói `graph.json` após cada commit. Não polui o git
  (a saída é gitignored).
- **Manual (após refactor grande):** `graphify update . --force`.
- Freshness: o `GRAPH_REPORT.md` regista o commit-base; comparar com `git rev-parse HEAD`.

## MCP — acesso por assistentes

Servidor MCP **read-only** (`graphify-mcp`) expõe 10 ferramentas de leitura: `query_graph`,
`get_node`, `get_neighbors`, `get_community`, `god_nodes`, `graph_stats`, `shortest_path`,
`list_prs`, `get_pr_impact`, `triage_prs`. **Nenhuma ferramenta de escrita** — o grafo nunca
altera código.

- **Claude Code:** já registado em `.mcp.json` (stdio). Fica ativo na próxima sessão.
- **Hermes (VPS):** ver `## Partilha` no relatório
  `.claude/.ai/reports/cortex/graphify_instalado.md` — config pronta a aplicar (não foi ligada
  autonomamente por mexer na config de produção do Hermes).
- **Ponte web (como o Córtex):** `graphify-mcp --transport http --api-key <KEY>` (env
  `GRAPHIFY_API_KEY`) atrás de HTTPS. Deixado como nota (exige reverse-proxy/domínio).

## Segurança / Trava

Aditivo e reversível. Graphify **só LÊ** código. A **Trava do banco tem prioridade absoluta**:
`settings.json`/`settings.local.json` **não foram tocados** e o selftest continua **12/12** após
a instalação. O hook opcional de "nudge" do Graphify (sugerir `graphify query` antes de grep) fica
como referência opt-in em `.claude/settings.example.json` — **não** foi aplicado à Trava.

Remover tudo: `graphify uninstall --purge` + `graphify hook uninstall`.
