---
id: memoria-claude-ai-digest-2026-10-16-chave-nova-edge
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-16
zona: verde
confianca: alta
estado: atual
---

# Chave nova 16/10 — Edge Functions a aceitar a sb_secret (Opus)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-16-chave-nova-edge`, origem `claude-code`, atualizada em 2026-10-16T11:21:16.218513+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 16 chave nova edge · memoria claude.ai · claude_ai_memoria

Missao chave-nova-16-10 (continuacao, 16/10). Objetivo: as Edge Functions chamadas pelo banco passarem a aceitar a chave secreta NOVA (sb_secret) ao lado da legada, para a troca no cofre (Bloco 3) nao partir nada. Nada foi desligado (Bloco 6): as chaves legadas continuam ligadas, tudo funciona hoje.
FEITO e PROVADO ao vivo (net.http_post do banco, 3 casos: legada em Bearer, nova em apikey/Bearer, sem credencial): 15 funcoes publicadas pelo MCP e a responder certo (legada 200/4xx, nova 200/4xx, sem nada 401/403): cortex-embedding, tvde-recibo-viagem, notify-partner-low-rating, notify-driver-assigned, payments-reconciler, notify-admin-urgent, settlement-receipt, analyze-conversations, auto-refund-order, notify-service-provider, notify-cleaner, monthly-partner-statement, weekly-closeout-digest, order-edit-settle (+ push-clientes-alvo ja de antes). order-edit-settle tinha um bug: importava chamadaDoServidor mas o whoCalls nunca a chamava — corrigido e publicado (commit local bf58dc11).
BLOQUEADO (a bora-tranca recusa o deploy MCP de Edge protegida, e a regra deny recusa o Edit): refund, finalize-order-from-intent, charge-extra. Os remendos (additivos, so aceitar tambem a chave nova) estao prontos em .claude/.ai/missoes/chave-nova-16-10/propostas/*.patch. So saem por sessao claude --safe-mode (tranca off) + CLI/MCP, por ordem do Danilo.
ADIADO para a CLI byte-exact (precisa do PAT da Supabase): robot-b (752 linhas; quebra so no Bloco 3) e 11 portoes exigirCallerOk ja no repo (notify-client, notify-tvde-chat/client/driver, notify-chat-message, notify-washer, ocr-receipt, notify-admin-message, notify-purchase-finalized, notify-admin-reimbursement, execute-broadcast) — hardening, nenhum quebra hoje.
PRECISA DO DANILO: (1) token de administracao da Supabase (caixinha pedir-token-supabase.ps1) para a CLI publicar refund/finalize/charge-extra/robot-b/portoes byte-exact e correr o Bloco 4 (VPS/CI/GitHub secret); (2) a sessao --safe-mode para a zona vermelha. So depois disso e de a maioria das apps estar na versao nova e que a Claude.ai desliga as chaves legadas (Bloco 3 aplicado primeiro). 2 commits locais por empurrar (d5d8f127, bf58dc11) — nao empurrei para nao disparar build da app sem mudanca Flutter.
