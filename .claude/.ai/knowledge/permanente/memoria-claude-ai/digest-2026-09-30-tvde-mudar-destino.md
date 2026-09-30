---
id: memoria-claude-ai-digest-2026-09-30-tvde-mudar-destino
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-30
zona: verde
confianca: alta
estado: atual
---

# Claude Code 30/09 — TVDE mudar destino

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-30-tvde-mudar-destino`, origem `claude-code`, atualizada em 2026-09-30T13:07:08.889916+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 30 tvde mudar destino · memoria claude.ai · claude_ai_memoria

Mudar destino a meio da corrida TVDE está construído e no servidor, mas o interruptor tvde_dest_change_enabled está DESLIGADO (false) até a app nova estar nas lojas; liga-se no painel admin (Configurações, tvde). Regra do Danilo: novo total de km = km feitos desde a recolha + rota do carro ao destino novo; mais longe paga preço novo menos preço combinado atual, mínimo 2 euros (motorista 80/km, mínimo 1 euro); mais perto não paga nem recebe. Os km são SEMPRE do servidor: Edge tvde-dest-change (v2) pede a rota ao Google com a chave do servidor e grava em tvde_dest_change_routes; as RPCs tvde_dest_change_quote/request só aceitam essa rota (60 s, mesmo estado da corrida). Cartão/MB Way: tvde-payment v17 acções charge_dest_change e confirm_dest_change_payment, PI com kind bora_dest_change (o stripe-webhook ignora); varrimento sweep_dest_changes pelo cron tvde-dest-change-sweep de 2 em 2 min aplica pagamentos tardios e devolve o que não se aplicou ou cuja corrida foi cancelada. tvde_finish_ride só ganhou somas (dest_change_extra_fee_cents / _driver_cents, dinheiro da mudança no acerto) e a volta do pacote só é grátis até à ida combinada (dest_change_base_km); backups em fn_definition_backups. Histórico em tvde_destination_changes; painel: botão Destino / mudanças em cada corrida (e mudança de corrida de balcão com valor à mão). Provas em .claude/.ai/provas/tvde-mudar-destino-2026-09-30 (4 exemplos certos em dinheiro e cartão; sem mudança = igual à função antiga). Nunca fazer UPDATE directo a tvde_rides para mudar destino: usar as funções. Relatório: .claude/.ai/reports/tvde-mudar-destino-2026-09-30.md. Falta: ligar o interruptor, 1.º teste real em dinheiro, decisão do Danilo sobre a volta do pacote (MÉDIO 6).
