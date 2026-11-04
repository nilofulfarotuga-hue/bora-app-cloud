import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/utils/premio_checkin_linha.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Prémio do check-in tipo DESCONTO no carrinho (04/11/2026).
///
/// O vale vai no orçamento como `checkin_vale_id` e o total mostrado é o
/// `customer_total` do servidor (já com o desconto). Enquanto o pedido não o
/// leva (`CartStore.descontoCheckinNoPedido` a false), o carrinho ignora o
/// vale: nunca se mostra um total que o pedido não cobra.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CartStore cesto({String loja = 'continente-guarda'}) => CartStore()
    ..configureSession(
      serviceType: OrderServiceType.storeShopping,
      isPartnerStore: false,
      vendorName: 'Continente',
      vendorRestaurantId: loja,
      distanceKm: 2.0,
      pickupLocation: const LatLng(40.5373, -7.2680),
      deliveryLocation: const LatLng(40.5400, -7.2700),
    )
    ..addItem(CartItem(
        productId: 'cont-1', name: 'Azeite', price: 5.0, quantity: 7));

  Map<String, dynamic> quote(CartStore c,
          {double desconto = 0, int falta = 0, double total = 32.60}) =>
      {
        'service_type': c.serviceType.name,
        'subtotal': c.subtotal,
        'service_fee': 0.99,
        'delivery_fee': 2.50,
        'bag_fee': 0.10,
        'apartment_surcharge': 0,
        'small_order_fee': 0,
        'customer_total': total,
        'checkin_desconto': desconto,
        'checkin_desconto_falta_cents': falta,
        'checkin_vale_id': desconto > 0 || falta > 0 ? 'vale-1' : null,
      };

  tearDown(() => CartStore.descontoCheckinNoPedido = false);

  test('desligado: o vale é ignorado e não vai no orçamento', () {
    CartStore.descontoCheckinNoPedido = false;
    final c = cesto()..definirValeDesconto('vale-1', valorCents: 300);
    expect(c.checkinValeId, isNull);
    expect(c.entradaDoQuote()!.containsKey('checkin_vale_id'), isFalse);
  });

  test('ligado: vai no orçamento e o resumo mostra o desconto do servidor',
      () async {
    CartStore.descontoCheckinNoPedido = true;
    final c = cesto()..definirValeDesconto('vale-1', valorCents: 300);
    expect(c.entradaDoQuote()!['checkin_vale_id'], 'vale-1');
    await pumpEventQueue();
    c.chamarQuoteParaTeste = (_) async => quote(c, desconto: 3.0);
    await c.quoteOrderPricing();
    final r = c.resumo;
    expect(r.total, 32.60, reason: 'o total é o do servidor, ao cêntimo');
    expect(r.descontoPremio, 3.0);
    expect(c.checkinDescontoFaltaCents, 0);
  });

  test('ligado, abaixo do mínimo: diz quanto falta e não desconta', () async {
    CartStore.descontoCheckinNoPedido = true;
    final c = cesto()..definirValeDesconto('vale-1', valorCents: 300);
    await pumpEventQueue();
    c.chamarQuoteParaTeste = (_) async => quote(c, falta: 528, total: 20.0);
    await c.quoteOrderPricing();
    expect(c.resumo.descontoPremio, 0);
    expect(c.checkinDescontoFaltaCents, 528);
    expect(c.checkinValeValorCents, 300);
  });

  test('trocar de loja ou limpar o carrinho larga o vale', () {
    CartStore.descontoCheckinNoPedido = true;
    final c = cesto()..definirValeDesconto('vale-1', valorCents: 300);
    c.configureSession(
      serviceType: OrderServiceType.storeShopping,
      isPartnerStore: false,
      vendorName: 'Auchan',
      vendorRestaurantId: 'auchan-guarda',
      distanceKm: 2.0,
      pickupLocation: const LatLng(40.5373, -7.2680),
      deliveryLocation: const LatLng(40.5400, -7.2700),
    );
    expect(c.checkinValeId, isNull);
    c.definirValeDesconto('vale-1', valorCents: 300);
    c.clearCart();
    expect(c.checkinValeId, isNull);
  });

  test('linha do prémio no ecrã do estafeta reconhece o nome do servidor', () {
    expect(ehLinhaPremioCheckin('Prémio Bora Todo Dia: Big Mac'), isTrue);
    expect(ehLinhaPremioCheckin('prémio bora todo dia: x'), isTrue);
    expect(ehLinhaPremioCheckin('Big Mac'), isFalse);
    expect(ehLinhaPremioCheckin('Big Mac', productId: 'premio-checkin-abc'),
        isTrue);
  });
}
