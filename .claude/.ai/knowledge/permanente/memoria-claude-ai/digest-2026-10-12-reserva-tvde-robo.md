---
id: memoria-claude-ai-digest-2026-10-12-reserva-tvde-robo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-12
zona: verde
confianca: alta
estado: atual
---

# Claude Code 12/10 — robô muda a hora das reservas de corrida; destino preparado (proposta)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-12-reserva-tvde-robo`, origem `claude-code`, atualizada em 2026-10-12T19:38:20.938771+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 12 reserva tvde robo · memoria claude.ai · claude_ai_memoria

O que funciona agora: o robô de suporte (Edge support-chatbot v28) conhece as reservas de corrida (TVDE). Lista-as com agent_get_my_tvde_reservations, confirma qual é, pergunta a hora nova e chama tvde_reservation_reschedule sozinho, sem aprovação (regra do Danilo de 12/10, depois de uma cliente ter de lhe ligar para passar das 17:30 para as 17:45). Skill TVDE_RESERVATION_CHANGE activa em support_skills. Prova real na sessão c821ab81 com demo.cliente: reserva de teste 13/10 10:00 passou a 11:00 por chat, SELECT confirmou, reserva cancelada no fim. A Edge notify-tvde-driver v22 tem os avisos novos reservation_rescheduled ("A reserva passou para DD/MM às HH:MM • rota • Ganhas €X") e reservation_rescheduled_lost (texto verdadeiro quando perde por conflito); a app do motorista já os conhece. Painel admin TVDE — Reservas e app do cliente (As minhas reservas) têm Mudar hora e Mudar destino (este só com o interruptor tvde_reservation_dest_change_enabled ligado, que ainda não existe). Edge tvde-dest-change v3 aceita acções reservation_quote/reservation_change (morada escrita geocodificada + rota Google no servidor) e recusa com reservation_dest_change_disabled enquanto o interruptor não existir (provado 403). Commit ab056aa3 na branch autonomous-night-2026-04-29; CI Android 38289885173, web 38289885182, iPhone 38289885225 (ver e2e_log fluxo reserva-tvde-robo-2026-10-12 para o resultado).
PEDIDOS À CLAUDE.AI (a bora-tranca recusou no PC, não se contornou): 1) aplicar por MCP supabase/migrations/20261012180000_tvde_reserva_aviso_hora_alterada.sql (só troca os kinds do push em tvde_reservation_reschedule para reservation_rescheduled / reservation_rescheduled_lost; corpo igual ao de 20261012162206, que a Claude.ai aplicou de manhã). 2) Bloco 2 (mudar destino, mexe em dinheiro): proposta completa com SQL e prova local em .claude/.ai/missoes/reserva-tvde-robo-2026-10-12/bloco2-proposta-mudar-destino.md — só com o "vai" do Danilo; precisa também de alteração na tvde-payment auto_refund_reservation (valor_cents parcial + guarda do amount_received). Achado: repo da tvde-payment está em v18 e o ar em v19 (10/10) — pôr o repo igual ao ar antes de editar.
O que falta: migração dos kinds por aplicar; Bloco 2 por aprovar; decidir se destino mais perto devolve a diferença (proposta devolve) ou segue a regra da corrida a meio (não devolve); prova nas 3 lojas depois do CI. Relatório: .claude/.ai/reports/reserva-tvde-robo-2026-10-12.md.
ESTADO DO CI (19:38 UTC): as três plataformas saíram verdes do commit ab056aa3 — web no ar (main.dart.js servido já com Mudar hora/Mudar destino), Android versionCode 665 no Play, iPhone build 184 (CI 38289885225). Documentos e prova local no commit 738920ee.
