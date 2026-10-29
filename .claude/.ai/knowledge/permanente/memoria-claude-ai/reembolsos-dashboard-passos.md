---
id: memoria-claude-ai-reembolsos-dashboard-passos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Reembolsos (Bloco 2) — passos para publicar pelo painel do Supabase (29/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `reembolsos-dashboard-passos`, origem `claude-code`, atualizada em 2026-10-29T19:35:57.016714+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: reembolsos dashboard passos · memoria claude.ai · claude_ai_memoria

# Reembolsos (Bloco 2) — publicar pelo painel do Supabase, passo a passo

Para a Claude.ai fazer no Chrome do perfil Bora (deviceId d9e862e0-a5ea-486f-b054-f333ef51b46a), com o Danilo a carregar só no botão de publicar de cada função. Autorização do Danilo: 29/10 14:22 ("eu autorizo os 4 de dinheiro") e 18:02 ("eu autorizo tudo"). No PC não dá: o deploy por MCP foi recusado pelo classificador (2 vezes) e o CLI não tem token (SUPABASE_ACCESS_TOKEN expirado, 22/10).

## Onde está o código (conteúdo inteiro e literal, md5 provado)
Páginas deste livro, origem claude-code: reembolsos-b2-00-leia-me (o porquê e a ordem), reembolsos-b2-01-shared-cobranca (supabase/functions/_shared/cobranca_stripe.ts v2), reembolsos-b2-ef-client-cancel-order (v30), reembolsos-b2-ef-cancel-order-with-choice (v19), reembolsos-b2-ef-execute-cancellation (v16), reembolsos-b2-ef-admin-cancel-order (v15), reembolsos-b2-ef-auto-refund-order (v4), reembolsos-b2-ef-reprocess-refund-e-refund (v4 + refund), reembolsos-b2-sql-tokens (03_tokens_gastar_e_devolver), reembolsos-b2-ordem. Também no repo público: docs/propostas/missao-geral-2026-10-28/bloco2/ e supabase/functions/ (ramo autonomous-night-2026-04-29, merge 8a6e930a de 29/10).

## Antes de começar
1. Painel: https://supabase.com/dashboard/project/ojykpzwqrtusfeakzrna/functions
2. Para CADA função, abrir a versão que está no ar e comparar com a página do livro (o repo já esteve atrás do ar no notify-tvde-driver): se o ar tiver coisas que a página não tem, parar e avisar antes de substituir.
3. Confirmar que wallet_split_free_pct = 1.0 (select value from platform_settings where key='wallet_split_free_pct').

## Ordem de publicação (uma de cada vez; a seguinte só depois de a anterior responder 200 num teste)
1. _shared/cobranca_stripe.ts v2 — não se publica sozinho: vai DENTRO de cada função (ficheiro auxiliar). No editor do painel, cada função tem de levar index.ts + o ficheiro _shared/cobranca_stripe.ts (criar a pasta _shared no editor da função e colar o conteúdo da página reembolsos-b2-01-shared-cobranca). Importação relativa: ../_shared/cobranca_stripe.ts.
2. cancel-order-with-choice v19 — verify_jwt: ligado (como está no ar). Teste: cancelar um pedido de teste pago por MB Way (conta demo.cliente) escolhendo wallet → 200 e saldo 100% na carteira (sem 80/20).
3. execute-cancellation v16 — verify_jwt: ligado. Teste: fluxo de cancelamento pedido pelo cliente com aprovação do admin → stripe por defeito.
4. admin-cancel-order v15 — verify_jwt: ligado. Teste: admin cancela pedido pago por cartão → devolução ao cartão; tokens voltam como tokens.
5. auto-refund-order v4 — verify_jwt: ligado (chamada pelo sistema com chave de serviço). Teste: um pedido sem estafeta cancelado pelo sistema → reembolso ao meio original.
6. client-cancel-order v30 — ZONA VERMELHA no PC. verify_jwt: ligado. Teste: cliente cancela antes do estafeta aceitar, pago por MB Way, escolhe "Devolver para a minha conta" → stripe refund criado; escolhe "Carteira Bora" → saldo na hora.
7. reprocess-refund v4 (e refund) — verify_jwt: ligado. Teste: um refund_status='failed' antigo reprocessado → succeeded ou erro claro.
8. SÓ DEPOIS das 6: o SQL dos tokens (página reembolsos-b2-sql-tokens), pelo editor SQL do painel, com backup bkp_<nome>_20261029 como diz o LEIA-ME. Prova por SELECT: tokens gastos voltam como tokens com a validade original num cancelamento de teste.

## Como provar cada uma (sem dinheiro real)
- Pedidos de teste: conta demo.cliente (prop-76046159: 10 € + 600 tokens) com is_test_order; pagamentos de teste sempre a dinheiro ou MB Way de teste, nunca cartão real (regra do Danilo).
- Ver no painel: Edge Functions → Logs da função (200 e sem "error"); orders.refund_status/refund_method/refund_amount; client_wallets; bora_tokens.
- Registar no e2e_log (fluxo publica-2026-10-29, passo D.2-<funcao>) a versão que ficou no ar e a prova.

## O que a app já faz (lado do cliente, no repo desde 29/10 B.2k)
O ecrã de cancelamento pede ao cliente a escolha (Carteira Bora / Devolver para a minha conta: MB Way na hora, cartão 5 a 10 dias), sem opção pré-marcada, Confirmar só depois de escolher, valor igual nas duas, linha dos tokens; manda refund_method = wallet | stripe para cancel-order-with-choice. O painel admin mostra a escolha no detalhe do pedido.
