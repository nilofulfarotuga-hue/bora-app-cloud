---
id: relatorio-sync-por-tarefa-2026-07-10
tipo: relatorio
origem: [Tarefa 2 missão 3-em-1 2026-07-10 — cegueira do espelho]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado
---

# ✅ Relatório — Sync do espelho POR-TAREFA (Tarefa 2)

## Implementado (bate com o ADR `2026-07-08-cortex-fonte-de-verdade-e-ponte-mcp`)
1. **`/usr/local/bin/espelho-pull.sh`** (VPS host): `git pull --ff-only` no espelho como
   `-u hermes` + deploy key (nunca PAT). **Árvore suja → skip com log** (nunca destrói
   estado do carteiro a meio de uma ordem); o fallback noturno reconcilia.
2. **`carteiro.sh`**: pull no INÍCIO de cada passagem (a ordem corre contra espelho fresco)
   e no FIM (apanha o push do executor).
3. **`pre-push` hook no PC** (`.git/hooks/pre-push`; cópia versionada em
   `.claude/scripts/hooks/pre-push`): qualquer push na branch dispara o pull na VPS ~15s
   depois, fire-and-forget (nunca bloqueia o push; sem rede = silêncio + fallback).
4. **`bora-bridge-up.sh`**: aviso idempotente se o espelho-pull.sh desaparecer.
5. **Cron 06h30 mantido** (sync-brain com `fetch --depth 1 + reset --hard`) como rede de
   segurança — é ele que limpa árvore suja acumulada.
6. `loops.md`: linha cortex-mcp-sync já em **v2** (por-tarefa + hook + fallback).

## Teste real (ciclo completo, medido)
Push `77f6548` (PC) → hook disparou → **espelho na VPS já estava em `77f6548` ao verificar
(~2 min depois; o pull manual seguinte deu rc=0 "Already up to date")**. Cegueira resolvida:
claude.ai/Hermes veem conteúdo novo em segundos, não no dia seguinte.

## Decisão de segurança importante (raiz de um bug latente)
O reset noturno do espelho DESCARTA edições locais não commitadas — o estado `aprovada` da
ordem ef7d vivia só no espelho e seria ressuscitado como `aberta` (re-execução!). Fix: o
estado final da ordem foi gravado no REPO (`orquestracao/ordem-...ef7d.md`, commit
`ab870b1`) — regra daqui em diante: **estado terminal de ordem grava-se no repo, não só no
espelho**.

## Pendência/nota
- O "hook pós-push" é aproximado por `pre-push` + delay (git não tem post-push nativo);
  webhook GitHub → VPS fica como melhoria futura (proposta, não construída).
- Divergência real do espelho (local commits vs remote) → o ff-only salta e o noturno
  resolve; se um dia o carteiro precisar de freshness com árvore suja, avaliar stash-pop.
