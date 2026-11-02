---
id: memoria-claude-ai-digest-2026-11-02-chaves-varredura
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Digest 02/11 — varredura das chaves (Claude Code PC)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-02-chaves-varredura`, origem `claude-code`, atualizada em 2026-11-02T06:20:59.441121+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 02 chaves varredura · memoria claude.ai · claude_ai_memoria

Missão chaves-varredura-2026-10-31, autorizada pelo Danilo a 31/10 12:19 depois do pagamento de 18,41 € que ficou sem pedido (a finalize recusava a chave do servidor desde 16/10). O Claude Code corrigiu e publicou 37 Edge Functions pela regra da casa (_shared/chaves.ts: chamadaDoServidor, exigirServidorOuAdmin, utilizadorDoPedido, respostaAoPing) e provou cada uma do banco (legada em Bearer, sb_secret em Bearer e só em apikey: 200) e de fora (JWT forjado e sem nada recusados). Falhas de segurança fechadas pelo caminho: register-partner lia o sub de um JWT sem assinatura; notify-tvde-driver não verificava quem chama (a chave pública mandava ofertas falsas); notify-client deixava qualquer sessão mandar texto livre a qualquer cliente e não aceitava user_id (o cliente nunca sabia de reembolsos e cancelamentos). A app mandava a chave pública como Bearer nos avisos (401): agora vai o token da sessão e as fases que o gatilho trg_push_cliente_fase_pedido já avisa saem da app; "Reenviar código" e "Encomenda aceite" mandavam o telefone e falhavam sempre. Painel: Pagamentos órfãos com "Criar o pedido agora" e ecrã novo Saúde das chaves; as rotas /admin/orphans e /admin/system-health dos avisos não existiam. Varredor tools/varrer_chaves_funcoes.ts: 99 funções, 0 com padrão proibido, 23/23 respondem pong no ar. O vigia dos pagamentos foi provado com um pagamento fictício (cura recusada pela Stripe, aviso com Telegram) e os dados de teste foram apagados. increment_chatbot_quota voltou a contar (o limite diário do robô nunca travava). Os 4 pagamentos sem etiqueta eram cobranças ao vivo (Tap to Pay): Jai 186 €, Vansh 291,53 € e dois de 5 € sem pista; nenhum pedido perdido. A zona vermelha (refund, dispatch-engine, stripe-webhook, client-cancel-order, finalize) foi aplicada pela Claude.ai a 01/11 a partir de docs/propostas/chaves-2026-10-31/zona-vermelha.md; fica por aplicar só a afinação do aviso para cobranças ao vivo (ponto 6). Armadilhas: a sessão ficou ~40 h parada à espera de uma confirmação do apply_migration; ao voltar, repôs por 7 min a versão antiga do vigia das chaves por cima da melhorada (reposta do histórico, md5 igual, nenhum aviso falso) — ler schema_migrations e functions list antes de reescrever. A tranca recusa ficheiros de migração com palavras de pagamento (os do vigia de pagamentos e admin_pagos_sem_pedido vivem só em schema_migrations). Skill nova: trocar-chaves-servidor. Commit 358cd9fe no ramo de produção; CI a correr (web, Android, iPhone).
