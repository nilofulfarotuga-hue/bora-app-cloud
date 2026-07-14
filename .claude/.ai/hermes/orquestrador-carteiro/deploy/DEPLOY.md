# Loop de orquestração — manifesto de deploy (LIGADO 2026-07-08)

Cópias versionadas dos artefactos que correm em produção. Onde cada um vive:

## PC (`hermes@100.71.105.7`, este PC) — onde o Claude Code REAL executa
- `C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\run-claude-loop.cmd` — **executor**:
  `claude -p --dangerously-skip-permissions --model opus --max-turns 20 --max-budget-usd 5`
  no projeto `bora_app`. Guard: sem commit/push; para em zona vermelha.
- `...\run-claude-judge.cmd` — **Claude-juiz**: `claude -p --model haiku --max-turns 3
  --max-budget-usd 1 --disallowedTools "Bash Edit Write ..."`. Só lê + devolve `VEREDITO: ...`.
- (Ambos `.cmd` = **CRLF** obrigatório.)

## Container Hermes (`/opt/data/.local/bin/`, persistente, no PATH)
- `pc-loop` / `pc-judge` — bridges (b64 + `ssh -o ProxyCommand="tailscale nc" hermes@PC`) que
  apontam aos `.cmd` acima. Isolados do `pc`/`run-claude.cmd` partilhados (zero risco a esses).

## VPS host (`/root/orquestracao/`)
- `carteiro.sh` — dispatcher determinístico. T5 kill switch → T3 zona-vermelha → T1 (5) →
  `pc-loop` (executor) → escreve `saida` → `pc-judge` → veredito → aprovada/corrigir/travada →
  `hermes send -t telegram`. `flock` serializa.
- **`claude-vps-exec.sh` (2026-07-14) — executor local na VPS** (`vps_exec()` em carteiro.sh,
  tentado ANTES do `pc-loop`; só cai para o PC em falha real do wrapper). Fonte: `deploy/claude-
  vps-exec.sh` + `deploy/vps-exec-runner.sh` (deploy: copiar para `/root/claude-vps-exec.sh` e
  `/home/hermes-exec/.vps-exec-runner.sh`).
  **Gotcha crítico (ordem 08db, 2026-07-14):** `--dangerously-skip-permissions` do Claude Code
  **recusa correr como root/sudo** por segurança — a 1ª versão do wrapper corria `claude -p`
  direto como root (sem essa flag, sem `cd` ao repo, sem GUARD) e por isso ficava preso até ao
  timeout (SAIDA-VAZIA) ou só "diagnosticava sem executar" (sem permissão real p/ ferramentas).
  Fix: utilizador dedicado não-root `hermes-exec` (uid/gid 10000 — o MESMO dono do clone
  `/docker/hermes-agent-fvnc/data/bora-app-cloud`, criado com `useradd -u 10000 -g 10000`).
  `claude-vps-exec.sh` (root) grava a tarefa num ficheiro temp, `chown` p/ hermes-exec, e chama
  `/usr/sbin/runuser -u hermes-exec -- bash .vps-exec-runner.sh` (caminho ABSOLUTO — `runuser`
  não está em `/usr/bin`, um PATH mínimo tipo cron/systemd dá `rc=127`). O runner (hermes-exec)
  tem o MESMO GUARD + tetos do `run-claude-loop.cmd` do PC (`--dangerously-skip-permissions
  --max-turns 40 --max-budget-usd 10`, modelo sonnet/opus por `[MODELO: OPUS]`).
  **Git push como hermes-exec:** `/root/.ssh/id_ed25519` NÃO autentica no GitHub (é doutra
  finalidade) — a chave de deploy válida do repo é
  `/docker/hermes-agent-fvnc/data/.secrets/cortex_deploy_ed25519` (já pertence a uid 10000, logo
  hermes-exec lê-a directamente); configurado via `git config core.sshCommand` no clone.
  Testado ponta-a-ponta 2x isolado (resposta simples + tool call real) antes de ir p/ produção.
  **Guarda (2026-07-14):** este ficheiro tem 7 chamadas `notify "..."` (conclusão/passo travado/
  tarefa travada/zona vermelha/rate-limit/conclusão/terminal-limpo). Qualquer edição feita
  diretamente na VPS tem de ser copiada de volta para este ficheiro (fonte git) — nunca o
  contrário — e `grep -c 'notify "' carteiro.sh` deve continuar ≥7 antes de dar a alteração
  por fechada. Verificação rápida: `sha256sum` local vs `/root/orquestracao/carteiro.sh` têm de
  bater certo.
  **2026-07-14 (aviso-espera-telegram):** o aviso de zona vermelha agora leva `resumo_tarefa()`
  (resumo curto da ordem, sem prefixos `[MODELO:.../[PROPOSE-ONLY:...]`) + o comando exato de
  desbloqueio (`vai <id>`). Testes do `resumo_tarefa()`: `--selftest`. Teste end-to-end sintético
  (ordem entra em zona_vermelha → aviso → `vai <id>` desbloqueia): `_teste_aviso_espera.sh`
  (não é deployado — só corre local/CI, fonte única = funções reais de `carteiro.sh`).
