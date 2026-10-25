---
id: memoria-claude-ai-digest-2026-10-25-tres-tarefas-noite
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-25
zona: verde
confianca: alta
estado: atual
---

# Digest — sem margem não-parceiro, botão chamar entregador já, nome do cliente e valor real da caixa (25/10 noite)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-25-tres-tarefas-noite`, origem `claude-code`, atualizada em 2026-10-25T22:46:10.545931+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 25 tres tarefas noite · memoria claude.ai · claude_ai_memoria

Feito no código (ramos locais no PC, NÃO enviados: a bora-tranca recusa push e migrações sem caixa humana): envio-sem-margem-2026-10-25 (7d5d0b34: ecrã do estafeta sem a linha "Cliente recebe € de reembolso" — conta errada 6,39 vs 3,90 —; painel explica non_partner_payment_buffer_multiplier=1,0 = sem margem) + por cima envio-nome-cliente-valor-caixa-2026-10-25 (4859d0eb: nome do cliente em destaque com Ligar em todas as fases; oferta só primeiro nome; talão pergunta "Quanto pagaste na caixa?" e "Bora reembolsa-te" deixa de mostrar o catálogo). envio-botao-chamar-estafeta-2026-10-25 (5e97e71c: botão "Chamar entregador já" no painel das encomendas por telefone + migração 20261025230000_admin_chamar_estafeta_ja.sql por aplicar).
Confirmado por leitura: create-mbway-payment-intent v30 e create-payment-intent v34 no ar cobram payment_buffer_total; create_order/quote_order_pricing fazem buffer = charge_total × multiplicador (=1). O servidor já reembolsa o estafeta pelo valor escrito (order_driver_reimbursement), usado no acerto, ledger, extrato e painel.
Por decidir (dinheiro): Fuku a1c4c62e escrito 9,90, pago 7,50 (admin_corrigir_talao); McDonald's 4c462849 cliente pagou 29,89 por 25,99 (margem antiga 3,90). Relatório: .claude/.ai/reports/tres-tarefas-25-10-noite.md.
