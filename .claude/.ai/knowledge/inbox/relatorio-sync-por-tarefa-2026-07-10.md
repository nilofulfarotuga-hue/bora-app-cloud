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

## ⚠️ Deploy à VPS — o elo que faltava (2026-07-10, 2.ª passagem do executor)
O commit `af00db8` **versionou** os scripts no repo mas **não os pôs a correr no host** da VPS.
Auditoria em `2026-07-10` (2.ª ordem) confirmou os três masters do host **desatualizados**:
- `/root/cortex-mcp/sync-brain.sh` — 16 linhas, **sem** modo `fast` (só o `reset --hard` antigo).
- `/root/orquestracao/carteiro.sh` — 75 linhas, **sem** `sync_espelho()`.
- `/root/bora-bridge-up.sh` — 67 linhas, **sem** o bloco `cortex-sync` idempotente.

Ou seja: a "cegueira" **não estava resolvida em produção** — o espelho ficava fresco só pelo cron
06h30 (`reset --hard`), o próprio comportamento que o modo `fast` veio evitar. Corrigido agora:
os três masters foram **deployados** do repo para o host (backups `*.bak_20260710_deploy` guardados;
`mv` atómico preserva o inode de um `carteiro.sh` a correr). Verificação pós-deploy:
`sync-brain fast=3 · carteiro sync_espelho=2 · bridge cortex-sync=1` ✅.

## Teste real (ciclo medido, 2026-07-10)
Com os três masters já live, empurrei um commit real (este relatório) e medi o ciclo:
1. **Push:** o `git push` https do PC do executor **falha headless** (`wincredman` pede sessão
   interactiva — ver `project_headless_push_credential`). Contornado pelo **deploy key SSH RW**:
   o commit exacto (`8676ca9`, via `git bundle` → push de dentro do container) chegou ao origin
   **sem SHA divergente**. `origin HEAD = 8676ca9` confirmado.
2. **Sync por-tarefa:** invoquei o `sync-brain.sh fast` como o carteiro faz. O espelho é um clone
   **`--depth 1` (shallow)**, por isso o `merge --ff-only` dá `fatal: refusing to merge unrelated
   histories` — o **fallback do script** entra e refresca `.claude/.ai/knowledge/` (o conteúdo que
   o MCP/Claude.ai realmente lê). Medido: **~1 s**, a frase nova do relatório já visível no espelho.
   A fila `orquestracao/` ficou **intacta (41→41)**.

**Resultado.** Cegueira resolvida **em produção ao nível do CONTEÚDO**: o Claude.ai/Hermes veem o
knowledge/ novo em segundos, não no dia seguinte. O **HEAD** do espelho não avança no `fast` (artefacto
do shallow) — reconciliado pelo **cron 06h30** (`reset --hard`). Como todo o Córtex vive sob
`.claude/.ai/knowledge/`, o fallback cobre 100% do que o MCP lê.

## Decisão de segurança (raiz de um bug latente)
O `reset --hard` noturno DESCARTA edições locais não commitadas — o estado terminal de uma ordem
(ex.: `aprovada`) vivia só no espelho e seria ressuscitado como `aberta` (re-execução!). Regra
daqui em diante: **estado terminal de ordem grava-se no REPO, não só no espelho.** É por isso que
o modo `fast` usa `merge --ff-only` (preserva) e não `reset --hard`.

## ✅ Verificação live em produção (3.ª passagem do executor, 2026-07-10)
Re-auditoria por SSH ao host confirmou os três masters **live** (não regrediram):
- `/root/cortex-mcp/sync-brain.sh` = **41 linhas, 3× `fast`** ✅
- `/root/orquestracao/carteiro.sh` = **76 linhas, 2× `sync_espelho`** ✅
- `/root/bora-bridge-up.sh` = **77 linhas, 1× bloco `cortex-sync`** ✅
- espelho remote = `git@github.com:...bora-app-cloud.git` (SSH deploy key, **nunca PAT**) ✅

**Teste medido (por-tarefa, modo `fast`).** Disparei `sync-brain.sh fast` como o carteiro faz:
- **Duração: ~1,46 s** (fetch + reconciliação do `knowledge/`) — "segundos", não o dia seguinte.
- **Fila `orquestracao/` preservada: 22 → 22** ficheiros (o `fast` NÃO rebobina a fila viva). Nota:
  a fila vive na **raiz** do espelho (`/opt/data/cortex-brain/orquestracao/`), não sob `knowledge/`.
- O `fetch` trouxe `origin/autonomous-night-2026-04-29` já à frente do espelho — o conteúdo novo
  passou a estar visível ao MCP/Claude.ai no próprio ciclo.
- **HEAD do espelho não avança no `fast`** (artefacto do clone `--depth 1`): fica no SHA antigo e é
  reconciliado pelo **cron 06h30** (`reset --hard`). Como o Claude.ai lê **CONTEÚDO** sob
  `knowledge/` (e não o SHA), a cegueira está resolvida ao nível que importa.

**Porque NÃO se força o HEAD por-tarefa (decisão reafirmada).** O working tree do espelho está
cronicamente "sujo" (a fila `orquestracao/` da raiz + reports editados localmente). Um `reset --hard`
ou um `--unshallow`+`ff-only` agressivo por-tarefa arriscaria a **fila viva do carteiro** (loop 🟢
Core). O design escolhe deliberadamente `merge --ff-only` + fallback (checkout de `knowledge/`) para
**preservar** essa fila; o avanço limpo do HEAD fica com o cron noturno. `--unshallow` continua como
melhoria futura **opcional**, não aplicada (mantém o mecanismo simples e a fila segura).

## Pendência/nota
- O "hook pós-push" é aproximado por `pre-push` + delay (git não tem `post-push` nativo);
  webhook GitHub → VPS fica como melhoria futura (proposta, não construída).
- Divergência real (commits locais no espelho vs remote) → o `ff-only` salta e o cron resolve;
  se um dia o carteiro precisar de freshness com árvore suja, avaliar `stash`/`pop`.
- **Espelho é shallow (`--depth 1`)** → o `merge --ff-only` do `fast` dá SEMPRE "unrelated
  histories" e cai no fallback (checkout de `knowledge/`). Funciona para o conteúdo (é o que o MCP
  lê), mas o HEAD do espelho só avança no cron. Melhoria futura (opcional): clonar full ou
  `git fetch --unshallow` uma vez para o `ff-only` avançar o HEAD limpo. Não feito (mantém simples;
  o conteúdo — o requisito — já reflecte em segundos).
- **Push headless:** o executor no PC não faz `git push` https (wincredman precisa sessão). O push
  por-tarefa real vai pelo **deploy key SSH** de dentro do container (bundle preserva o SHA). Ver
  `project_headless_push_credential`.
