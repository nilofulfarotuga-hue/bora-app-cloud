# Missão maiores-18 — parte Flutter (07/10/2026)

> Agente `flutter-ui`. Sem commit, sem push. Nada tocado em dispatch, pricing, finalizePurchase,
> bora_tokens, Stripe nem valores de dinheiro. A recusa segue o cancelamento que já existe
> (o servidor abre `cancellation_requests`; a app só chama a RPC).
> Backend: `supabase/migrations/20261007180000_maiores_18_verificacao_idade.sql` (lida inteira; ainda
> NÃO aplicada na base — a app é tolerante: colunas em falta lêem `false`).

## Ficheiros

### Novos
| Ficheiro | O que é |
|---|---|
| `lib/widgets/bora/maior_18.dart` | `Maior18Badge` (etiqueta "+18" preta/branca), `Maior18Aviso` (cartão âmbar), `Maior18Linha` (linha da ficha do produto) |
| `lib/services/maior_18_service.dart` | `Maior18Service.textoPedeMaior18` (RPC `texto_pede_maior_18`) e `confirmar` (RPC `driver_confirm_age_check`); `VerificacaoIdadeResultado` com mensagens PT-PT por código de erro |
| `lib/widgets/verificacao_idade_sheet.dart` | Folha obrigatória do estafeta (`VerificacaoIdadeSheet`, não dispensável, 2 botões, confirmação em diálogo na recusa, erro → mensagem e tentar de novo) e `VerificacaoIdade.garantir(context, order)` (o portão) |
| `lib/screens/admin/admin_maiores_18_screen.dart` | Painel PT-BR: abas Produtos (busca + filtro marcados/não marcados/sugeridos/todos, paginado, toggle por linha), Por categoria (Marcar/Desmarcar todos), Verificações (`order_age_checks`, abre o detalhe do pedido) |
| `test/maiores_18_test.dart` | 8 testes (ver abaixo) |

### Alterados
| Ficheiro | Mudança |
|---|---|
| `lib/models/partner_product.dart` | `ageRestricted` (default false) + `copyWith` |
| `lib/models/cart_item.dart` | `ageRestricted` (default false); `toJson` só grava `age_restricted: true` quando é true (o JSON dos pedidos normais não muda); `fromJson` lê-o |
| `lib/models/order_model.dart` | `hasAgeRestricted` lido de `has_age_restricted` (default false); `toSupabase` NÃO o envia (é trigger) |
| `lib/stores/restaurant_store.dart` | `_productFromRow` + realtime insert/update lêem `age_restricted` (tolerante a null) |
| `lib/stores/cart_store.dart` | `hasAgeRestricted` (algum item +18) |
| `lib/screens/restaurant_menu_screen.dart`, `lib/screens/store_products_screen.dart` | `_resolveProduct` lê `age_restricted` das rows RPC; etiqueta nos cartões `_GlovoProductCard`, `_SectionProductCard`, `_ProductCard`; `ageRestricted` copiado para o `CartItem` ao adicionar |
| `lib/widgets/bora/bora_product_card.dart`, `lib/widgets/market/market_product_card.dart` | etiqueta "+18" no canto da foto; `CartItem` com `ageRestricted` |
| `lib/screens/product_detail_screen.dart` | linha "Só para maiores de 18 anos. O estafeta pede documento na entrega." (antes dos alergénios); 3 caminhos de adicionar levam `ageRestricted` |
| `lib/screens/cart_screen.dart` | aviso âmbar como 1.ª linha da lista quando `cartStore.hasAgeRestricted` |
| `lib/screens/payment_method_screen.dart` | mesmo aviso no topo do ecrã de pagamento |
| `lib/screens/errand_form_screen.dart` | debounce 600 ms na descrição → `texto_pede_maior_18` → `Maior18Aviso` por baixo do campo; timer cancelado no dispose |
| `lib/screens/driver_home_screen.dart` | portão `VerificacaoIdade.garantir` ANTES da foto e do PIN em "Concluir entrega"; selo "+18 · Pede documento de identificação na entrega." no cartão activo, no cartão de pedido disponível e no diálogo "Novo pedido!" |
| `lib/screens/driver_map_screen.dart` | mesmo portão antes da foto/PIN (recusa → volta à lista com `popUntil`); caixa âmbar "+18" no detalhe do pedido |
| `lib/screens/admin/admin_menu_registry.dart` | item "Maiores de 18" na secção Parceiros (a seguir ao Catálogo) |
| `lib/main.dart` | rota `/admin/maiores-18` |
| `lib/screens/admin/admin_order_detail_screen.dart` | select lê `has_age_restricted`; carrega `order_age_checks`; linha "Maiores de 18: +18 · verificação pendente / documento confirmado (data) / RECUSADO … cancelamento aberto" |
| `lib/l10n/strings_en.dart` | 18 entradas novas (bloco "07/10/2026: missão maiores-18") |

