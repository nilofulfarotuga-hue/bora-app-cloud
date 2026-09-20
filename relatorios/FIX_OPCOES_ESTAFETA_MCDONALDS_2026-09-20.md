# Correcao das opcoes do pedido no estafeta

Foi corrigido o pedido McDonald's `9cba3644-5733-4fe4-9898-d24b896ff3f9`.

A causa era a copia criada em `lib/screens/driver_map_screen.dart`, dentro de `_showShoppingListSheet`. O pedido ja chegava ao `OrderModel` com `selected_options` e `selected_options_priced`, mas a copia nova guardava apenas id, nome, preco, quantidade, estado e preco real. Por isso a lista de compras recebia `displayOptions` vazio.

A copia agora preserva todas as informacoes, incluindo `selected_options`, `selected_options_priced` e `basePrice`. A apresentacao foi extraida para `lib/widgets/driver_item_options.dart`. O estafeta ve uma linha por grupo: tamanho, bebida, acompanhamento, complemento, molho, ketchup e remocoes. `displayOptions` continua a preferir `selected_options_priced`, sem duplicar as escolhas. Pedidos antigos sem opcoes continuam a funcionar.

Foi procurado o resto do fluxo do estafeta. A unica tela que renderiza os itens e a lista de compras em `driver_map_screen.dart`, aberta pelo botao `Ver compras`. Os cards de oferta e o overlay nao mostram itens.

Provas executadas:

- `flutter test test/driver_item_options_test.dart --reporter expanded`: 6 testes passaram.
- `flutter test test/golden/estafeta_lista_compras_test.dart --reporter expanded`: 3 testes visuais passaram, sem overflow, nas larguras 320, 390 e 430.
- Suite relacionada: 37 testes passaram, incluindo `weight_portions_test.dart`, `order_lifecycle_contract_test.dart`, `order_eta_phases_test.dart`, `taxa_servico_nao_parceiro_test.dart`, `loja_fechada_test.dart` e `quote_leva_product_lines_test.dart`.
- `flutter analyze` dos ficheiros alterados: sem erros novos. Restam quatro avisos preexistentes em `driver_map_screen.dart`, fora das linhas alteradas.
- `git diff --check`: sem erros.

Nao houve alteracao na base de dados, em `orders`, pricing, dispatch, pagamentos, Stripe, wallet, ledger ou finalizePurchase.
