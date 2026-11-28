# Relatório — missão balcao-real-2026-11-28

> Claude Code na nuvem, 28/11/2026, ramo `ai/2026-11-28-balcao-real`. Motor: Opus 5.5.
> Não corri SQL no Supabase. O SQL está em `docs/missoes/balcao-real-2026-11-28-sql.md`.

## O que ficou feito

**B1, app do estafeta.** O item do pedido passa a ler e guardar o `balcaoReal` que o servidor carimba
(`lib/models/cart_item.dart`). A cópia da lista de compras do estafeta (`lib/widgets/driver_item_options.dart`)
e o `toJson` guardam-no, para o estafeta não o apagar ao gravar as compras. O preço de balcão
(`lib/services/preco_balcao.dart`) passa a ser `balcaoReal` + opções quando existe e a loja não é
parceira; senão fica exatamente como hoje. Isto chega sozinho ao cartão laranja, à lista "Ver compras",
ao total, ao "Valor estimado" do talão e ao "Pagar ao balcão" da lista de pedidos, porque todos usam a
mesma fonte. Produto ao quilo fica como hoje (explico abaixo). Não mexi em `PricingService`, carrinho,
checkout, `cash_total_due`, reembolso, ganhos, `finalizePurchase` nem `dispatch_engine`. Confirmei que
a função de fecho da compra (`finalize_storeshopping_purchase`) só lê o id e o estado de cada item, por
isso a chave a mais não muda nada no dinheiro.

**B2, painel admin (PT-BR).** Na aba Correções, o estado novo `estafeta` tem filtro próprio ("Só para o
estafeta"), aparece escrito "Corrigido só para o estafeta (o cliente continua a pagar o mesmo)" e tem o
botão Reverter. Aprovar uma proposta mais barata mostra a resposta `so_estafeta` com o valor do balcão.
O diálogo de preços que existia (`admin_product_prices_dialog.dart`) é só de lojas parceiras, onde o
balcão real não existe; por isso pus no mesmo ficheiro um diálogo próprio "Balcão real", aberto por um
botão novo (ícone de talão) no catálogo das lojas não-parceiras (`admin_catalog_screen.dart`). Mostra o
preço de balcão real do último talão com a data, deixa pôr ou tirar à mão pela RPC
`admin_preco_balcao_real` e diz em português o erro `balcao_real_tem_de_ser_menor_que_o_preco`. O detalhe
do pedido no painel não mostra valor ao balcão, por isso não precisou de mudança.

**B3, auditoria.** Varri todas as migrações: nove funções leem `basePrice`. Só uma é de ecrã e ainda não
estava feita: `encomenda_telefone_resumo` (o aviso "LIGAR À LOJA"). O SQL proposto está no ficheiro de
SQL, bloco 2. As de dinheiro ficam como estão: `partner_chamar_estafeta`, `_order_edit_build`,
`estafeta_ajustar_peso`, `_talao_casar_itens` e `_trg_alerta_preco_catalogo_fn` (este é um aviso, mas
mede se o preço do cliente cobre o talão, e com o balcão real dava alarmes falsos). `demo_boom_criar_pedido`
só cria pedidos de demonstração.

**B4, talão de combos do KFC.** Regra proposta e provada: pedido de um só menu que o robô não casou →
total do talão menos sacos e depósitos = esse menu, com as guardas 0,4× a 2,5×. Confiança alta só
quando a loja, o total impresso, a soma das linhas e o valor escrito pelo estafeta batem. Mais barato e
com certeza → só o balcão do estafeta. Mais caro ou com dúvida → proposta no painel. Nunca muda o preço
do cliente sozinho. No caso do KFC dá balcão real de 10,41 € no Box Meal Mix: o estafeta passava a ver
12,85 € (com a maçaroca) em vez de 15,67 €. Provado num Postgres descartável: 8 casos de teste verdes e
o robô inteiro a correr de ponta a ponta. SQL nos blocos 3 a 5 do ficheiro de SQL, com uma prova no
talão real em transação desfeita antes de aplicar.

## Provas

- `flutter test test/preco_balcao_real_2026_11_28_test.dart`: 10 testes verdes (com balcão real 13,60 €
  em vez de 15,67 €; sem balcão real igual a hoje; parceiro igual a hoje; quantidade 2; zero ignorado;
  produto ao quilo ignorado; `toJson` e cópia da lista guardam o valor; textos do painel).
- Os testes antigos do preço de balcão (`preco_balcao_b6b`, `pagar_na_loja`, `fechar_app_bloco2_3a`,
  `driver_item_options`) continuam verdes.
- RESULTADO_TESTES_COMPLETOS
- Juiz anti-trapaça: limpo (nenhum teste apagado, enfraquecido ou saltado).
- Rubrica de ecrã: o ecrã do estafeta não muda de aspeto, só o número. No painel, um filtro, um texto
  verde e um botão a mais na aba Correções, e um ícone a mais em cada produto das lojas não-parceiras,
  tudo em PT-BR com os termos técnicos explicados entre parênteses. Não houve captura de ecrã: o
  diálogo lê o produto do Supabase ao abrir e esta sessão não tem acesso ao servidor.

## Publicação

PUBLICACAO

## O que fica para a Claude.ai aplicar no servidor

O ficheiro `docs/missoes/balcao-real-2026-11-28-sql.md`, pela ordem que lá está: guardas do carimbo,
resumo do telefone e o menu único do KFC (com a prova no talão real antes).

## Outros erros encontrados pelo caminho (reportados, não corrigidos)

1. O carimbo do balcão real deixava passar um `balcaoReal` que já viesse no pedido e carimbava produtos
   ao quilo. É só ecrã: a correção está no bloco 1 do ficheiro de SQL.
2. Produtos ao quilo: o talão deles muda com o peso, e a folha da balança valida ±30 % sobre o
   "Previsto" do ecrã, enquanto o servidor valida sobre o `basePrice`. Por isso a app ignora o balcão
   real nesses produtos, para os dois continuarem a bater.
3. ⚠️ ISTO MEXE EM DINHEIRO. O robô do talão não exclui os produtos ao quilo: um talão mais pesado do que
   o previsto pode subir sozinho o preço do cliente (até +50 %). A guarda está descrita no ficheiro de
   SQL, secção 6; não a escrevi como migração porque precisa do "autorizo" do Danilo.
4. ⚠️ ISTO MEXE EM DINHEIRO. O talão do KFC trazia "DEPOSITO 0,75" e a app cobrou 0,10 € de depósito
   Volta pela lata. Só relatório.
5. O `flutter analyze` já tinha um aviso antigo no catálogo do painel (`admin_catalog_screen.dart:56`,
   chavetas num `if`). Não é desta missão; ficou como estava.
6. Correr os testes inteiros regrava fotos de prova (`.claude/.ai/provas/...`, `test/golden/_fotos/...`)
   e o `flutter pub get` regrava 3 ficheiros gerados de macOS/Windows. Não foram para o commit.

## Registo por bloco (e2e_log, fluxo balcao-real-2026-11-28)

Não escrevi no `e2e_log` (esta sessão não corre SQL no Supabase). Passos para a Claude.ai registar:
B1 feito (app do estafeta, 10 testes) · B2 feito (painel) · B3 feito (auditoria; SQL no bloco 2) ·
B4 feito (SQL e provas nos blocos 3 a 5, por aplicar) · B5 PASSO_B5 · B6 feito (este relatório).
Digest no livro: não tenho acesso ao livro nesta sessão; este relatório serve de digest.
