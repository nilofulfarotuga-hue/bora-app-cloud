---
id: memoria-claude-ai-digest-2026-10-30-gorjetas-taxa
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Claude Code 30/10 — gorjetas com a taxa, robô da Boom e publicação 7

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-30-gorjetas-taxa`, origem `claude-code`, atualizada em 2026-10-30T23:24:35.158486+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 30 gorjetas taxa · memoria claude.ai · claude_ai_memoria

A missão gorjetas-taxa-2026-10-30 (ordem do Danilo de 30/10 13:40) ficou feita na app e no painel e entrou em produção com a publicação 7 (56734748, 30/10 21:25, autorizada pelo Danilo às 20:23). Na app, a gorjeta do carrinho pode ir no mesmo pagamento da compra (interruptor tips_checkout_junto_pagamento, desligado); o estafeta vê em cada gorjeta paga depois o valor, a taxa e quanto recebe; o painel mostra taxa, líquido, quem pagou e como, com totais. Testes 2464/2464, analyze limpo, juiz limpo. O servidor das gorjetas está pronto mas NÃO aplicado: a tranca recusou as migrações que falam da Stripe e as quatro funções vermelhas (create-payment-intent, create-mbway-payment-intent, stripe-webhook, client-cancel-order). Está tudo em docs/propostas/gorjetas-taxa-2026-10-30/ com a ordem no pagamentos_LEIA-ME.md: 144900 → 145000 → 150000 → 151000, funções fora da zona vermelha, patches vermelhos, prova em rollback, e só depois ligar o interruptor. A 20261030144900 está no repo mas não aplicada; sem ela a app nova comporta-se como a antiga. Achados por decidir (dinheiro): create_order aceita payment_already_confirmed de qualquer cliente com sessão (e2e 5454); lastCreatedOrderId velho no cartão pode cobrar a gorjeta no pedido anterior (5455); a gorjeta conta no acerto pela data do pagamento e não da entrega. Robô da Boom: em modo teste, os números da allowlist já são atendidos com a loja em breve (restaurante.py, 6abb55a2), os outros continuam a ouvir "abre em breve"; coming_soon na base intocado; provado por simulação (e2e 5490). A ponte WhatsApp esteve calada depois das 20:08; foi reiniciada às 20:32, não havia mensagem pendente para repetir, causa por provar (5491); depois caiu e voltou sozinha às 22:05 (408) e às 22:38 (428), um processo só. Publicação 7 provada (e2e 5538): web no ar com o bundle das gorjetas; Android versionCode 702 na Play; iPhone build 220 VALID, a 1.0.31 já aprovada e à venda, a 1.0.32 submetida e em WAITING_FOR_REVIEW com lançamento automático. Os ramos locais do PC estão atrás de origin (commit do CI d8c927e5): git pull --rebase antes de trabalhar.
