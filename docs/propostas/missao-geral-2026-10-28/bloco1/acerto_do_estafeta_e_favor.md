# Bloco 1 — o que ficou para o Claude.ai (DINHEIRO)

Missão `missao-geral-2026-10-28`, 29/10/2026. Encontrado pelo agente do C3 e confirmado pelo líder
por SELECT. Nada foi aplicado.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo descrito — confirma que se aplica.

## 1. O acerto do estafeta conta o dinheiro bruto (o mais grave)

Num pedido a dinheiro, o que o estafeta deve à Bora é calculado pelo total do pedido, sem tirar o
que o cliente já pagou com saldo, tokens e crédito de menu.

- `post_order_to_ledger`, linhas 22 e 38: `v_total := COALESCE(final_total, price)` e
  `v_cash_adj := -ROUND(v_total - v_driver_earn - v_reimb, 2)`.
- `apply_driver_cash_settlement`, linhas 25 e 29: a mesma conta ("FUROS DO EURO 2026-08-16:
  fórmula alinhada"), por isso as duas têm de mudar JUNTAS.

Prova com o pedido Auchan de 28/10 (total 14,35 €, saldo 10,31 €, tokens 0,73 €, ganho 4,87 €,
talão 7,88 €): ficou `cash_adjustment = -1,60` = −(14,35 − 4,87 − 7,88). Com o dinheiro que o
estafeta recebeu de facto (3,31 €) seria −(3,31 − 4,87 − 7,88) = +9,44. Diferença: 11,04 € contra o
estafeta. (Este pedido já foi acertado em mão; os 6 antigos estão em
`Desktop\Bora\prompts\missao-geral-2026-10-28-C6-pedidos-antigos.md`, fora do repo.)

Correção proposta: nas duas funções, o dinheiro que o estafeta tem na mão passa a ser
`COALESCE(cash_total_due, GREATEST(0, COALESCE(final_total, price) − (wallet_applied_cents +
tokens_applied_value_cents + menu_credit_applied_cents) / 100.0)) + debt_collected_cents / 100.0`
(a dívida antiga também é recebida pelo estafeta em dinheiro e entregue à Bora; confirmar com o
`compute_driver_settlement` antes). Backup `bkp_fn_<nome>_20261028` de cada uma, prova em rollback
com um pedido de teste a dinheiro com saldo/tokens, e verificar que os pedidos sem saldo/tokens dão
exatamente o mesmo número que hoje.

## 2. A folha do Favor manda cobrar o bruto (ficheiro protegido)

`lib/widgets/errand_execution_sheet.dart`, ≈ linha 385 (zona vermelha `_finalizePurchase`): o
"Cobrar ao cliente" usa `o.finalTotal ?? o.total`, sem descontar saldo/tokens nem somar a dívida.
Contradiz o cartão do Favor, que já está certo (commit 60c4cbf4). Correção: usar
`o.totalToCollectCash` (o getter do modelo, que já vem do servidor). No troco do dinheiro de casa,
descontar também o que já foi pago.

## 3. Acerto do parceiro

- Entregas normais: a loja recebe a parte inteira pelo acerto semanal
  (`post_order_to_ledger` linha 61 `partner_store_share(subtotal)`; `compute_partner_weekly_settlement`
  linhas 37 e 54 só descontam dinheiro em take-away levantado e em "parceiro chama estafeta"). Logo, o
  texto da faixa do estafeta "RECEBER X — entregar ao parceiro" contradiz o acerto: se o estafeta
  entregar o dinheiro à loja, a loja recebe duas vezes. Confirmar com o Danilo em que pedidos o
  estafeta entrega mesmo dinheiro à loja, e alinhar o texto ou o acerto.
- Take-away pago em dinheiro com saldo/tokens: o acerto desconta o total bruto, por isso a loja NÃO
  recebe a diferença paga com saldo/tokens. Correção: descontar o `cash_total_due`, não o bruto.

## 4. No painel admin

O cartão "Cash entregue" (admin_order_detail_screen.dart ≈ 753) usa o `cash_total_due`; o registo de
movimentos usa o bruto. Os dois números não batem nos pedidos com saldo/tokens até o ponto 1 estar
aplicado.
