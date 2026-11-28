# Remendo do `order_store.dart` que a tranca não deixa fazer (27/11/2026)

**Para quem:** Claude.ai (pelo GitHub) ou uma sessão com a tranca aberta pelo Danilo. A tranca do repositório
(`.claude/settings.json` → `deny Edit(./lib/stores/order_store.dart)` e `bora-mods/zonas-vermelhas.json`,
motivo "order_store.dart (finalizePurchase)") recusou o Edit nesta missão, e também a cópia do ficheiro para
preparar o diff. Não foi contornado. Nenhuma das 3 mudanças toca no `finalizePurchase`, em preços, comissões,
taxas, tokens, carteira ou Stripe: só a condição do travão "loja fechada".

**Ordem do Danilo:** 27/11/2026 21:52 e 21:57 (missão `loja-fechada-agendar-2026-11-27`): com a loja fechada,
deixar encher o carrinho e marcar para amanhã (da abertura ao fecho) ou outro dia.

**Porquê:** o travão da app (`isPartnerStore && serviceType == restaurant` + `!restaurant.isOpenNow()`) recusa
no último passo TODOS os pedidos de restaurante parceiro fechado — também os que têm hora marcada e as
encomendas de festa. Foi o que parou a Karen Sabrina na Sabores do Brasil às 21:38. O servidor já deixa
passar (migração `20261127215900`), o carrinho já marca a hora; só falta este travão.

A regra nova está pronta e testada num ficheiro livre: `lib/utils/loja_fechada_pedido.dart`
(`lojaFechadaTravaPedidoDoCarrinho`), provada em `test/loja_fechada_agendar_test.dart` (relógio fixo, Lisboa).

## As 3 mudanças (todas em `lib/stores/order_store.dart`)

1. Imports, logo a seguir a `import '../utils/religar_com_espera.dart';`:

```dart
import '../utils/loja_fechada_pedido.dart';
```

2. `startCardPaymentDraft` (perto da linha 607). Trocar:

```dart
    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOpenNow()) return null;
    }
```

por:

```dart
    // 27/11/2026: só trava "para agora" (sem hora marcada e sem encomenda de
    // festa); com a razão, para o ecrã dizer quando abre.
    lastCreateOrderError = null;
    if (isPartnerStore &&
        serviceType == OrderServiceType.restaurant &&
        lojaFechadaTravaPedidoDoCarrinho(
          loja: _restaurantStore?.restaurantByName(vendorName),
          itens: items,
          categoriaDoProduto: _restaurantStore?.productCategoryById,
        )) {
      lastCreateOrderError = 'STORE_CLOSED';
      return null;
    }
```

3. `createOrder` (perto da linha 914). Trocar:

```dart
    if (isPartnerStore && serviceType == OrderServiceType.restaurant) {
      final restaurant = _restaurantStore?.restaurantByName(vendorName);
      if (restaurant != null && !restaurant.isOpenNow()) {
        // 11/11/2026 (Farmácia da Sé às 21:23): sem razão, o ecrã mostrava o
        // genérico "Não foi possível criar o pedido". Diz-se que está fechada.
        lastCreateOrderError = 'STORE_CLOSED';
        return false;
      }
    }
```

por:

```dart
    if (isPartnerStore &&
        serviceType == OrderServiceType.restaurant &&
        // 27/11/2026 (Sabores do Brasil às 21:38): só trava "para agora" — com
        // hora marcada no carrinho ou encomenda de festa, a loja fechada agora
        // não trava (o servidor volta a decidir: STORE_CLOSED).
        lojaFechadaTravaPedidoDoCarrinho(
          loja: _restaurantStore?.restaurantByName(vendorName),
          itens: items,
          categoriaDoProduto: _restaurantStore?.productCategoryById,
        )) {
      // 11/11/2026 (Farmácia da Sé às 21:23): sem razão, o ecrã mostrava o
      // genérico "Não foi possível criar o pedido". Diz-se que está fechada.
      lastCreateOrderError = 'STORE_CLOSED';
      return false;
    }
```

## Porque é que chega

- A hora escolhida no carrinho continua em `AgendarPedidoEstado.instance` quando o `createOrder` corre (o
  `CartStore` marca-a com `client_preparar_agendamento` ANTES e só a limpa DEPOIS, em `gravarEscolha`).
- A encomenda de festa lê-se pela prateleira dos itens (`RestaurantStore.productCategoryById`), a mesma que o
  carrinho usa para abrir o `FestasQuandoScreen`; o servidor deixa-a passar (`_store_closed_guard_orders`).
- O ecrã de pagamento já mostra a frase nova para `STORE_CLOSED` (diz quando abre e manda voltar ao carrinho
  para marcar), nos dois caminhos (dinheiro/MB Way e cartão).

## Prova depois de aplicar

`flutter analyze` (0 erros) e `flutter test test/loja_fechada_agendar_test.dart`. Na web, conta de teste, em
DINHEIRO: Goola Açaí ou Sabores do Brasil fechada → encher o carrinho → o seletor abre na 1.ª janela de amanhã →
Finalizar → o pedido nasce com `scheduled_for` (SELECT) → cancelar no fim e confirmar que não ficou acerto.
