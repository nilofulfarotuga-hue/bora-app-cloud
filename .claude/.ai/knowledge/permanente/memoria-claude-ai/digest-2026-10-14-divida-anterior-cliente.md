---
id: memoria-claude-ai-digest-2026-10-14-divida-anterior-cliente
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-14
zona: verde
confianca: alta
estado: atual
---

# Claude Code 13-14/10 — dívida anterior visível ao cliente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-14-divida-anterior-cliente`, origem `claude-code`, atualizada em 2026-10-14T07:52:13.262981+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 14 divida anterior cliente · memoria claude.ai · claude_ai_memoria

Missão só de ecrã, autorizada pelo "Vai" do Danilo a 13/10. O cliente com dívida de cancelamento passa a ver a dívida e o total com ela, o mesmo número que o estafeta cobra à porta. Novo getter OrderModel.totalWithDebt: em dinheiro é o totalToCollectCash; em cartão/MB Way é (finalTotal ?? total) + debt_collected_cents/100. Detalhe do pedido: linha "Dívida anterior" e Total com a dívida. Acompanhamento: linha "Dívida anterior" e "Total a pagar". Os meus pedidos: total com a dívida e "Inclui €X de dívida anterior" (inglês em strings_en.dart e pt-en-16-divida-anterior.json). Painel admin: "Dívida anterior cobrada neste pedido" no resumo e no separador Pagamento. Nenhum valor cobrado mudou. Commit 20793e9b; CI 4/4 verde (Android 667, web no ar, iPhone 187). Teste test/divida_anterior_cliente_test.dart chumba com o ecrã antigo. FALTA, à espera do Danilo (dinheiro): fn_apply_client_debt_settlement_on_cash_delivery desconta ao estafeta o saldo negativo da carteira no momento da entrega, não o debt_collected_cents do pedido; hoje 0 casos desencontrados em produção. Também reportados sem correcção: errand_execution_sheet (folha antiga do favor) cobra sem a dívida; cartão "Cash entregue" do admin mostra o recebido sem a dívida; reembolso de cancelamento no detalhe usa o total sem a dívida. Relatório: .claude/.ai/reports/divida-anterior-cliente-2026-10-13.md. e2e_log run_id divida-anterior-cliente-2026-10-13.
