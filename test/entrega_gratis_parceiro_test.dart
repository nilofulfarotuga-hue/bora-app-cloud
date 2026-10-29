import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/entrega_gratis_da_loja.dart';
import 'package:bora_app/widgets/falta_para_entrega_gratis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// ENTREGA GRÁTIS TAMBÉM NAS LOJAS PARCEIRAS (28/10/2026).
///
/// Boom! Burger (parceira) tem `free_delivery_min_cents = 3000`. Na parceira só
/// sai a taxa base da entrega; os km a mais continuam a pagar-se. Na não
/// parceira sai a entrega toda. Os totais abaixo são os que o servidor deu a
/// 29/10/2026 em `pricing_calculate_loja('restaurant', subtotal, km, true,
/// false, false, 0, 'boom-burger-guarda')`:
///
///   29,99 € a 4 km -> entrega 2,50 | total 34,29
///   30,00 € a 4 km -> entrega 0,00 | total 31,80
///   30,00 € a 6 km -> entrega 1,00 | total 32,80
///   30,00 € a 4 km com apartamento -> entrega 1,50 (só o apartamento) | 33,30
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const boom = 'boom-burger-guarda';
  const mcdonalds = 'mcdonalds-guarda';

  setUp(() {
    SmallOrderFeeService.definirEntregaGratisParaTeste(boom, 3000);
    SmallOrderFeeService.definirEntregaGratisParaTeste(mcdonalds, 2000);
    SmallOrderFeeService.definirTaxaBaseParaTeste(null);
  });

  tearDown(() {
    SmallOrderFeeService.definirEntregaGratisParaTeste(boom, null);
    SmallOrderFeeService.definirEntregaGratisParaTeste(mcdonalds, null);
    SmallOrderFeeService.definirTaxaBaseParaTeste(null);
  });

  CartStore boomComCesto(double subtotal, double km, {bool apartamento = false}) {
    final c = CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: true,
        vendorName: 'Boom! Burger',
        vendorRestaurantId: boom,
        distanceKm: km,
        pickupLocation: const LatLng(40.5373, -7.2680),
        deliveryLocation: const LatLng(40.5400, -7.2700),
      )
      ..addItem(CartItem(
        productId: 'boom-menu',
        name: 'Menu Boom',
        // parceira: o preço é o puro de catálogo
        price: subtotal,
        basePrice: subtotal,
        quantity: 1,
      ));
    if (apartamento) c.setApartmentDelivery(true);
    return c;
  }

  group('parceira (Boom) — só a taxa base sai', () {
    test('29,99 € mostra a entrega e diz quanto falta', () {
      final c = boomComCesto(29.99, 4);

      expect(c.entregaGratisMin, 30.0);
      expect(c.entregaGratis, isFalse);
      expect(c.entregaRiscada, isNull);
      expect(c.faltaParaEntregaGratis, closeTo(0.01, 0.0001));
      final r = c.resumo;
      expect(r.entrega, closeTo(2.50, 0.001));
      expect(r.total, closeTo(34.29, 0.001));
    });

    test('30 € a 4 km dá entrega grátis, com o total do servidor', () {
      final c = boomComCesto(30.00, 4);

      expect(c.entregaGratis, isTrue);
      expect(c.faltaParaEntregaGratis, 0);
      final r = c.resumo;
      expect(r.entrega, closeTo(0, 0.001));
      expect(r.total, closeTo(31.80, 0.001), reason: 'igual ao servidor');
      expect(c.entregaRiscada, closeTo(2.50, 0.001),
          reason: 'o preço normal fica riscado');
    });

    test('30 € a 6 km cobra só os km a mais (a taxa base sai)', () {
      final c = boomComCesto(30.00, 6);

      expect(c.entregaGratis, isTrue);
      final r = c.resumo;
      expect(r.entrega, closeTo(1.00, 0.001),
          reason: '6 km = 2,50 base + 1,00 de 2 km a mais; sai a base');
      expect(r.total, closeTo(32.80, 0.001), reason: 'igual ao servidor');
      expect(c.entregaRiscada, closeTo(3.50, 0.001));
    });

    test('com apartamento: o apartamento continua a pagar-se', () {
      final c = boomComCesto(30.00, 4, apartamento: true);

      final r = c.resumo;
      expect(r.entrega, closeTo(0, 0.001));
      expect(r.apartamento, closeTo(1.50, 0.001));
      expect(r.total, closeTo(33.30, 0.001), reason: 'igual ao servidor');
    });

    test('a taxa base lida do servidor manda sobre a do PricingService', () {
      SmallOrderFeeService.definirTaxaBaseParaTeste(200);
      final c = boomComCesto(30.00, 4);

      // a entrega local é 2,50; sai a taxa base lida (2,00) -> ficam 0,50
      expect(c.resumo.entrega, closeTo(0.50, 0.001));
    });

    test('com o quote do servidor, os números são os dele', () async {
      final c = boomComCesto(30.00, 6);
      c.chamarQuoteParaTeste = (_) async => {
            'service_type': 'restaurant',
            'subtotal': 30.0,
            'service_fee': 1.50,
            'delivery_fee': 1.00,
            'bag_fee': 0.30,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'customer_total': 32.80,
          };
      await c.quoteOrderPricing();

      final r = c.resumo;
      expect(r.doServidor, isTrue);
      expect(r.entrega, 1.00);
      expect(r.total, 32.80);
      expect(c.entregaGratis, isTrue,
          reason: 'o mínimo vem da loja mesmo que o quote não o traga');
    });

    test('sem o mínimo da loja não há oferta', () {
      SmallOrderFeeService.definirEntregaGratisParaTeste(boom, null);
      final c = boomComCesto(99, 4);
      expect(c.entregaGratisMin, isNull);
      expect(c.entregaGratis, isFalse);
      expect(c.entregaRiscada, isNull);
      expect(c.resumo.entrega, closeTo(2.50, 0.001));
    });

    test('"ir buscar" nunca tem entrega grátis', () {
      final c = boomComCesto(30, 4)
        ..setServiceTypeFromOption(OrderServiceType.takeaway);
      expect(c.entregaGratisMin, isNull);
      expect(c.entregaGratis, isFalse);
    });
  });

  group('não parceira — sai a entrega toda (como antes)', () {
    CartStore mcd(double subtotal, double km) => CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: false,
        vendorName: "McDonald's",
        vendorRestaurantId: mcdonalds,
        distanceKm: km,
        pickupLocation: const LatLng(40.5373, -7.2680),
        deliveryLocation: const LatLng(40.5400, -7.2700),
      )
      ..addItem(CartItem(
        productId: 'mcd-1',
        name: 'Menu',
        price: subtotal,
        basePrice: subtotal / 1.15,
        quantity: 1,
      ));

    test('20 € a 6 km: entrega toda grátis, km incluídos', () {
      final c = mcd(20.00, 6);
      expect(c.entregaGratis, isTrue);
      expect(c.resumo.entrega, closeTo(0, 0.001));
      expect(c.entregaRiscada, closeTo(3.50, 0.001));
    });

    test('19,99 € mostra a entrega inteira', () {
      final c = mcd(19.99, 6);
      expect(c.entregaGratis, isFalse);
      expect(c.resumo.entrega, closeTo(3.50, 0.001));
    });
  });

  group('o que o ecrã diz', () {
    testWidgets('ficha da loja: "Entrega grátis a partir de 30 €"', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: EntregaGratisDaLoja(restaurantId: boom))));
      expect(find.text('Entrega grátis a partir de 30 €'), findsOneWidget);
    });

    testWidgets('mínimo com cêntimos mostra-os', (t) async {
      SmallOrderFeeService.definirEntregaGratisParaTeste(boom, 2950);
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: EntregaGratisDaLoja(restaurantId: boom))));
      expect(find.text('Entrega grátis a partir de 29,50 €'), findsOneWidget);
    });

    testWidgets('loja sem o mínimo: não mostra nada', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: EntregaGratisDaLoja(restaurantId: 'outra'))));
      expect(find.byKey(const Key('entrega_gratis_da_loja')), findsNothing);
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: EntregaGratisDaLoja(restaurantId: null))));
      expect(find.byKey(const Key('entrega_gratis_da_loja')), findsNothing);
    });

    testWidgets('"Faltam X € para a entrega grátis"', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: FaltaParaEntregaGratis(falta: 4.5))));
      expect(find.text('Faltam 4,50 € para a entrega grátis'), findsOneWidget);
    });

    test('o carrinho e o pagamento usam as mesmas linhas', () {
      final cart = File('lib/screens/cart_screen.dart').readAsStringSync();
      final pay =
          File('lib/screens/payment_method_screen.dart').readAsStringSync();
      for (final src in [cart, pay]) {
        expect(src, contains("'Entrega grátis'.tr"));
        expect(src, contains('cartStore.entregaRiscada'));
        expect(src, contains("'Taxa base grátis; pagas só os km a mais'.tr"));
      }
      // o pagamento ganhou o "Faltam X €" (o carrinho já o tinha)
      expect(pay, contains('FaltaParaEntregaGratis('));
      expect(cart, contains('Faltam {0} € para a entrega grátis'));
    });

    test('as fichas das lojas mostram a linha', () {
      expect(File('lib/screens/restaurant_menu_screen.dart').readAsStringSync(),
          contains('EntregaGratisDaLoja('));
      expect(File('lib/screens/store_products_screen.dart').readAsStringSync(),
          contains('EntregaGratisDaLoja('));
    });
  });

  test('o mínimo da entrega grátis já não depende de a loja ser não parceira',
      () {
    final src = File('lib/stores/cart_store.dart').readAsStringSync();
    final inicio = src.indexOf('double? get entregaGratisMin');
    final fim = src.indexOf('}', src.indexOf('return cents / 100;', inicio));
    final corpo = src.substring(inicio, fim);
    expect(corpo, isNot(contains('_ehPedidoNaoParceiro')));
    expect(corpo, contains('_temEntregaDeLoja'));
  });
}
