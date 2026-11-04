---
id: memoria-claude-ai-digest-2026-11-04-checkin-premios-fecho
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Digest 04/11 — check-in prémios e Favor (fecho)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-04-checkin-premios-fecho`, origem `claude-code`, atualizada em 2026-11-04T15:31:48.12237+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 04 checkin premios fecho · memoria claude.ai · claude_ai_memoria

Continuacao 14:17 da missao checkin-escada-premios-2026-11-04 (PC, Claude Code). A correcao S2 do premio no talao tinha ido para finalize_storeshopping_purchase_v2, mas a app fecha o talao do nao-parceiro por finalizar_talao_nao_parceiro; a mesma regra foi aplicada na funcao certa por MCP (versao 20261104145309), provada antes em rollback: Big Mac de premio, cliente paga 3,59, reembolso ao estafeta pending_admin 450, ganho do estafeta 5,20 igual, pedido normal igual. Ligados os 7 degraus de produto (8,11,12,13,17,18,20), backup bkp_checkin_marcos_20261104, confirmados por _checkin_estado_marcos. Os 6 degraus de desconto ficam desligados: o desconto esta provado no servidor (40,43 para 37,43, estafeta 5,57 igual) mas o order_store, que manda o checkin_vale_id ao create_order, e zona vermelha da tranca; a app tem o desconto pronto e desligado (CartStore.descontoCheckinNoPedido). Erro encontrado: o gatilho de cancelamento so devolve vales de pedidos com artigo premio-checkin-, o vale de desconto fica usado; proposta de uma linha em docs/propostas (a trava bloqueou). Com a conta demo nao se prova devolucao de vale: o pedido demo nasce driverAccepted. Favor: cartao "Pagar a diferenca", painel "Diferencas de Favor", "Marcar entregue sem codigo" e ramo errand_extra no webhook partilhado ficaram na app; o servidor (tabela favor_diferencas e 6 funcoes) foi bloqueado pela tranca e esta em docs/propostas para a Claude.ai aplicar; blocos B e D vivem no errand_execution_sheet (zona vermelha). Selo Frescura fora da Mercadona Beleza. Juiz: anti-trapaca limpo, analyze sem erros, 2902 testes verdes em 268 ficheiros. Commit 94b5b203 enviado; e2e_log 6613-6620. Relatorio .claude/.ai/reports/checkin-escada-premios-fecho-2026-11-04.md.
