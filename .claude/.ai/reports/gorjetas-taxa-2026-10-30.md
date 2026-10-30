# Gorjetas com a taxa certa — relatório (30/10/2026)

Missão `gorjetas-taxa-2026-10-30`, feita a partir da tua ordem de 30/10 às 13:40. O trabalho está no ramo
`gorjetas-taxa-2026-10-30`; nada foi publicado e nada foi aplicado em produção por esta sessão.

## O que ficou feito

A regra ficou escrita em todo o lado como disseste:
- A gorjeta dada no carrinho com cartão ou MB Way vai no mesmo pagamento da compra e o estafeta recebe-a inteira.
- A gorjeta paga depois, na avaliação, é um pagamento à parte, e o estafeta ou o motorista recebe a gorjeta menos
  a taxa da Stripe desse pagamento.
- A gorjeta em dinheiro vai inteira.
- A Bora não fica com nada, e se o pedido for cancelado a gorjeta volta inteira ao cliente.

O desconto da taxa na gorjeta paga depois já estava no ar desde as 13:50, posto pela Claude.ai. Confirmei-o com a
gorjeta real de 29/10: 2,00 € menos 0,28 € dá 1,72 € ao motorista, e o acerto da semana dele soma 1,72 €.

Na app do cliente, quando o modo "junto" estiver ligado, o carrinho já mostra a gorjeta no total e o cliente aprova
um pagamento só. Desligado, fica tudo como hoje. O estafeta passa a ver, em cada gorjeta paga depois, quanto foi, a
taxa e quanto recebe. No painel vês, por gorjeta, a taxa, o que o estafeta recebeu, quem pagou a taxa e como foi
paga, com os totais do período. Tens também o interruptor do modo "junto", que está desligado.

O servidor também está todo feito:
- cobrar a gorjeta junto com a compra;
- nunca a cobrar duas vezes, mesmo com as apps antigas;
- devolvê-la inteira quando o pedido é cancelado, uma vez só e pelo meio que o cliente escolheu;
- uma verificação de 15 em 15 minutos que apanha o que escapar;
- ir buscar à Stripe, ao domingo antes do fecho, as taxas que faltarem.

Um revisor independente tentou derrubar este trabalho. Encontrou seis falhas de dinheiro (uma gorjeta MB Way que
podia ficar presa, uma devolução em dobro possível depois de uma falha de rede, e outras), e foram todas corrigidas.

Os testes passaram:
- os da app: 2464 de 2464;
- os do servidor: 16 de 16 e 25 de 25;
- o Juiz anti-trapaça deu limpo.

## O que falta, e porquê

⚠️ ISTO MEXE EM DINHEIRO — está tudo pronto.

A tranca não me deixa mexer nas quatro funções que cobram e devolvem o pagamento da compra (criar o pagamento por
cartão, criar o MB Way, o webhook da Stripe e o cancelamento pelo cliente). Também não me deixa guardar no
repositório migrações que falem da Stripe. Não contornei: as mudanças estão prontas, feitas contra a versão que
está no ar, na pasta `docs/propostas/gorjetas-taxa-2026-10-30/`, com a ordem certa no ficheiro `pagamentos_LEIA-ME.md`.

Não pus o servidor no ar sozinho. Hoje não há nenhuma gorjeta para devolver nem nenhuma taxa em falta, por isso
não se ganhava nada. A parte principal só funciona quando as quatro funções vermelhas entrarem, e tem de entrar
tudo junto e pela ordem. Pôr metade no ar só trazia risco.

O modo "junto" fica desligado até isso estar no ar e provado. A app nova entra na publicação do fim de semana.

## Erros que encontrei pelo caminho (não corrigi, são dinheiro)

1. Grave, para ver primeiro. A função que cria os pedidos aceita de qualquer cliente com sessão a marca "pagamento
   já confirmado". Com essa marca, o pedido nasce pago sem a Stripe confirmar nada. Não experimentei, mas no código
   não há nenhuma guarda. Devia só aceitar essa marca vinda do servidor ou do admin.
2. Com o cartão, a gorjeta à parte pode ser cobrada no pedido anterior do cliente, porque a app não atualiza o
   número do último pedido. Isto já acontece hoje, e a correção está num ficheiro de zona vermelha.
3. A gorjeta de um pedido entra no acerto pela data do pagamento, mas o estafeta só fica com ela na entrega. Um
   pedido pago no domingo à noite e entregue já depois do fecho de segunda perde a gorjeta. A proposta para contar
   pela data da entrega está em `pagamentos_acerto_por_entrega.md`; é dinheiro dos acertos, por isso decides tu.

## Próximo passo

A Claude.ai, pelo GitHub, copia as migrações e aplica as funções pela ordem do `pagamentos_LEIA-ME.md`. Corre a
prova em rollback e só depois liga o modo "junto" no painel. A app entra na publicação do fim de semana.

## Para a Claude.ai (técnico)

- Ramo `gorjetas-taxa-2026-10-30` (commits `fb7b524f` app/painel, `7208023a` servidor + propostas), a partir de
  `origin/autonomous-night-2026-04-29` 9330e66d. Enviado para o servidor (ramo próprio, não produção).
- Migrações a copiar para `supabase/migrations/` (a tranca recusou no PC):
  - `00_bloco0_migracao_20261030134938.md` (a tua de hoje, com definições completas);
  - `pagamentos_20261030145000_gorjeta_checkout_junto_pagamento.sql`;
  - `admin_listar_gorjetas.sql.md` (→ 20261030151000);
  - `extrato_prestador.sql.md` (→ 20261030150000).
  A `20261030144900_gorjeta_checkout_interruptor.sql` já está no repo.
- Ordem (`pagamentos_LEIA-ME.md`):
  1. 144900 → 145000 → 150000 → 151000.
  2. Edge Functions fora da zona vermelha: `charge-tip`, `cancel-order-with-choice`, `execute-cancellation`,
     `admin-cancel-order`, `auto-refund-order`, `payments-reconciler`, com `_shared/cobranca_stripe.ts` v3 e
     `_shared/gorjeta_devolver.ts`.
  3. Patches vermelhos: `create-payment-intent`, `create-mbway-payment-intent`, `stripe-webhook`, `client-cancel-order`.
  4. Prova `supabase/tests/gorjetas_taxa_prova.sql`.
  5. Só depois `tips_checkout_junto_pagamento = true`.
- Base das funções fora da zona vermelha, comparada com o ar a 30/10 (sem regressão):
  - `cancel-order-with-choice` v19, `execute-cancellation` v16, `admin-cancel-order` v15, `auto-refund-order` v4 e
    `payments-reconciler` v6: iguais a origin;
  - `charge-tip`: o ar é ainda a v1 de 04/10. O repo já tinha `secretKey()` de 16/10, nunca publicada, e entra
    junto com esta mudança.
- Atenção: `_shared/cobranca_stripe.ts` v3 também é usado por `stripe-webhook`, `finalize-order-from-intent` e
  `client-cancel-order`. Entra nelas na próxima publicação de cada uma. Sem gorjetas "junto", as contas ficam iguais.
- Fora da missão, a decidir: `create_order` com `payment_already_confirmed` vindo do cliente (e2e 5454);
  `lastCreatedOrderId` no cartão (e2e 5455); acerto da gorjeta por entrega (`pagamentos_acerto_por_entrega.md`);
  o diálogo do MB Way mostra o preço do carrinho, mas o MB Way cobra o valor reservado do pedido (já era assim).
- e2e_log fluxo `gorjetas-taxa-2026-10-30`: 5448, 5449, 5454, 5455, 5457–5461, 5463–5466.
