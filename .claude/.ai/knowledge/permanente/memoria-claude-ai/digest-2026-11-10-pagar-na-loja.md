---
id: memoria-claude-ai-digest-2026-11-10-pagar-na-loja
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-10
zona: verde
confianca: alta
estado: atual
---

# Digest 10/11/2026 — missão pagar-na-loja (estafeta paga a loja parceira na recolha)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-10-pagar-na-loja`, origem `claude-code`, atualizada em 2026-11-10T22:38:28.604929+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 10 pagar na loja · memoria claude.ai · claude_ai_memoria

A missão pagar-na-loja-2026-11-10 (autorização do Danilo por voz às 21:33, "Pode.") acertou o pedido 6d38f5e5 da Boom! Burger: o estafeta tinha pago 13,80 € à loja na recolha e recebido 19,71 € da cliente, mas as contas tratavam o pedido como se a Bora pagasse a loja no fecho. Agora o estafeta deve 1,67 € por esse pedido (era 15,47 €), o saldo dele passou de 20,23 € para 34,03 € e a Boom fica com 0,00 € a receber desse pedido, comissão igual (2,30 €); cópia em bkp_acerto_graca_boom_20261110 e 63 fechos comparados antes e depois, só mudaram esses dois. A regra nova (business_rules 2.4.2) ficou no servidor: o pedido grava loja_pagamento_estado e loja_pagar_valor (gatilho zzzz_orders_loja_pagamento) e, na recolha de um pedido de app a dinheiro em loja parceira, marca is_purchase_finalized e final_purchase_value com o preço de balcão; o acerto do estafeta, o fecho da loja (pago_em_mao_na_recolha), os recibos e o extrato contam isso; o admin corrige pelo RPC admin_corrigir_pago_loja. Armadilha: nesses pedidos final_purchase_value é o pago à loja, não o valor dos produtos; a divisão do pedido (apply_order_financial_split) e os extratos da loja foram protegidos para continuarem a usar o subtotal. Prova R1 a R5 em transação desfeita: R1 loja 0 / estafeta -1,67, os outros iguais a hoje. O notify-driver v45 já está no ar com a frase "Pagas X na loja · Cobras Y". A app (faixa grande no mapa do estafeta, aviso no painel do parceiro, secção no admin) está no ramo ai/2026-11-10-pagar-na-loja com o pedido de revisão #10 para o autonomous-night-2026-04-29: a bora-tranca do PC recusou o envio direto para produção, por isso falta juntar o #10 (dispara Android, iPhone e web) e provar as 3. Testes no PC: 3332, só vermelhos os 6 do ListTile do Flutter 3.47 (o CI usa 3.41). A pasta C:\BoraLocal\projetosflutter\bora_app está 594 versões atrás do remoto; o trabalho foi feito no worktree C:\BoraLocal\wt-pagar-loja-10-11. Reportado sem mexer: três pedidos antigos a dinheiro na Goola Açaí (05/09, 14/10, 05/11) foram contados com a Bora a pagar a loja, em semanas já pagas. Relatório: .claude/.ai/reports/pagar-na-loja-2026-11-10.md; e2e_log fluxo pagar-na-loja-2026-11-10.