## Provas
- `flutter analyze` (completo, 60 s): **0 erros e 0 avisos nos meus ficheiros**. Erros existentes de OUTRA sessão
  (não corrigidos, como mandado): `lib/main.dart:86` e `admin_menu_registry.dart:62` importam
  `admin_assistente_screen.dart`, que não existe no disco (Bora Assistente, mesmo dia, ficheiros `??`);
  avisos antigos em `driver_map_screen.dart:24` (`BRDriver`) e `:2433` (`bold`) — não estão no meu diff.
- `flutter test test/maiores_18_test.dart` → **`00:02 +8: All tests passed!`**
  1. etiqueta "+18" no `BoraProductCard` só com `ageRestricted` (cerveja sim, água não);
  2. `CartStore.hasAgeRestricted` segue os artigos; a marca sobrevive a `toJson/fromJson`; o cartão âmbar
     aparece com o artigo +18 e sai sem ele (mesma regra do `CartScreen`);
  3. folha do estafeta: pedido sem +18 segue sem folha; pedido +18 mostra os 2 botões, **sem "Concluir
     entrega" até escolher**, voltar atrás não fecha; confirmar chama `(id, true)` e segue; recusa pede
     confirmação, chama `(id, false)` e mostra "Pedido enviado para cancelamento; o suporte trata do
     resto."; erro do servidor (`invalid_status`) mostra a mensagem PT-PT e deixa tentar outra vez.
- `flutter test test/l10n_cobertura_test.dart` → **falha, mas não por mim**: as 30 chaves sem inglês são
  todas de `lib/screens/client/assistant/` (Bora Assistente, outra sessão, `??` no git) — incluindo
  o `'+18: o estafeta pede documento na entrega.'` que é deles. Verificação própria
  (`scratchpad/check_l10n.py`): **221 chaves `.tr` nos meus ficheiros, 0 sem inglês**.
- RAM antes do `flutter analyze`: 1881 MB disponíveis (portão pesado 800 MB — OK).
- Terminações de linha: a árvore é CRLF; os 24 ficheiros que toquei/criei ficaram CRLF (verificado a bytes).

## O que ficou de fora e porquê
- **`CartScreen`/`PaymentMethodScreen` inteiros não são pumpados no teste** — precisam de `OrderStore`
  e `RestaurantStore`, que abrem Supabase ao nascer. O teste prova a regra (`hasAgeRestricted`) e o
  widget do aviso; a ligação no ecrã é um `if` de uma linha (ver `cart_screen.dart`).
- **Selo "+18" por item na lista de compras do estafeta** (`driver_item_options.dart`) — não feito; o
  estafeta vê o selo ao nível do pedido (oferta, cartão activo, detalhe), que é o que decide o passo.
- **Reorder / pedidos antigos**: itens vindos de `orders.items` sem `age_restricted` entram no carrinho
  com `false` — o aviso do carrinho pode não aparecer num "pedir outra vez" de um pedido anterior à
  migration; o servidor marca o pedido na mesma (trigger), e o estafeta faz o passo na mesma.
- **Pré-carregar o estado da verificação na app do estafeta** (se já confirmou noutro aparelho): a RPC é
  idempotente (`already`) e o portão guarda em memória os confirmados nesta sessão; não se lê
  `order_age_checks` ao abrir o ecrã.
- **Os erros de `admin_assistente_screen.dart` e as chaves l10n do assistente** são da outra sessão;
  não toquei. Até esse ficheiro existir, `flutter analyze` e o teste de l10n chumbam no CI por causa
  deles — não por esta missão.
- Nada foi commitado nem empurrado (ordem). A migration continua na gaveta para a Claude.ai aplicar.
