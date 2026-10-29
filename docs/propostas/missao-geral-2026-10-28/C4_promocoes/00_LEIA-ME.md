# Promoções com preço riscado — a regra de dinheiro, para confirmares (29/10/2026)

Isto é a parte do servidor que mexe no que o cliente paga. Está escrita mas **não aplicada**. O
interruptor das promoções nasce **desligado**; enquanto estiver desligado, nada muda para ninguém.

## A regra, em português simples

Quando uma promoção está ativa, o cliente paga o **preço promocional**. A comissão da Bora, o
markup escondido de 5 %, a taxa de serviço e a margem de 15 % das lojas que não são parceiras
calculam-se sobre o preço promocional, e não sobre o preço antigo. É o que a Glovo, a Uber Eats e
a iFood fazem: quem baixa o preço ganha menos, e a Bora também. Tu autorizaste isto a 29/10 às
18:02; fica escrito aqui para veres antes de ligar.

Como o servidor faz isto: nas duas funções do checkout (a que dá o preço ao cartão e ao ecrã de
pagamento, e a que grava o pedido), onde antes lia o preço do produto, passa a ler primeiro o
preço promocional, **só se** a promoção estiver válida naquele momento. Tudo o resto (comissão,
markup, taxas) já recebia o subtotal e continua igual; como o subtotal agora é o promocional, as
contas seguem sozinhas. Não se toca nas funções de comissão, de taxas nem do estafeta.

### Exemplo com as percentagens de hoje (arredondamentos podem variar um cêntimo)

Loja parceira, 1 unidade, o parceiro escreve o preço de balcão:

| | Sem promoção | Com promoção |
|---|---|---|
| Balcão (o que a loja recebe) | 8,00 € | 6,00 € |
| O cliente vê | 9,33 € | 7,00 € |
| Markup escondido (5 % do balcão) | 0,40 € | 0,30 € |
| Comissão visível da Bora (10 %) | 0,93 € | 0,70 € |
| Taxa de serviço ao cliente (5 %) | 0,47 € | 0,35 € |

Loja que não é parceira: produto de 4,00 € no catálogo, a app mostra 4,60 € (com os 15 %). Com
promoção a 3,00 €, a app mostra 3,45 €; a margem da Bora passa de 0,60 € para 0,45 €. A taxa fixa
de 2,50 € não muda.

## Consequências que convém saberes

1. A entrega grátis "a partir de X €" e a taxa de pedido pequeno olham para o subtotal já com a
   promoção. Um cliente pode deixar de ter entrega grátis, ou passar a pagar a taxa de pedido
   pequeno, por causa de uma promoção. É o comportamento normal dessas apps.
2. Os tokens que o cliente ganha (3 × o preço) contam sobre o que ele pagou, por isso ganha menos.
3. A loja parceira recebe sobre o preço promocional. O acerto semanal usa o subtotal do pedido, por
   isso acompanha sozinho.
4. Quem escolhe a promoção é o parceiro (ele escreve o balcão promocional e vê quanto o cliente
   paga) ou tu, no painel. O servidor recusa um preço promocional igual ou acima do normal.
5. Ficam de fora: produtos vendidos ao peso, e as marcas (variantes) de um produto. Num produto com
   opções (extras), só o preço base baixa; os extras pagam-se inteiros.
6. Promoções antigas que já estão na base sem datas (por exemplo 14 produtos do Lidl) **não ligam
   sozinhas**: só conta uma promoção com data de início. Se quiseres usar uma delas, dá-lhe datas
   no painel.

## Como a lei dos 30 dias fica cumprida (Diretiva Omnibus)

A app mostra o preço antigo riscado, o novo, e a linha "Preço mais baixo dos últimos 30 dias: X €".
O servidor guarda o histórico de preços de cada produto e calcula o preço mais baixo que esteve em
vigor nos 30 dias antes de a promoção começar. Se esse preço for mais baixo do que o preço normal,
é ele que aparece riscado. Se não houver descida real em relação a ele, a app mostra só o preço que
se paga, sem riscar nada.

## O que precisas de confirmar

1. A regra acima (comissão, markup e taxas sobre o preço promocional): sim ou não.
2. Que promoções antigas sem datas ficam desligadas até lhes dares datas: sim ou não.
3. Que produtos ao peso e marcas ficam fora desta primeira versão: sim ou não.

## Ordem para aplicar (quem aplica é a Claude.ai, com o teu "vai")

1. Aplicar a migração `supabase/migrations/20261029200800_c4_promocoes.sql` (não mexe em valores).
2. Correr a PARTE P de `01_servidor_precos_proposta.sql`: é uma prova que termina sempre com um
   erro de propósito e desfaz tudo; o relatório vem no texto do erro (um pedido de teste com e sem
   promoção, linha a linha, e 12 produtos sem promoção a dar o mesmo que a função antiga). Não pode
   haver nenhuma linha "FALHOU".
3. Correr a PARTE A: guarda a cópia das duas funções (`bkp_fn_quote_order_pricing_20261029` e
   `bkp_fn_create_order_20261029`) e faz a troca. Se não encontrar exatamente os 2 sítios em cada
   função, pára sem mudar nada.
4. Conferir `select public.promotions_status();` → `server_ready = true`, `enabled = false`.
5. Só então ligar o interruptor no painel (menu Sistema, Promoções). Antes disso a app nunca mostra
   preço riscado, mesmo que o interruptor esteja ligado: o painel avisa se o servidor ainda não
   aplica a promoção.

Para desligar de emergência: o interruptor no painel (efeito imediato, a app e o servidor voltam ao
preço normal). Para repor as funções antigas: o fim do ficheiro SQL tem os comandos.

## O que não foi provado

Esta proposta foi escrita sem acesso à base (curl bloqueado, sem MCP). A prova da parte P ainda não
foi corrida. Os dois pontos a ver no resultado: o tipo das colunas `price` e `discount_price` (a
prova pára se forem diferentes) e a primeira encomenda real com promoção (conferir
`orders.subtotal`).
