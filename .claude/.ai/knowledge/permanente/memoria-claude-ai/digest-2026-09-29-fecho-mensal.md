---
id: memoria-claude-ai-digest-2026-09-29-fecho-mensal
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-29
zona: verde
confianca: alta
estado: atual
---

# Claude Code 29/09 — fecho mensal e modelo fiscal de 01/10

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-29-fecho-mensal`, origem `claude-code`, atualizada em 2026-09-29T21:42:44.243273+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 29 fecho mensal · memoria claude.ai · claude_ai_memoria

Setembro fechado e confirmado por SQL: 17 entregas reais, clientes pagaram 371,40 EUR, mercadoria 275,19, receita própria da Bora 96,21, estafetas 87,93, lucro 8,28. Parte da Bora na TVDE de outros motoristas 10,00 (sem o Danilo e sem contas de teste). As 4 faturas-recibo que o Danilo passou à mão saem iguais: Goola 8,76 (NIF 519478428), Sabores de Casa 5,05 (sem NIF na base), consumidor final 82,40 e 10,00.
Regras de custo usadas: loja parceira = ledger earning restaurant; não-parceiro = talão (order_receipts_v2); sem talão = subtotal a dividir por 1,15. Comissão da loja parceira = subtotal menos parte da loja.
Como se usa: public.admin_monthly_closeout(ano, mes) dá o mês inteiro, com o bloco para_as_financas pronto para o recibo verde. public.partner_monthly_statement(loja, ano, mes) é o extrato da loja (só a própria vê). Painel: /admin/fecho-mensal (Dinheiro e acertos, Fecho do mês), com CSV, PDF, reenviar extrato e Exportar DAC7. App do parceiro: cartão Este mês nos Ganhos, com PDF.
Email: Edge Function monthly-partner-statement, cron 88 no dia 1 às 09h de Lisboa, registo em monthly_statement_log (não repete sem force). Prova: extrato de setembro enviado à Goola a 29/09.
Modelo a partir de 01/10: termos novos com aceitação obrigatória (cliente e estafeta de entregas), estafeta confirma NIF e atividade aberta (prazo 15/10; depois não fica online na app), resumo do recibo verde no dia 1 e aviso ao admin no dia 10 (cron 89). Fatura da parte da Bora por pedido em bora_invoices_pending (lançar à mão no Portal). DAC7: admin_dac7_report(ano).
Falta: bloqueio no servidor ao aceitar entrega (zona do dispatch) em platform_settings.staged_fecho_mensal_20260929, à espera do vai. NIF do cliente no checkout não existe. MB Way grava stripe_charge_cents=0. Relatório: .claude/.ai/reports/RELATORIO-fecho-mensal-2026-09-29.md.
