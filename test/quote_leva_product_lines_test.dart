import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// O `p_input` do `quote_order_pricing` TEM de levar `product_lines`.
///
/// Não é detalhe de formato: a função do servidor só soma o carrinho a partir
/// dessa chave — o `items` serve-lhe apenas para os extras das opções. Sem
/// ela o quote devolve `subtotal: 0` e, por arrasto, `small_order_fee: 0`.
///
/// Como o `CartStore.smallOrderFee` prefere o número do servidor ao espelho
/// local, um quote assim apagava a taxa de pedido pequeno do ecrã de
/// pagamento enquanto o gatilho `orders_aa_small_order_fee` a cobrava na
/// mesma — o cliente via um total mais baixo do que o que ia pagar.
///
/// Medido contra a produção a 2026-09-08, com a RPC real e um JWT de
/// utilizador (cesto de 1 × `auc-18633`, unit_price 2,51 → 2,89 no cliente):
///
///   sem `product_lines` → subtotal 0.0,  small_order_fee 0,    total 3.59
///   com `product_lines` → subtotal 2.89, small_order_fee 1.39, total 7.87
///
/// Os 1,39 € do segundo caso são os mesmos que a encomenda leva.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CartStore comCesto({
    required OrderServiceType serviceType,
    double? basePrice,
  }) =>
      CartStore()
        ..configureSession(
          serviceType: serviceType,
          isPartnerStore: false,
          vendorName: 'Auchan',
          vendorRestaurantId: 'auchan-guarda',
          distanceKm: 2.0,
          pickupLocation: const LatLng(40.5373, -7.2680),
          deliveryLocation: const LatLng(40.5400, -7.2700),
        )
        ..addItem(CartItem(
          productId: 'auc-18633',
          name: 'Queijo Boursin',
          price: 2.89, // já com o markup de 15% que o cliente vê
          basePrice: basePrice,
          quantity: 1,
        ));

  test('o pedido de mercado manda as linhas de produto ao servidor', () {
    final entrada =
        comCesto(serviceType: OrderServiceType.storeShopping).entradaDoQuote();

    expect(entrada, isNotNull,
        reason: 'com as duas moradas a RPC pode ser chamada');
    final linhas = entrada!['product_lines'] as List?;
    expect(linhas, isNotNull,
        reason: 'sem product_lines o servidor devolve subtotal 0');
    expect(linhas, hasLength(1));
    expect(linhas!.first, {
      'product_id': 'auc-18633',
      'quantity': 1,
      'unit_price': 2.89,
      'name': 'Queijo Boursin',
    });
  });

  test('o restaurante manda-as também — a taxa vale para as duas', () {
    final entrada =
        comCesto(serviceType: OrderServiceType.restaurant).entradaDoQuote();
    expect((entrada!['product_lines'] as List?), hasLength(1));
  });

  test('unit_price é o preço PURO, senão o servidor duplica o markup', () {
    // O servidor aplica ×1.15 por cima do `unit_price` quando o id não existe
    // em `products`. Mandar o preço já com markup cobrava-o duas vezes.
    final entrada = comCesto(
      serviceType: OrderServiceType.storeShopping,
      basePrice: 2.51,
    ).entradaDoQuote();

    final linha = (entrada!['product_lines'] as List).first as Map;
    expect(linha['unit_price'], 2.51,
        reason: 'basePrice manda quando existe; price (2,89) só é o recurso');
  });

  test('logística não leva linhas — o servidor confia no subtotal do cliente',
      () {
    final entrada = (CartStore()
          ..configureSession(
            serviceType: OrderServiceType.sendPackage,
            isPartnerStore: false,
            vendorName: 'Encomenda',
            distanceKm: 2.0,
            pickupLocation: const LatLng(40.5373, -7.2680),
            deliveryLocation: const LatLng(40.5400, -7.2700),
          ))
        .entradaDoQuote();

    expect(entrada!.containsKey('product_lines'), isFalse);
  });

  test('sem moradas não há pedido nenhum a fazer', () {
    final cart = CartStore()
      ..configureSession(
        serviceType: OrderServiceType.storeShopping,
        isPartnerStore: false,
        vendorName: 'Auchan',
        distanceKm: 2.0,
      );
    expect(cart.entradaDoQuote(), isNull);
  });
}
