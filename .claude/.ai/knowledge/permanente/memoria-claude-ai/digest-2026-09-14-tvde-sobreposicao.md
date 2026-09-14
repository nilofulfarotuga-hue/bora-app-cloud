---
id: memoria-claude-ai-digest-2026-09-14-tvde-sobreposicao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-14
zona: verde
confianca: alta
estado: atual
---

# Sobreposição TVDE (back-to-back) 14/09 — Opus, Claude Code — resultado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-14-tvde-sobreposicao`, origem `claude-code`, atualizada em 2026-09-14T19:00:05.184449+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 14 tvde sobreposicao · memoria claude.ai · claude_ai_memoria

O que funciona agora: um motorista a meio de uma corrida também recebe ofertas TVDE — a oferta aparece por cima do ecrã da corrida que ele leva (ganho em grande, "depois desta corrida", distância de onde larga até onde vai buscar), ele aceita e continua no passageiro actual, a nova fica no cartão "Próxima corrida" e no mapa em tom mais claro, e quando termina a app abre sozinha a seguinte (provado no emulador, vídeo P3_transicao_automatica.mp4). O cliente em fila vê "o teu motorista está a terminar uma corrida aqui perto · chega em ~N min" com o tempo somado (RPC tvde_ride_queue_info). O despacho (tvde_offer_to_next) passou a um pool único: primeiro os livres por distância (igual a antes), depois os ocupados elegíveis por destino→recolha; o ocupado entra na mesma rotação (recusa/expira → segue, pode voltar ao livre). tvde_accept_ride mete em fila com qualquer corrida activa e tem guarda contra duas activas (ride_conflict/queue_full). tvde_cancel_ride: largar só a da fila não promove outra. tvde_finish_ride NÃO foi tocada (já promovia a fila). Settings novas no painel (categoria tvde): tvde_backtoback_enabled=true (false volta ao comportamento antigo, provado), tvde_backtoback_max_queue=1, tvde_backtoback_min_stage=motorista_a_caminho, tvde_queue_pickup_radius_km 3→5. Admin: admin_tvde_reassign_ride (aceita drivers.id ou user_id, grava user_id; livre → directo, ocupado → fila; auditado; push) + botão "Reatribuir corrida" no ecrã das corridas com selector livre/ocupado + "Em fila atrás de / Leva atrás". Edge notify-tvde-driver v16 com kinds queued_added / ride_assigned / ride_reassigned_away (kinds antigos intactos). Migrations 20260914150204 e 20260914151041 no repo. flutter analyze 0 erros, 521 testes verdes. INCIDENTE: às 16:51 um pedido de teste meu foi oferecido ao Valdemir (real), ele aceitou e cancelei 37 s depois (push de cancelamento, sem taxa) — a Edge re-ancora o offer_expires_at para 40 s depois do push e o sweep limpa os tentados após 35 s; com motoristas reais online, pedido sintético só sem passar pela oferta. Por provar: o texto do push queued_added num telemóvel com token; o ecrã do painel admin ao vivo. Provas em .claude/.ai/provas/tvde-sobreposicao-2026-09-14/ e relatório em .claude/.ai/reports/tvde-sobreposicao-2026-09-14.md (cópia em Desktop/Bora/prompts). Publicado por push no ramo autonomous-night-2026-04-29 (CI faz build Android + web).
