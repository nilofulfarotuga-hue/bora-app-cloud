#!/bin/bash
# .vps-exec-runner.sh — corre como hermes-exec (nao-root; --dangerously-skip-permissions recusa
# root/sudo por seguranca). Chamado por /root/claude-vps-exec.sh via runuser. $1=ficheiro da
# tarefa, $2=modelo (sonnet|opus). Paridade com run-claude-loop.cmd (PC): mesmo GUARD + tetos.
export HOME=/home/hermes-exec
source /home/hermes-exec/.claude-vps-token
cd /docker/hermes-agent-fvnc/data/bora-app-cloud || exit 3

GUARD="Estas a correr como EXECUTOR de um loop autonomo do Bora (headless, sem canal com o Danilo). Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA facas git commit nem git push (a menos que a tarefa peca explicitamente). Se a tarefa comecar com [PROPOSE-ONLY], prepara tudo mas NAO apliques nem facas commit - devolve a proposta e para. PARA e responde SO com uma linha 'CONFIRMACAO NECESSARIA: <o que>' se a tarefa tocar Lista Vermelha (Stripe/pagamentos/payouts/pricing/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger/migrations destrutivas/force-push/disparos em massa/builds de producao). Nunca imprimas segredos. No fim devolve RESULTADO conciso PT-BR: o que fizeste + ficheiros tocados."

exec claude -p --append-system-prompt "$GUARD" --model "$2" --dangerously-skip-permissions --max-turns 40 --max-budget-usd 10 < "$1"
