# Bloco 2 — o que falta dentro do `order_store.dart` (proposta pronta a aplicar)

Missão `fechar-app-15-11`, 14/11/2026. Ordem do Danilo na missão (caixa_guardados id 13): "ESTAFETA
LENTO, O QUE FICOU DENTRO DO order_store.dart (zona vermelha, autorizado aqui pelo Danilo só para isto)".

## Porque é uma proposta e não está aplicado

A bora-tranca negou a edição de `lib/stores/order_store.dart` ("zona vermelha: order_store.dart
(finalizePurchase)") à primeira tentativa, às 22:24 de 14/11. Não se repetiu nem se contornou. É a mesma
recusa de 11/11 e de 14/11 19:15 (`docs/TRANCAS.md`).

## O que a proposta faz (e o que não toca)

Ficheiro `bloco2_order_store.patch`, ao lado deste. Mexe em dois ficheiros:

1. `lib/stores/order_store.dart` — só o `loadOrders` e duas funções novas ao lado dele:
   - **Um só carregamento em voo.** Quem chamar `loadOrders` enquanto um corre junta-se a um único
     carregamento seguinte (`CarregamentoUnico`, já no ramo em `lib/services/carregamento_unico.dart`).
   - **Estafeta: 2 s entre carregamentos** (`esperaEntreCarregamentosEstafeta`). Cliente, loja e painel
     não esperam nada.
   - **Estafeta: lista filtrada.** Em vez de `GET orders` sem filtro (64 pedidos, ~330 kB em 14/11),
     dois pedidos pequenos: os vivos dele (`assigned_driver_id` ou `current_driver_offer_id` = o
     `user_id`, estado diferente de entregue/cancelado/rejeitado) e as últimas 20 entregas.
   - **Histórico às páginas** (`carregarMaisHistoricoEstafeta`, 20 de cada vez).
   - A lista do estafeta deixa de ser apagada a cada carregamento: junta-se por id ao que os canais
     ao vivo já lá puseram, e tira só o que deixou de ser dele.
2. `lib/screens/driver_main_screen.dart` — três linhas que ligam o botão "Ver entregas mais antigas"
   (já no ramo, a funcionar com o que está na memória) às páginas do servidor.

Não toca em `finalizePurchase`, criação de pedido, pagamentos, preços, tokens, contas nem nos canais
ao vivo. Sessão que não seja só de estafeta (cliente, loja, painel) segue exatamente o caminho antigo.

## Como aplicar (Claude.ai ou sessão com a tranca aberta)

```
git apply --check docs/propostas/fechar-app-15-11/bloco2_order_store.patch
git apply docs/propostas/fechar-app-15-11/bloco2_order_store.patch
```

O `--check` passou neste ramo a 14/11 22:45 (commit a seguir ao que traz este ficheiro).
Depois: `flutter analyze` e `flutter test test/fechar_app_bloco2_3a_test.dart test/fila_estafeta_test.dart`.

## Provas que já existem

`test/fechar_app_bloco2_3a_test.dart`: a regra de juntar chamadas (rajada de 10 dá 2 carregamentos,
não 10; quem chama a meio recebe dados pedidos depois; um erro não prende o seguinte; 2 s para o
estafeta com relógio falso; sem espera para os outros), o texto do filtro e as páginas de 20, e o
ecrã do histórico (20, 40, 45; botão some quando acaba; pede a página seguinte ao servidor).

## O que fica por medir

O "antes" está no e2e_log 8886 (309 GET sem filtro entre as 18:19 e as 18:31 de 14/11, pico de 60 por
minuto). O "depois" mede-se nos registos do Supabase quando o build novo chegar aos telemóveis.

## Limite conhecido (não mexido)

O canal ao vivo dos pedidos atribuídos (`stream().eq('assigned_driver_id', …)`) traz o histórico
inteiro do estafeta uma vez por ligação. Limitá-lo mexe na entrega de pedidos em tempo real e não se
pode provar sem telemóvel; fica para uma missão própria com teste real.
