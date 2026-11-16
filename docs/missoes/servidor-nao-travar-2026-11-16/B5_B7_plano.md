# B5 e B7 — plano fechado para a sessão com emulador (16/11/2026)

Missão `servidor-nao-travar-2026-11-16`. Escrito na sessão da nuvem (PC offline). Nada destes dois
blocos foi mexido em código: os dois mudam ecrãs grandes da app e têm de ser vistos nas 3
plataformas (Android, iPhone, web) antes de publicar.

## B7 — Estafeta: vários pedidos de mercado ao mesmo tempo

### O que os grandes fazem (pesquisa B7.1, fontes no e2e_log passo B7.1)

- Instacart: lista única; cada pedido do lote tem uma letra (A, B, C) ao lado de cada artigo e
  no chat; um saco/cesto por pedido; na caixa paga-se um cliente de cada vez; talão confirmado
  por pedido; estado do lote guardado no servidor; até 4 pedidos.
- DoorDash: os pedidos continuam separados e troca-se entre eles no topo da app; cartão de
  pagamento carregado com o valor exato de cada pedido; a app sugere a ordem das entregas e o
  estafeta pode mudar.
- Uber Eats: 2 pedidos, rota sugerida.
- Glovo e iFood não publicam nada.

### O que já existe no Bora (não refazer)

- `lib/services/compra_rascunho_service.dart` + `estafeta_guardar_progresso_compra`: cada toque
  (comprado, não há, troca, sacos, valor e foto do talão) grava no servidor **por pedido**.
  O erro de 14/11 (progresso só no telemóvel) já está fechado.
- `lib/services/fila_estafeta.dart` + `fila_do_estafeta`: pedidos da mesma loja ficam juntos em
  `ativos`; o resto fica em espera.
- Painel: `admin_filas_estafetas_screen.dart` (filas) e `admin_rascunho_compra_section.dart`
  (rascunho de cada compra no detalhe do pedido).

### O que falta fazer (o mínimo que copia o padrão provado)

1. **Lista única com letras.** Quando `FilaEstafeta.ativos` tem 2+ pedidos `storeShopping` da
   mesma loja, a folha da lista de compras mostra os artigos dos dois, cada um com a letra do
   pedido (A verde `#16A34A`, B laranja `#F97316`) e um filtro "A / B / Todos". Cada toque
   continua a gravar no rascunho do pedido a que o artigo pertence (`CompraRascunhoService`
   por `orderId`, sem mudar o formato).
2. **"Trocar de pedido" na caixa.** No passo da caixa, um seletor A/B no topo. Pedido A: valor,
   foto do talão, confirmar → corre o fecho de hoje (`finalizar_talao_nao_parceiro`) só para A.
   Depois B, igual. Cada pedido mantém o seu talão, pagamento e recibo. **Não se mexe no fecho
   nem nas contas** (`finalizePurchase`/talão é zona protegida).
3. **Entregas pela ordem do caminho.** Depois dos dois talões, a app sugere o mais perto
   primeiro e o estafeta pode trocar (como a DoorDash).
4. **Limite:** 2 pedidos, mesma loja (3 numa fase seguinte).
5. **Paridade admin (PT-BR):** em "Filas dos entregadores", marcar os pedidos que estão a ser
   comprados juntos (mesma loja, letra A/B) e o progresso de cada um (já vem de
   `admin_rascunho_compra`).
6. **Testes:** widget da lista com 2 pedidos (letras, filtro, toque grava no pedido certo);
   app a morrer a meio e reabrir igual; caixa A depois B chama o fecho uma vez por pedido.
   Pagamento de teste sempre em dinheiro.

Ficheiros prováveis: `lib/screens/driver_map_screen.dart` (folha da compra e passo da caixa),
`lib/services/fila_estafeta.dart`, um widget novo `lib/widgets/compra_em_lote.dart`.
`lib/widgets/errand_execution_sheet.dart` está trancado (Favores) e não entra.

### B7.3 — oferecer o 2.º pedido a quem já tem um (despacho) — precisa-danilo

⚠️ ISTO MEXE EM DINHEIRO/DESPACHO. Está tudo pronto — confirma que eu aplico.

Proposta: no motor de ofertas, um estafeta com 1 pedido `storeShopping` aceite e ainda **antes
da caixa** (sem talão) pode receber a oferta de um 2.º pedido `storeShopping` **da mesma loja**,
criado até 10 min depois, se o destino do 2.º estiver a ≤ 3 km do 1.º. Ganho do estafeta: o de
hoje, pedido a pedido (sem mudar valores). Até lá, o 2.º pedido chega pelo painel com
`ops_reassign_order`.

## B5 — Catálogo do Continente sem descarregar tudo

### Hoje (medido 16/11)

- Desde 15/11 (`loadFullStoreProducts`, bloco 3c) as páginas já são por cursor (sem o servidor
  reordenar a loja 20 vezes), mas a loja inteira continua a descer ao abrir: Continente ~19 800
  produtos = 20 pedidos de 1000.
- Tentativa antiga (B5 v1, 30 por página) partiu as categorias porque os ecrãs as montam em
  memória sobre o que já desceu (build 288).

### Como a Glovo/Uber Eats fazem

Abrem a loja com a lista de secções e os primeiros artigos de cada uma; cada secção carrega mais
ao rolar; a pesquisa vai ao servidor.

### Plano

1. Servidor: `loja_secoes(p_restaurant_id)` → secções (categoria, nº de produtos, ordem) + os
   primeiros 12 produtos de cada (1 pedido). `loja_secao_pagina(p_restaurant_id, p_categoria,
   p_cursor, p_limite)` → página seguinte de uma secção por cursor `(sort_order, id)`.
   Índice `products (restaurant_id, category, sort_order, id) where is_available`.
2. App: `store_products_screen.dart` e `market/market_store_screen.dart` passam a pedir as
   secções e a carregar cada secção ao rolar; a pesquisa continua no servidor
   (`search_products`). Manter `loadFullStoreProducts` atrás de um interruptor
   (`platform_settings`, não financeiro) para voltar atrás num toque.
3. Home: os 15 restaurantes de uma vez passam a só os produtos que a home mostra.
4. Medir antes/depois: nº de pedidos e tempo até a loja aparecer, por `edge_logs`.
5. Não tocar preços nem fotos.
