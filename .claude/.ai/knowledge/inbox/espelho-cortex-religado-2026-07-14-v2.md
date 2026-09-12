---
id: espelho-cortex-religado-2026-07-14-v2
tipo: reconfirmacao (2a vez, sem regressao)
zona: verde (conteudo do Cortex copiado add-only via tar/ssh; zero git push, zero commit, zero build)
criada: 2026-07-14
autor: claude code (executor loop)
---

# Espelho do Cortex "parado" — reconfirmação (2ª vez, sem regressão)

## Resumo (uma linha)
ESPELHO CORTEX religado + relatórios de hoje visíveis: **sim** — mesmo pedido literal já
resolvido às 17:02 de hoje ([[espelho-cortex-religado-2026-07-14]]); reconfirmado agora com
zero regressão, mais 1 ficheiro novo sincronizado.

## O que mudou desde a última vez
Nada de estrutural. Diferenças encontradas nesta ronda:
- `docker inspect cortex-mcp` continua com `StartedAt=2026-07-09T06:15:45Z` (container não
  reiniciou) e `RestartPolicy=unless-stopped` — resiliência a restart já correta, sem alterar.
- Local tinha **1 ficheiro novo** desde a última sincronização (17:02):
  `aviso-espera-telegram-2026-07-14-v2.md`. Repeti o mesmo content-sync add-only:
  ```
  tar czf - .claude/.ai/knowledge | ssh -i id_ed25519_vps root@srv1786862.hstgr.cloud \
    'cd cortex-brain && tar xzf - --skip-old-files'
  chown -R 10000:10000 .../cortex-brain/.claude/.ai/knowledge
  ```
  Espelho VPS passou de 217 → 218 ficheiros `.md`.
- `git`: `origin/autonomous-night-2026-04-29` continua parado em `00c8623`; HEAD local segue
  ~40 commits à frente + dezenas de ficheiros nunca commitados. Causa raiz inalterada:
  `git push` headless continua bloqueado ([[project_headless_push_credential]]), não é bug
  de hoje. Não tentei destravar o push — recusado 9x+ antes pela mesma razão (dispara build
  de produção sem filtro de path).

## Verificação (chamadas reais ao MCP)
- `cortex_buscar("cloudflare")` → 10 resultados, incluindo `teste-vps-cloudflare-2026-07-14`.
- `cortex_ler("espelho-cortex-religado-2026-07-14")` → devolve o relatório completo de hoje
  16:02/17:02 (prova que já estava sincronizado antes desta ronda).
- `cortex_listar(filtro="inbox")` → 48 páginas com `id`, incluindo o próprio relatório.
- `cortex_buscar("aviso-espera-telegram-2026-07-14-v2")` → 1 resultado (ficheiro novo desta
  ronda), confirmando a sincronização recém-aplicada.
- `inbox/credencial-git-restaurada-2026-07-14.md` (citado no pedido) **continua a não
  existir** em lado nenhum (PC nem VPS) — não é falha de sync, esse relatório nunca foi
  escrito.

## Gotcha para quem investigar isto de novo
`cortex_buscar` faz **substring literal** (com espaços) sobre `nome+conteúdo`, não busca
tokenizada — uma query como `"espelho cortex religado 2026-07-14"` (espaços) NÃO bate com
nomes de ficheiro em hífen (`espelho-cortex-religado-2026-07-14.md`) a menos que essa frase
exata apareça no corpo do texto. Isto pareceu "0 resultados = espelho morto" numa primeira
tentativa desta ronda até re-testar com palavra única (`"cloudflare"`) — **não é bug do
servidor**, é como usar a ferramenta. Ver `server.mjs` função `t_buscar` (linha ~49).

## Auto-restart / resiliência futura
Sem mudanças — já correto (`--restart unless-stopped` no container + crontab do host
sobrevive a qualquer restart do cortex-mcp ou do Hermes, são processos independentes).

## Fica para o Danilo
Mesma pendência de sempre: o fix durável (origin realmente atualizado, sem eu repetir o
scp a cada ronda) só acontece quando os commits retidos no PC chegarem ao GitHub via "vai"
do Danilo — continua bloqueado por decisão consciente (build de produção automático nesta
branch). Não é uma ação recomendada agora, só o registo do estado.