- `campainha.sh` — watcher **inotify** (event-driven, NÃO polling) da fila → corre o carteiro.
- `/etc/systemd/system/orq-campainha.service` — corre a campainha (Restart=always, enabled).
- cron `17 * * * *` — fallback lento (rede de segurança).

## Container Hermes — skill `desbloqueio-zona-vermelha` (2026-07-14)
- Fonte canónica: `bora_app/.claude/.ai/hermes/orquestrador-carteiro/skill-desbloqueio-vai/SKILL.md`.
- Deploy: copiar a pasta para `/opt/data/skills/hermes-agent/desbloqueio-zona-vermelha/` (mesmo
  padrão de `hermes-operacao-confiavel`/`hermes-auto-configuracao` — descoberta automática por
  pasta, sem passo extra de registo).
- Ensina o Hermes a reagir a **"vai `<id>`"** no Telegram: se a ordem estiver `estado:
  zona_vermelha`, edita para `estado: aberta` (limpa `nota:`) — a campainha inotify acorda o
  carteiro sozinha a partir daí. Não decide nada sozinho; só executa a confirmação explícita que
  o Danilo já deu ao escrever "vai". Não toca em ordens que não estejam em zona vermelha.
  **NÃO substitui a Trava nem a T3 do carteiro** — só encurta o "como confirmar", a decisão de
  entrar em zona vermelha continua 100% do classificador determinístico `zona_vermelha()`.

## Fila + kill switch (`/opt/data/cortex-brain/orquestracao/`, = `/brain/orquestracao/`)
- `_controlo.md` → `orquestracao_enabled: true|false` (**KILL SWITCH**).
- `<id>.md` — ordens (estado: aberta→executando→respondida→aprovada|corrigir|zona_vermelha|travada).

## Operar
- **PARAR TUDO:** pôr `orquestracao_enabled: false` em `_controlo.md` (ou
  `systemctl stop orq-campainha`).
- **Ver:** `tail /root/orquestracao/carteiro.log` · `journalctl -u orq-campainha`.
- **Ver AO VIVO no PC (2026-07-14):** duplo-clique em `assistir-vps.cmd` (raiz do repo,
  ao lado do `assistir.cmd` local) — SSH direto `root@srv1786862.hstgr.cloud` com
  `C:\Users\danil\.ssh\id_ed25519_vps`, `tail -f` ao `carteiro.log`; religa sozinho se a
  ligação cair (`ServerAliveInterval`/loop de retry). Complementa o `assistir.cmd`: esse
  mostra o Claude a trabalhar passo a passo NESTA máquina (bora-live.log), o
  `assistir-vps.cmd` mostra o dispatcher (carteiro.sh) NA VPS — ordens a entrar/sair da
  fila, tentativa, veredito do Juiz, rc, notificações. Ver relatório
  `.claude/.ai/knowledge/inbox/janela-visibilidade-vps-2026-07-14.md`.
- **Reverter:** `systemctl disable --now orq-campainha`; `rm -rf /root/orquestracao`;
  remover `pc-loop/pc-judge` e os 2 `.cmd`; remover a linha `orq-fallback` do cron.
