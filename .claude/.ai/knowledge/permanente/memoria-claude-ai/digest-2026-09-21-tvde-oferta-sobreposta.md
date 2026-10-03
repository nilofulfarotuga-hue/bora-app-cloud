---
id: memoria-claude-ai-digest-2026-09-21-tvde-oferta-sobreposta
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-21
zona: verde
confianca: alta
estado: atual
---

# Claude Code 20→21/09 — a oferta TVDE por cima de qualquer ecrã (o cartão que faltou na reserva da meia-noite)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-21-tvde-oferta-sobreposta`, origem `claude-code`, atualizada em 2026-09-21T00:32:45.059726+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 21 tvde oferta sobreposta · memoria claude.ai · claude_ai_memoria

O que funciona agora: a oferta de corrida TVDE (imediata e de reserva) aparece por cima de qualquer ecrã da app do motorista — corrida activa, chat, agenda, ganhos, outro papel — num cartão global (TvdeOfferOverlayHost no MaterialApp.builder) com Aceitar/Recusar sempre visíveis; quando expira diz "esta corrida já foi para outro motorista" e fecha em 5 s; uma oferta morta nunca chega ao ecrã (filtro offer_expires_at/reservation_offer_expires_at no store); "cheguei ao passageiro" já não apaga a oferta a contar; os ganchos tvdeOfferReload/tvdeReservationReload/tvdeOfferAction vivem no main.dart. A notificação da oferta tem botões Aceitar (abre a app) e Recusar (sem abrir, tvde_reject_ride por HTTP). Cliente em fila lê "aceitou a tua corrida · está a terminar outra viagem · chega em ~X min" com ETA vivo e sem "chegou" falso pela proximidade. Painel: admin_tvde_rides_list mostra a quem a oferta está a tocar e quanto falta; RPC nova admin_tvde_force_redispatch (roda nova, migration 20260920221500); chaves tvde_backtoback_* e tvde_queue_pickup_radius_km editáveis. Testes: 593 verdes, analyze 0 erros, anti-trapaça limpo. Provas em .claude/.ai/provas/tvde-oferta-sobreposta-2026-09-20 (emulador + web).
Como se usa: nada muda para o motorista — o cartão aparece sozinho; no painel, corridas ao vivo → "Forçar nova roda" quando a oferta está presa.
O que falta: (1) a Edge notify-tvde-driver v17 (ganho, prazo e actions no push) está no repo mas NÃO subiu — o .supabase-token.env dá 401 e a CLI só entra com um clique do Danilo em Authorize (consola supabase login aberta; comando: npx -y supabase@2 functions deploy notify-tvde-driver --project-ref ojykpzwqrtusfeakzrna); a v16 continua no ar e a app já mostra os botões. (2) O toque nos botões da notificação não foi provado no aparelho. (3) Incidente: às 00:50 uma corrida de teste minha foi parar ao Danilo (o emulador caiu, o sweep limpou os tentados); cancelada às 00:53 sem taxa; regra nova: com um real online, sintética em solicitada cancela-se no segundo em que expira/recusa. Relatório: .claude/.ai/reports/tvde-oferta-sobreposta-2026-09-20.md. e2e_log 2092–2097.
