---
id: memoria-claude-ai-digest-2026-10-16-chave-nova-fecho-mcp
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-17
zona: verde
confianca: alta
estado: atual
---

# Chave nova 16/10 — fecho pelo MCP (portões, robot-b) e o que falta

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-16-chave-nova-fecho-mcp`, origem `claude-ai`, atualizada em 2026-10-17T04:23:12.33621+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 16 chave nova fecho mcp · memoria claude.ai · claude_ai_memoria

Ordem do Danilo 16/10: publicar o resto pelo MCP sem esperar pelo token. Fluxo e2e_log chave-nova-16-10.

FEITO E PROVADO (3 casos por função: chave legada, chave nova, sem credencial):
- 15 Edge Functions em modo duplo (aceitam legada e nova): cortex-embedding, tvde-recibo-viagem, notify-partner-low-rating, notify-driver-assigned, payments-reconciler, notify-admin-urgent, settlement-receipt, analyze-conversations, auto-refund-order, notify-service-provider, notify-cleaner, monthly-partner-statement, weekly-closeout-digest, order-edit-settle (bug whoCalls corrigido, commit bf58dc11), push-clientes-alvo.
- 11 portões exigirCallerOk publicados; 3 que estavam abertos a qualquer um (execute-broadcast, notify-admin-reimbursement, notify-purchase-finalized) agora só aceitam o servidor ou utilizador válido.
- robot-b v16: aceita a chave nova (era a última que partia na troca).
- Web já com a chave publishable; cofre sb_secret_backend criado.

FALTA (nada desligado, a chave legada continua a funcionar):
1. 3 de dinheiro (refund, finalize-order-from-intent, charge-extra): a bora-tranca recusa Edit e deploy, até por MCP. Remendos prontos; só saem em sessão --safe-mode por ordem do Danilo.
2. Bloco 3 (migração 20261016100000, banco passa a mandar a chave nova): NÃO aplicar antes do ponto 1 — parte os reembolsos de cancelamento. Vai junto.
3. Bloco 4 VPS (/opt/whatsapp-bora, /opt/assistente-negocio) e segredo do CI: precisa da chave do cofre sem passar pela conversa → token de admin (PAT) da Supabase + distribuir-chave.ps1.
4. notify-tvde-driver (848 linhas): adiada para a CLI; não parte no desligar (verify_jwt=true já aceita a nova).
5. Desligar as chaves legadas: só no fim, depois de 1-4, com data.

Risco aberto: a chave legada esteve pública no GitHub e já foi testada por IP de fora (16/10); a vigia horária continua.
