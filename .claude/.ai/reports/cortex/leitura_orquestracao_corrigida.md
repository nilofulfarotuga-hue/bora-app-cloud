# Leitura da pasta orquestracao/ corrigida (2026-07-09)

O Claude.ai deixou de ficar "cego" depois de disparar uma ordem: `cortex_ler`, `cortex_listar` e
`cortex_buscar` passam a ver a fila `orquestracao/`. Correção de infra, zona verde, sem tocar em
código de produção nem dinheiro.

## ✅ Causa raiz
As três ferramentas de leitura varriam **só** `walk(BRAIN)`, com `BRAIN=/brain/.claude/.ai/knowledge`.
Mas o `cortex_nova_ordem` escreve em `/brain/orquestracao/` — **fora** do BRAIN. Logo a escrita
funcionava, mas a leitura nunca olhava para essa pasta → "não encontrado" / 0 resultados.
(`findById`, `t_buscar`, `t_listar` usavam `walk(BRAIN)`.)

## ✅ Correção aplicada (`cortex-mcp/server.mjs`)
- **Escopo de leitura alargado:** `const READ_ROOTS = [BRAIN, FILA]` + `walkRoots()` que varre os
  dois. As 3 funções passaram de `walk(BRAIN)` → `walkRoots()`.
- **Paths limpos:** helper `relPath(p)` → páginas do cérebro mantêm o path curto de sempre
  (`permanente/x.md`), ordens aparecem como `orquestracao/<id>.md` (sem regressão no formato antigo).
- **Filtro por pasta:** `cortex_listar(filtro)` agora casa também com a **pasta de topo** (além de
  `tipo`/`zona`) — assim `filtro:"orquestracao"` devolve as ordens. É aditivo (só acrescenta matches).
- **Cirúrgico:** nada além disto mudou; `cortex_nova_ordem`/escrita/OAuth intactos. Backup no VPS
  antes (`server.mjs.bak_*`). Redeploy por `deploy.sh` (token/issuer/mount iguais; saúde 401/200 OK).

## ✅ Testes (curl com token, só LEITURA — não repeti o loop ponta-a-ponta)
Usando a ordem real de hoje `ordem-20260709060305-e4df` (terminada, aprovada):
1. `cortex_ler('ordem-20260709060305-e4df')` → **encontra**; conteúdo mostra `estado: aprovada`;
   path `orquestracao/ordem-20260709060305-e4df`. ✅
2. `cortex_listar(filtro:"orquestracao")` → **devolve a ordem**. ✅
3. `cortex_listar(filtro:"verde")` → **28** (era 27; +1 = a ordem). ✅
4. `cortex_listar()` sem filtro → **38** (cérebro inteiro intacto — sem regressão). ✅
5. `cortex_buscar("ordem-20260709060305")` → **encontra** (bónus: também estava cega). ✅

## ✅ Outras pastas fora do índice?
Varri todo o `/brain` à procura de `.md` com frontmatter `id:` **fora** de `.claude/.ai/knowledge`:
**só existe uma — a ordem em `orquestracao/`.** O resto de `/brain` é o **espelho do repo**
(android/, lib/, supabase/, docs/, …) sem páginas cortex (sem `id:`) — de propósito fora do índice
(indexá-lo seria varrer milhares de ficheiros do repo). Portanto `orquestracao/` era a **única**
pasta com este problema; está resolvida. Não alarguei ao espelho inteiro (seria errado e lento).

## ⚠️ Bugs / riscos
1. **Reset de OAuth no redeploy (recorrente):** recriar o container zera o OAuth em memória → o
   conector Córtex no chat web **pede reconexão 1x**. O token estático (Desktop/API) persiste. É o
   custo de qualquer restart do `cortex-mcp`; considerar persistir o estado OAuth no futuro se
   incomodar.
2. **`filtro` por pasta é aditivo:** `cortex_listar(filtro:"permanente")` agora também casa por
   pasta, não só por `tipo`. Só **acrescenta** resultados (nunca esconde) — melhoria, não regressão,
   mas fica registado.
3. **Fila cresce:** ordens antigas ficam em `orquestracao/` e passam a aparecer nas listagens. Quando
   houver muitas, convém um arquivo/limpeza de ordens `aprovada`/`travada` antigas (fora de scope).

Ficheiro: `.claude/.ai/cortex-mcp/server.mjs` (repo = VPS). Anterior: `costura_fechada.md`.
