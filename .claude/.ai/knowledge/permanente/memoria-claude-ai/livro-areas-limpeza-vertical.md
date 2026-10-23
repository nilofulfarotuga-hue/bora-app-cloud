---
id: memoria-claude-ai-livro-areas-limpeza-vertical
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App Limpeza (cleaning) vertical — Helpling-style booking and dispatch

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-limpeza-vertical`, origem `claude-ai`, atualizada em 2026-10-23T05:38:59.319019+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas limpeza vertical · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/limpeza-vertical.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: limpeza-vertical
description: Bora App Limpeza (cleaning) vertical — Helpling-style booking and dispatch
sources: [backfill]
aliases: [Limpeza]
---
- [stated] Cleaning vertical of Bora App, went live with candidate bugs fixed (address geocoding + MIME HTTP 400), awaiting E2E device test on build ~370
- [stated] Full Helpling-style implementation: scheduled, fixed pricing T0–T4+, professional availability dispatch model, 85/15 split, materials +€3, recurrence –10%, bidirectional chat, KYC, dual-rating, complete admin
- [stated] Multi-role estafeta⇄limpeza closed (drivers/cleaners linked by user_id)
- [stated] Two bookings stuck (cleaner_id=null, zero availability rows), confirmed via MCP
- [stated] Minimum lead time removed (was 12h)
- [stated] Candidate flow bugs fixed: address geocoding (commit 6a5d74a) and MIME HTTP 400 (commit 9185112) — both confirmed client-side Flutter, bucket/RLS were correct

Limpeza fica ATIVA mas sem limpadoras (2026-07-31)
- [stated] DECISÃO Danilo: NÃO pôr Limpeza em "Em breve". Fica a funcionar normalmente com os horários disponíveis; quando alguém pedir, ele corre atrás de uma limpadora à mão nesse momento. Por isso quer aviso IMEDIATO e persistente.
- [stated] Quer o aviso por: notificação persistente no app/painel admin dele + Telegram (já tem caminho, mesmo do talão do estafeta) + idealmente WhatsApp/chamada.
- [stated] FEITO por MCP: trigger `trg_cleaning_notify_admin_new` (AFTER INSERT em cleaning_bookings, ignora is_test_order) → chama `notify_admin_urgent_push` com severidade high. Grava em admin_notifications (badge/inbox) E dispara push persistente pela Edge `notify-admin-urgent`. Resumo traz cliente, tipo, tamanho/horas, data/hora Lisboa, morada, valor e método de pagamento + deep-link /admin/limpeza/{id}. Confirmado que o token FCM de admin do Danilo está registado e em uso (admin_push_tokens, 1 device android).
- [stated] Antes disto, `create_cleaning_booking` NÃO avisava o admin — só `_cleaning_next_offer` avisava, e apenas quando não havia limpadora disponível.
- [stated] PENDENTE: ponte para Telegram. O Telegram vive no Hermes/VPS (`hermes send`), NÃO há bot token no vault do Supabase (só project_url, service_role_key, dispatch_anon_jwt) nem função Edge de Telegram. Caminho decidido: gravar telegram_bot_token + telegram_admin_chat_id no vault e estender a Edge `notify-admin-urgent` para também dar POST na API do Telegram — vai em prompt Claude Code (só ele alcança a VPS para ir buscar o token).
- [stated] 01/10/2026: Danilo arranjou a primeira limpadora real, Mayra (Mayra Suzy Abreu Da Silva), encontrada pelo grupo dos brasileiros da Guarda; registou-se no Bora e ele mandou aprovar (conta de limpadora aprovada; não precisa de carta de condução para limpeza)
- [stated] 09/10/2026: a Mayra SÓ faz limpeza (não faz entregas). Regra do Danilo: quem só faz limpeza, ao entrar pelo lado do estafeta e pôr o login, vai direto para a parte da limpeza; e a oferta de limpeza tem de tocar persistente, igualzinho ao estafeta e ao motorista, até ela aceitar ou recusar
- [stated] 12/10/2026: a Mayra disse-lhe que tem atividade aberta nas Finanças; ele ia mandar-lhe mensagem nessa noite a explicar que o Bora vai ser legalizado (faturas dela por autofaturação, ver [[faturacao-fiscal]])

FINAL WRITE
- [stated] 15/10/2026: regra do Danilo — sempre que houver uma limpeza, a profissional tem de ver no app (campo próprio, português simples) o que tem de fazer conforme o tipo (Standard, Profunda…) e o que tem de levar (produtos sim ou não, aspirador, etc.); e o robô do suporte tem de saber explicar isso ao cliente
- [stated] 19/10/2026: regra do Danilo — só se chama a limpadora se a limpeza estiver paga: MB Way tem de estar pago antes de chamar; dinheiro chama logo. Numa limpeza semanal vale o dia e a hora que o cliente programou (um reagendamento pontual não muda as seguintes)
- [stated] 20/10/2026: regra do Danilo — o cadastro de TODOS os prestadores (limpadora, estafeta, motorista) tem de pedir e guardar o comprovativo de atividade aberta nas Finanças; e o pedido MB Way da limpeza tem de chegar ao cliente sozinho e a tempo antes do dia, senão a limpadora não vai

