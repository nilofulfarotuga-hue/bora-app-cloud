# Farmácia Rego — prova de dinheiro (Bloco 1.7), 23/11/2026

Tudo medido por SQL no servidor (projeto ojykpzwqrtusfeakzrna), em leitura ou em transação
desfeita. Nada foi cobrado e a loja continua escondida (`so_lista_permissao = true`).

Carrinho de teste: **1 produto de 10,00 € de balcão**, que na app aparece a **11,50 €**
(balcão × 1,15). Estafeta a 2 km.

## A. Como a Rego ficaria HOJE (sem mexer no preço)

A Rego é `category = 'pharmacy'` e parceira, por isso apanha o "ramo farmácia" do
`pricing_calculate_loja` (feito a 14/11 para a Sé, onde o preço é o da Glovo e a farmácia
recebe tudo) e o ramo farmácia do `partner_store_share`.

| Linha | Valor |
|---|---|
| Produto (o cliente vê) | 11,50 € |
| Taxa de serviço das farmácias (0,99 € + 5 %) | 1,57 € |
| Entrega | 2,50 € |
| Taxa de pedido pequeno (abaixo de 15 €) | 1,39 € |
| **Cliente paga** | **16,96 €** |
| Rego recebe (`partner_store_share`) | **11,50 €** — errado para o modelo: devia ser 10,00 € |
| Estafeta | 4,20 € (3,80 + 0,20 × 2 km) |
| Bora fica | 16,96 − 11,50 − 4,20 = **1,26 €** |

Conclusão: **hoje a Rego NÃO está no modelo combinado** (cobra a taxa de serviço das farmácias,
que a missão proíbe, e paga os 15 % à farmácia em vez de os deixar à Bora). Como a loja está
escondida e os pedidos nas lojas escondidas viram pedidos de teste sem cobrança, nenhum
dinheiro real corre com isto. Tem de ser corrigido antes de a loja abrir.

## B. O modelo da missão, aplicado à letra

Missão: "preço = balcão × 1,15; a Rego recebe sempre o balcão; a Bora fica com os 15 %; sem
comissão extra; as mesmas taxas de entrega e de pedido pequeno que a A3 cobra; NÃO aplicar a
taxa de serviço das farmácias".

Medido na A3 com o mesmo cesto de 11,50 € (`pricing_calculate_loja(...,'a3-guarda')` e
`small_order_fee_calc(...,'a3-guarda')`):
entrega 2,50 €, taxa de serviço 5 % = 0,58 €, saco 0,30 €, **taxa de pedido pequeno = 0 €**
(as lojas parceiras que não são farmácia não levam esta taxa, regra de 22/09), comissão 10 %
+ 5 % oculto, a A3 recebe 9,86 €.

**Atenção — a missão descreve a A3 de forma diferente do que a A3 é no servidor:** a A3
cobra 5 % de taxa de serviço e não cobra taxa de pedido pequeno. Por isso há três leituras
possíveis, com o mesmo carrinho de 10,00 € de balcão:

| | B1 — só entrega (à letra) | B2 — entrega + pedido pequeno das farmácias | B3 — igual à A3 (entrega + 5 % serviço + saco) |
|---|---|---|---|
| Produto | 11,50 | 11,50 | 11,50 |
| Taxa de serviço | 0 | 0 | 0,58 |
| Saco | 0 | 0 | 0,30 |
| Entrega | 2,50 | 2,50 | 2,50 |
| Pedido pequeno | 0 | 1,39 | 0 |
| **Cliente paga** | **14,00** | **15,39** | **14,88** |
| Rego recebe | 10,00 | 10,00 | 10,00 |
| Estafeta | 4,20 | 4,20 | 4,20 |
| **Bora fica** | **−0,20** | **1,19** | **0,68** (saco 0,30 incluído) |

A B1 dá **prejuízo de 0,20 €** num pedido de 10 € a 2 km: os 15 % (1,50 €) + a entrega
(2,50 €) não chegam para os 4,20 € do estafeta. A partir de ~11,35 € de balcão deixa de dar
prejuízo.

## C. Pedido de receita (igual à Sé, sem os 15 %)

Não depende da loja: usa `pricing_calculate_errand('normal', ...)`, o mesmo da Sé. Medido:

- Receita com 10,00 € de medicamentos, 2 km: cliente paga **16,00 €** (10,00 € de
  medicamentos + 6,00 € de taxa do Favor). A Rego recebe **10,00 €** (o estafeta paga ao
  balcão). Estafeta **5,00 €**. Bora **1,00 €**.
- A 6 km: taxa 7,00 € (6,00 + 2 km extra × 0,50), estafeta 6,00 €, Bora 1,00 €, cliente 17,00 €.
- Não há 15 % nos medicamentos com receita nem comissão extra (a Rego tem
  `partner_extra_commission_pct = NULL`).

## D. O que falta e quem decide

1. Escolher B1, B2 ou B3 (decisão de dinheiro, é do Danilo).
2. Aplicar a exceção `PROPOSTA-preco-farmacia-com-markup.sql` (nesta pasta) com a escolha,
   e correr a prova por hash que ela traz (as outras lojas ficam iguais ao cêntimo).

Frase exata para o Danilo autorizar (exemplo com a B2):
"AUTORIZO 23/11: na Farmácia Rego o cliente paga o balcão + 15 % no preço do produto, a
entrega normal e a taxa de pedido pequeno das farmácias (1,39 € abaixo de 15 €), sem a taxa
de serviço das farmácias; a Rego recebe o balcão; sem comissão extra."
