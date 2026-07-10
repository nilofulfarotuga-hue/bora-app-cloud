---
id: relatorio-sync-por-tarefa-2026-07-10
tipo: relatorio
origem: [Tarefa "cegueira do espelho do Córtex" 2026-07-10]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado
---

# ✅ Relatório — Sync do espelho POR-TAREFA (fim da cegueira diária)

**Problema.** O espelho `/opt/data/cortex-brain` (o que o Claude.ai/MCP lê) só sincronizava
no cron das 06h30 → o Claude.ai ficava **cego ao conteúdo novo até ao dia seguinte**.

**Solução.** Refrescar o espelho a **cada ordem** do loop, não só de madrugada. Consolidado
num único script com 2 modos, `sync-brain.sh` (evita duplicar lógica de auth/clone).

## Implementado (bate com o ADR `2026-07-08-cortex-fonte-de-verdade-e-ponte-mcp`)

1. **`sync-brain.sh` ganhou 2 modos** (`.claude/.ai/cortex-mcp/sync-brain.sh`; master no host
   `/root/cortex-mcp/sync-brain.sh`):
   - `hard` (default) — cron 06h30: `fetch + reset --hard`. Autoritário / rede de segurança.
   - `fast` — por-tarefa: `fetch + merge --ff-only`. **Preserva a fila `orquestracao/`** que o
     carteiro edita localmente (o `reset --hard` rebobinava-a → re-execução de ordens). Se o
     ff não der (árvore suja no caminho) refresca só `.claude/.ai/knowledge/` (o Claude.ai lê
     CONTEÚDO, não o SHA) e deixa o cron reconciliar.
   - Auth **sempre** deploy key SSH (`/opt/data/.secrets/cortex_deploy_ed25519`), **nunca PAT**.

2. **`carteiro.sh`** chama `sync_espelho()` (modo `fast`, como `-u hermes -e HOME=/opt/data`)
   **no fim de cada ordem** — depois de o executor fazer push, o espelho fica fresco em segundos
   (linhas 20-22 e 73-74; best-effort, nunca aborta o ciclo).

3. **`pre-push` hook no PC do executor** (`.git/hooks/pre-push`; cópia versionada em
   `.claude/.ai/hermes/orquestrador-carteiro/deploy/hooks/pre-push`): **qualquer** push à branch
   `autonomous-night-2026-04-29` (loop do carteiro OU push manual do Danilo) agenda o sync `fast`
   na VPS ~6s depois, fire-and-forget. Aproxima o "post-push" que o git não tem nativamente.
   Nunca bloqueia/atrasa o push; sem rede → silêncio + o cron reconcilia.

4. **`bora-bridge-up.sh`** re-garante (idempotente, padrão do fix tailscale) após um `recreate`
   do container: git presente, espelho clonado, e o **remote forçado a SSH deploy key** (nunca
   PAT em URL) + `safe.directory` — para o pull por-tarefa continuar a autenticar (linhas 67-77).

5. **Cron 06h30 mantido** (`sync-brain.sh` sem arg = `hard` = `reset --hard`) como rede de
   segurança — reconcilia se algum `fast` saltar por árvore suja.

6. **`loops.md`** (`permanente/semantica/loops.md`): linha `cortex-mcp-sync (espelho)` já em
   **v2** — frequência "por-tarefa (carteiro após push, modo fast) + pre-push hook + cron 06h30
   fallback".

## Teste real (ciclo medido)
Push do PC → o `pre-push` disparou → o espelho na VPS refletiu o novo HEAD em segundos (pull
manual seguinte deu "Already up to date"). Cegueira resolvida: o Claude.ai/Hermes veem conteúdo
novo em segundos, não no dia seguinte.

## Decisão de segurança (raiz de um bug latente)
O `reset --hard` noturno DESCARTA edições locais não commitadas — o estado terminal de uma ordem
(ex.: `aprovada`) vivia só no espelho e seria ressuscitado como `aberta` (re-execução!). Regra
daqui em diante: **estado terminal de ordem grava-se no REPO, não só no espelho.** É por isso que
o modo `fast` usa `merge --ff-only` (preserva) e não `reset --hard`.

## Pendência/nota
- O "hook pós-push" é aproximado por `pre-push` + delay (git não tem `post-push` nativo);
  webhook GitHub → VPS fica como melhoria futura (proposta, não construída).
- Divergência real (commits locais no espelho vs remote) → o `ff-only` salta e o cron resolve;
  se um dia o carteiro precisar de freshness com árvore suja, avaliar `stash`/`pop`.
