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
  **Guarda (2026-07-14):** este ficheiro tem 7 chamadas `notify "..."` (conclusão/passo travado/
  tarefa travada/zona vermelha/rate-limit/conclusão/terminal-limpo). Qualquer edição feita
  diretamente na VPS tem de ser copiada de volta para este ficheiro (fonte git) — nunca o
  contrário — e `grep -c 'notify "' carteiro.sh` deve continuar ≥7 antes de dar a alteração
  por fechada. Verificação rápida: `sha256sum` local vs `/root/orquestracao/carteiro.sh` têm de
  bater certo.
- `campainha.sh` — watcher **inotify** (event-driven, NÃO polling) da fila → corre o carteiro.
- `/etc/systemd/system/orq-campainha.service` — corre a campainha (Restart=always, enabled).
- cron `17 * * * *` — fallback lento (rede de segurança).

## Fila + kill switch (`/opt/data/cortex-brain/orquestracao/`, = `/brain/orquestracao/`)
- `_controlo.md` → `orquestracao_enabled: true|false` (**KILL SWITCH**).
- `<id>.md` — ordens (estado: aberta→executando→respondida→aprovada|corrigir|zona_vermelha|travada).

## Operar
- **PARAR TUDO:** pôr `orquestracao_enabled: false` em `_controlo.md` (ou
  `systemctl stop orq-campainha`).
- **Ver:** `tail /root/orquestracao/carteiro.log` · `journalctl -u orq-campainha`.
- **Reverter:** `systemctl disable --now orq-campainha`; `rm -rf /root/orquestracao`;
  remover `pc-loop/pc-judge` e os 2 `.cmd`; remover a linha `orq-fallback` do cron.
