# ESPEC — missao-geral-2026-10-28

Escrito a 28/10/2026, 21:00, no Bloco 0. Cada sessão que pegue nesta missão lê isto primeiro
e acrescenta no fim cada decisão nova, com a data.

## Objetivo

1. App do estafeta: o Confirmar do talão funciona com qualquer escrita do valor, o erro aparece
   dentro da folha, a recolha mostra o nome da loja, e o valor a cobrar em dinheiro vem sempre
   do servidor (`cash_total_due`), já sem o que o cliente pagou com saldo e tokens.
2. Cancelamentos: devolve-se ao MB Way ou ao cartão por defeito, ou 100% em saldo Bora se o
   cliente escolher. Acabou o 80/20. Os tokens gastos voltam como tokens.
3. Boom! Burger: NIF opcional, entrega grátis acima de 30 € no ecrã, painéis, IVA das faturas
   da Bora (regime normal a partir de 01/11), restos do adendo 3.
4. Robô de pedidos da Boom pelo WhatsApp, em teste, só para o número do Danilo.
5. Cartazes da Boom (logótipo da Boom + logótipo da Bora).
6. Erros abertos: 401 vindo da VPS, carrinho que confunde parceiro com não-parceiro, e os
   reportados que ficaram por fazer.

## Quem usa

Estafetas (app, PT-PT), clientes (app, PT-PT), parceiro Boom (painel do parceiro, PT-PT),
Danilo e Claude.ai (painel admin, PT-BR), escritório de contabilidade (CSV semanal, não se
envia nada).

## O que NÃO se toca (fronteiras)

- Preços, taxas, comissões, percentagens. Os preços da Boom ficam como estão.
- Devolver dinheiro a alguém ou mexer em saldos reais.
- F5 (sinal das reservas, ramo consertos-boom-f5-sinal): só com "autorizo F5".
- Publicar: só com "publica" (passos publica-autorizado-1/2 no e2e_log ou o Danilo na sessão).
- Abrir a Boom ao público: coming_soon fica true.
- Mensagens para fora (Emanuel, escritório, gráfica, grupos, clientes): nenhuma. Para fora só o
  Telegram ao Danilo.
- Ficheiros: lib/stores/order_store.dart, lib/widgets/errand_execution_sheet.dart,
  lib/services/pricing_service.dart, dispatch_engine*, .github/workflows/**, .claude/hooks/**,
  settings, bora-mods.
- Edge Functions: client-cancel-order, refund, reprocess-refund, stripe-webhook,
  create-payment-intent, create-mbway-payment-intent, finalize-order-from-intent, charge-extra,
  dispatch-engine.
- Funções de dinheiro (lista MONEYFN) e tabelas de dinheiro: nenhum DDL nem DML. O conserto que
  cair aí vai preparado para docs/propostas/missao-geral-2026-10-28/ e para o Claude.ai.
- Repositório público: sem nomes, telefones, ids de pedidos de clientes reais, NIF, nome da
  empresa.

## Decisões já tomadas

- 28/10 18:24 (Danilo): reembolso 100% ao meio original por defeito, ou 100% saldo; tokens
  voltam como tokens; acabou o 80/20. `wallet_split_free_pct` = 1 desde as 18:27.
- 28/10 18:31 (Danilo): cobrar ao cliente o total menos o que pagou com saldo e tokens.
- 28/10 12:17 (Danilo): NIF opcional; entrega grátis acima de 30 € na Boom.
- 28/10 16:49 (Danilo): não subir o escondido dos parceiros para 10% por agora.
- 28/10 (contabilista): a empresa está no IVA normal, trimestral. A partir de 01/11 as faturas
  da Bora dizem "IVA 23% incluído — regime normal". Aplicado na JANELA 1 (20261028203348).
- 28/10 21:00 (esta missão, Bloco 0): no conflito entre o ramo da Boom e o adendo das melhorias
  sobre o horário das lojas, a app segue o servidor (`is_partner_open` olha só ao horário do
  próprio dia, também na madrugada). A regra "a madrugada conta pela véspera" fica reportada
  como proposta para o servidor primeiro, porque com a app diferente do servidor o pedido cai
  no fim com STORE_CLOSED.
- 28/10 21:00 (esta missão): o ramo melhorias-paridade foi juntado até 931b1836 (inclui o adendo
  da revisão 5fcf75cf e os itens 13-14), porque o adendo resolve o carrinho reposto como
  parceira (E2). Em commit separado, para se poder separar se for preciso.
