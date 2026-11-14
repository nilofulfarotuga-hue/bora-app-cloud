# Bloco 1.6 — números (Farmácia da Sé, cesto a 2 km)

Calculados a 14/11/2026 com as funções da proposta (bloco1-proposta-dinheiro.md) criadas como temporárias
contra as definições reais de produção (nada mudou no servidor). e2e_log 8747/8748.

Definições usadas: taxa de serviço 0,99 € + 5 %; entrega 2,50 € até 4 km; pedido pequeno 1,39 € abaixo de 15 €;
estafeta 3,80 € + 0,20 €/km; Stripe 1,5 % + 0,25 € (cartão e MB Way); dinheiro sem Stripe. Sem saco.

| Cesto | Cliente paga | Farmácia recebe (3 meses) | Farmácia depois | Estafeta | Bora (3 meses) | Bora 3 meses, cartão | Bora depois | Bora depois, cartão |
|---|---|---|---|---|---|---|---|---|
| 8 € | 13,28 (serviço 1,39 + entrega 2,50 + pequeno 1,39) | 8,00 | 7,20 | 4,20 | 1,08 | 0,63 | 1,88 | 1,43 |
| 15 € | 19,24 (serviço 1,74 + entrega 2,50) | 15,00 | 13,50 | 4,20 | 0,04 | −0,50 | 1,54 | 1,00 |
| 25 € | 29,74 (serviço 2,24 + entrega 2,50) | 25,00 | 22,50 | 4,20 | 0,54 | −0,16 | 3,04 | 2,34 |
| 40 € | 45,49 (serviço 2,99 + entrega 2,50) | 40,00 | 36,00 | 4,20 | 1,29 | 0,36 | 5,29 | 4,36 |

Antes da mudança (como estava): o cliente pagava 11,00 / 18,35 / 28,85 / 44,60 € e a farmácia recebia só
6,86 / 12,86 / 21,43 / 34,29 € (a Bora tirava 10 % + 5 % escondidos ao preço da Glovo).

Em dinheiro: o estafeta paga à farmácia o subtotal na recolha (8 / 15 / 25 / 40 €); nos 3 primeiros meses o fecho
semanal dá 0; depois a farmácia fica a dever 0,80 / 1,50 / 2,50 / 4,00 € por pedido, que entram no fecho.

Ponto de atenção para o Danilo: entre 15 € e cerca de 30 € pago com cartão, nos 3 primeiros meses a Bora perde
dinheiro por pedido (a 15 € perde 0,50 €; a 25 € perde 0,16 €), porque a taxa de pedido pequeno deixa de entrar aos
15 € e a taxa de serviço + entrega quase só pagam o estafeta. Não mexi em nada disto: é a regra combinada.
