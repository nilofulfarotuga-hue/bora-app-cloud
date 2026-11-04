# Proposta — check-in: desconto nos mercados e prémios em lojas não parceiras (04/11/2026)

Missão `checkin-escada-premios-2026-11-04`, blocos A e B. Autorização do Danilo: 04/11 09:58, "Vai, pode fazer."
Nada disto está aplicado. Mexe no dinheiro do pedido (orçamento, criação do pedido, fecho da compra e acerto
do estafeta), que é zona protegida e a tranca do Bora bloqueia. Precisa de uma sessão com licença para essa zona.

## O que já está no ar (sem mexer em dinheiro)

- Tipo de prémio `desconto` no servidor: tabela `checkin_premios_vales` aceita `tipo = 'desconto'` e tem a
  coluna nova `minimo_cents`; `_checkin_marcos_config`, `_checkin_escada_degraus`, `_checkin_vale_emitir` e
  `_checkin_vale_json` tratam o desconto (migração `20261104114014`).
- Os 6 degraus de desconto existem em `platform_settings` mas estão **desligados** (`"ativo": false`):
  dia 9 Mercadona Beleza 3 € (mín. 15 €), dia 10 Continente 3 € (mín. 25 €), dia 15 Mercadona 5 € (mín. 30 €),
  dia 16 Continente 5 € (mín. 40 €), dia 22 Continente 7 € (mín. 55 €), dia 25 Continente 10 € (mín. 70 €).
- Os 5 degraus de lojas não parceiras (Leonidas barra e 4 bombons, Burger King Double e Whopper, Big Mac,
  Tiago's, Fuku) continuam **desligados**.

## A — desconto no pagamento (falta)

1. `quote_order_pricing(p_input)`: aceitar `checkin_vale_id`. Validar no servidor: o vale é do cliente,
   `tipo = 'desconto'`, `estado = 'por_usar'` e dentro da validade, a loja do vale é a loja do pedido, e o
   subtotal **só de produtos** (sem entrega, taxas, saco, gorjeta) é `>= minimo_cents`. Se valer:
   `desconto = valor_cents / 100`, devolver `checkin_desconto` e tirar o desconto de `customer_total` e
   `charge_total`. Se não valer, devolver o motivo (falta X € para o mínimo) e não descontar.
2. `create_order`: a mesma validação (nunca confiar no ecrã) e gravar o desconto no pedido.
3. Quem paga: **a margem da Bora** (`platform_commission` desce o valor do desconto). `driver_earnings` não
   muda. Nas lojas não parceiras a loja continua a receber o preço da app (regra de 25/10, sem margem).
4. Gastar o vale: no gatilho que já marca os prémios-produto como usados (`_checkin_premio_no_pedido`), marcar o
   vale de desconto como `usado` com o `pedido_id`; se o pedido for cancelado, o gatilho de cancelamento já
   devolve o vale.
5. App: no carrinho, "Usar prémio: 3 € de desconto" quando há vale da loja; linha verde com o desconto
   (valor vindo do orçamento do servidor); "Falta X € para usares o desconto" abaixo do mínimo.
6. Provar em transação desfeita: 1 caixa abaixo do mínimo (sem desconto), compra acima do mínimo
   (desconto certo, comissão menos 3 €, estafeta igual), vale gasto uma vez só. Pagamento de teste em dinheiro.
7. Só depois: ligar os 6 degraus.

## B — prémio-produto em loja não parceira (falta)

O que existe hoje: numa loja **parceira** o prémio sai a 0 € e a Bora paga depois à loja o `custo_cents`
(`admin_checkin_premios_pagar_loja`, ecrã "A pagar às lojas"). Numa loja **não parceira** o estafeta paga o
produto ao balcão. Não há caminho que lhe devolva esse valor quando o produto vai a 0 € para o cliente, e o
fecho da compra pelo talão recalcula o pedido pelo valor real — pode cobrar o prémio ao cliente.

Proposta:
1. No pedido, marcar a linha do prémio (produto `premio-checkin-*`) como "prémio pago pela Bora".
2. No ecrã do estafeta: "Prémio do check-in: compra no balcão, a Bora paga-te este valor" junto à linha.
3. No fecho da compra (talão): o valor do talão para essa linha **não** entra no total do cliente; entra como
   custo do prémio da Bora (`checkin_premios_vales.custo_cents` = valor real do talão) e é devolvido ao
   estafeta no acerto semanal, sem mexer no ganho dele.
4. Provar com um pedido de teste na conta demo, pagamento em dinheiro, estafeta demo (o gatilho demo põe o
   pedido no estafeta demo e não oferece a estafetas reais).
5. Só depois: ligar os 5 degraus.
