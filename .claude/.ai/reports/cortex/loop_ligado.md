# Loop de orquestração — LIGADO (2026-07-08)

**As 3 aprovações do Danilo executadas.** O loop autónomo (ordem → executor → juiz → aprovada/corrigir)
está **LIVE**, com dry-run passado 100% e todos os tetos verificados. Recon real primeiro, backups e
rollback prontos, e nada de zona vermelha. **A Trava do banco mantém prioridade absoluta.**

## Arquitetura real (o que existe, verificado)
- O `claude` no VPS é um **stub que redireciona para o PC** via `pc` → `ssh -ProxyCommand "tailscale nc"
  hermes@100.71.105.7` → `run-claude.cmd`. **As mãos executam no PC.** (Reusei este padrão, isolado.)
- `--max-budget-usd`, `--max-turns`, `--allowedTools`, `--model haiku` — **todos funcionam** (testados).

## ✅ Passo 1 — Campainha (implementada, testada, dispara sozinha)
- **Escolha de segurança:** NÃO reconstruí o `cortex-mcp` (é o servidor OAuth LIVE de que dependo).
  Em vez disso, um **watcher inotify** (`campainha.sh` via `systemd orq-campainha.service`,
  Restart=always) observa `/brain/orquestracao/` e acorda o carteiro. **Event-driven, não polling.**
- Fallback: cron `17 * * * *` (rede de segurança).
- **Testado:** larguei `selftest-002` e a campainha disparou o carteiro **sozinha** (log:
  `22:24:37 evento em selftest-002.md -> carteiro`), sem correr nada à mão.

## ✅ Passo 2 — Claude-juiz (agendado via campainha, testado)
- Implementado como bridge **`pc-judge` → `run-claude-judge.cmd`**: `--model haiku --max-turns 3
  --max-budget-usd 1`, **read-only** (`--disallowedTools "Bash Edit Write ..."`). Guard: só devolve
  `VEREDITO: APROVADA` ou `VEREDITO: CORRIGIR: <...>`. É acionado pelo carteiro logo após `respondida`
  (a "mesma campainha" da opção do prompt) — juízo independente, isolado do executor.
- **Isola-se de zona vermelha:** só lê; nunca edita/executa Stripe/pricing/etc.
- **Testado:** devolveu `VEREDITO: APROVADA` via a ponte real.

## ✅ Passo 3 — Dry-run (passou 100%, 1 tentativa)
- **Manual** (`selftest-001`): aberta→executando→respondida→**aprovada**; executor criou o ficheiro no
  PC (UTC), sem commit; juiz aprovou.
- **Auto** (`selftest-002`): **campainha disparou sozinha** → mesmo desfecho. Ponta-a-ponta.
- **Telegram:** `hermes send -t telegram` entregue ao Danilo (chat 6731890157).
- **Brakes verificados:** **T5** (enabled=false → ordem fica `aberta`, log "kill switch OFF", NÃO executa);
  **T3** (tarefa toca `pricing_service` → `zona_vermelha`, tentativa=0, NÃO executa).
- Ordens de teste apagadas; fila limpa (só `_controlo.md`).

## 🚦 Estado final: `orquestracao_enabled: TRUE` — LIGADO
Fila sem ordens pendentes. A próxima ordem em `orquestracao/<id>.md` corre sozinha:
executor (budget $5/20 turns) → juiz (haiku) → aprovada | corrigir (reabre, máx 5) | travada (Telegram).

## 🔴 Confirmações de segurança
- **Zona vermelha FORA do loop:** T3 no carteiro (grep dispatch/pricing/finalizePurchase/bora_tokens/
  stripe/wallet/ledger/refund/payout/commission/platform_settings/force-push) → `zona_vermelha`, não
  executa. **Verificado.**
- **Trava intacta e com prioridade:** os hooks `protege-dinheiro.sh`/`protege-banco.sh` disparam
  **mesmo com `--dangerously-skip-permissions`** — testei: edit a `pricing_service.dart` → **exit 2
  (bloqueado)**; edit UI normal → exit 0. Não toquei `settings.json`.
- **T1=5** (carteiro). **T2** budget+turns nos `.cmd`. **T4** juiz read-only; executor sem commit/push.
- **T5** kill switch em `_controlo.md` (ou `systemctl stop orq-campainha`).

## ⚠️ Bugs / riscos (reportados, mesmo fora do scope)
1. **Trava hygiene (bug):** as regras `MultiEdit(...)` no `settings.json` dão "matches no known tool"
   — são **no-ops** (o Claude Code já não tem tool `MultiEdit`). Edit/Write denies + hooks ainda
   protegem, mas as linhas `MultiEdit` estão mortas. Sugiro trocar por `Edit`/`Write` (zona 🟡 —
   mexe na Trava, PROPOSE-ONLY).
2. **Fragilidade PC-aceso:** o executor corre no PC. Se o PC dormir, `pc-loop` faz timeout → a ordem
   fica `executando` até nova tentativa/T1. Não há dano; só atraso.
3. **Chatter do inotify:** as escritas do próprio carteiro na ordem re-disparam a campainha → corridas
   no-op (o `flock` + o check `aberta` contêm; a ordem final fica estável). Otimização futura: reagir
   só a `create`/`moved_to` + re-enfileirar reaberturas explicitamente.
4. **Ponto de integração a validar com ordem REAL do claude.ai:** o dry-run largou ficheiros de ordem
   direto na fila. Em produção, o claude.ai escreve a ordem via `cortex_escrever` — falta confirmar
   que isso cria o ficheiro em `orquestracao/` (o `cortex_escrever` "atualiza EXISTENTE"; criar ordem
   nova pode precisar de suporte no cortex-mcp). **A mecânica do loop está provada; esta é a última
   costura claude.ai→fila.**
5. **`--dangerously-skip-permissions`:** o executor corre com permissões totais (necessário p/ headless).
   Zona vermelha é bloqueada por hooks (hard) + guard (soft); não-vermelho reversível é o trabalho do
   loop, com o juiz a filtrar qualidade e sem auto-commit. Risco residual aceite pelo desenho do Danilo.

Artefactos versionados: `.claude/.ai/hermes/orquestrador-carteiro/deploy/` (+ `DEPLOY.md`).
