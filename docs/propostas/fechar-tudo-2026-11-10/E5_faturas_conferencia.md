# E5 — Faturas da Bora por emitir: conferência com o fecho de outubro

Missão fechar-tudo-2026-11-10, bloco E5. Conferido a 10/11/2026 por SELECT na base de produção
(só leitura). **Nada foi emitido nem enviado.** Sem NIFs nem nomes de clientes (o repositório é
público); os pedidos aparecem só pelos 8 primeiros caracteres do id.

## 1. O que está na lista `bora_invoices_pending`

| Mês | Linhas por lançar | Valor | Linhas sem valor | Com NIF do cliente | Com número de documento |
|---|---|---|---|---|---|
| outubro (02/10 a 31/10) | 19 | 33,71 € | 2 | 1 | 0 |
| novembro (02/11 a 09/11) | 18 | 119,14 € | 0 | 7 | 0 |
| **Total** | **37** | **152,85 €** | 2 | 8 | 0 |

Nenhuma linha tem número de fatura: até hoje não foi emitida nenhuma fatura da Bora.

Nas linhas de outubro há 18 pedidos entregues (31,21 €) e uma taxa de cancelamento de 2,50 € (pedido
`bd26d6e0`, 13/10). As 2 linhas sem valor são os 2 pedidos de outubro que deram prejuízo.

## 2. Conferência com o fecho de outubro (`admin_monthly_closeout(2026,10)`)

O fecho de outubro diz (entidade: nome individual, IVA isento pelo art. 53.º do CIVA):

- 20 pedidos entregues; os clientes pagaram 368,92 €; mercadoria 239,36 €; estafetas 103,64 €.
- **Receita própria da Bora nas entregas: 129,56 €** (entrega 76,94; taxa de serviço 12,44; sacos
  2,90; pedido pequeno 5,56; parte nos parceiros 3,59; margem nos não parceiros 31,42; tokens −3,29).
- **Mais 29,61 € de taxa da Bora nas limpezas** (5 serviços).
- **Total a declarar: 159,17 €**, e o texto do fecho diz que "a parte da Bora (159,17 € no total)
  fatura-se aos clientes".
- Lucro (pago − mercadoria − estafetas): 25,92 €.

A lista de faturas de outubro usa outra base: **o lucro de cada pedido** (pago − mercadoria −
estafeta, nunca negativo). Daí os números não baterem:

| | Valor |
|---|---|
| Lista de outubro, pedidos entregues (só os positivos) | 31,21 € |
| menos os 2 pedidos no prejuízo (`48669acf` −2,69 e `b4338364` −1,87) | −4,56 € |
| = lucro dos pedidos pela lista | 26,65 € |
| Lucro do fecho | 25,92 € |
| **Diferença** | **0,73 €** |

A diferença de 0,73 € é um pedido só: `f293752c` (28/10). A linha foi gravada na entrega com
1,60 €; depois entrou o talão e o lucro desse pedido passou a 0,87 €. A linha não se atualizou
(o valor só se calcula quando o pedido passa a entregue).

Em resumo, para outubro há três números possíveis e só o contabilista pode dizer qual se fatura:

1. **33,71 €** — o que está na lista (lucro por pedido + a taxa de cancelamento), com 1 linha
   desatualizada (deveria dar 32,98 €);
2. **129,56 € + 2,50 €** — a receita da Bora nas entregas (o que o cliente pagou à Bora: entrega,
   taxas, margem), mais a taxa de cancelamento;
3. **159,17 € + 2,50 €** — o total a declarar do fecho, com as limpezas (que hoje NÃO têm nenhuma
   linha na lista de faturas).

## 3. Novembro (só para saber, o mês ainda não fechou)

Desde 01/11 a lista já usa a receita da Bora por pedido ("Serviço da plataforma Bora —
intermediação, taxa de serviço e entrega", IVA 23% incluído), que é a base do ponto 2.

- 18 pedidos de 01/11 a 09/11: receita da Bora hoje = 109,00 €; a lista tem 119,14 €.
- **Diferença −10,14 €** em 4 linhas que ficaram com o valor da hora da entrega e depois mudaram
  (cerca de 2,50 € cada): `9124cfa5` (5,86 → 3,23), `c1e9495f` (8,42 → 5,91), `c53b29ef`
  (6,18 → 3,68), `d573633b` (7,41 → 4,91).
- As limpezas de novembro também não entram na lista.

## 4. O que já está feito na app (sem emitir nada)

- O email ao cliente (`recibo-pedido-cliente`) passa a ter o título "Resumo do pedido — este
  documento não serve de fatura", diz o mesmo no corpo e no rodapé, e identifica a sociedade
  (Danilo Fulfaro da Silva - Unipessoal Lda, NIPC, sede) e o Livro de Reclamações. Falta publicar
  a função (deploy da Edge Function).
- No painel, "Fecho do mês" → "Faturas da Bora por pedido": o CSV para Excel já existia (data,
  pedido, cliente, NIF, valor, base, IVA 23%, regime, estado; sem as linhas sem valor); entrou o
  botão **PDF** com as mesmas linhas, para mandar ao contabilista.

## 5. O que falta decidir com o Hugo

1. **Base da fatura de outubro**: lucro por pedido (33,71 €), receita da Bora (129,56 € + 2,50 €)
   ou total a declarar com limpezas (159,17 € + 2,50 €)? A lista e o texto do fecho dizem coisas
   diferentes; a lista de novembro já está na receita.
2. **Limpezas**: as taxas da Bora nas limpezas (29,61 € em outubro, 5 serviços) também levam
   fatura ao cliente? Hoje não estão na lista.
3. **Taxa de cancelamento** (2,50 €, 13/10): fatura-se como serviço da Bora?
4. **Valores que mudaram depois da entrega** (1 linha em outubro, 4 em novembro): emite-se pelo
   valor de hoje? Proposta: recalcular as linhas ainda "por lançar" antes de emitir (mexe em
   dinheiro/fiscal — só com "autorizo" do Danilo).
5. **Quem emite e com que programa**: o escritório emite as 37 (ou mais) faturas de 02/10 a 09/11
   à mão, ou liga-se já um programa de faturação certificado à app (uma fatura por pedido)?
   Os 8 pedidos com NIF do cliente precisam de fatura com esse NIF.
6. **Outubro foi em nome individual** (isento, art. 53.º) e novembro já é a sociedade (IVA 23%):
   confirmar que as faturas de outubro saem no NIF pessoal e as de novembro no NIPC da sociedade,
   e o prazo legal para as que já estão atrasadas (CIVA art. 36.º: 5 dias úteis).

Fonte dos números: `bora_invoices_pending`, `public._fecho_pedidos` e `admin_monthly_closeout(2026,10)`,
lidos a 10/11/2026 (Lisboa).
