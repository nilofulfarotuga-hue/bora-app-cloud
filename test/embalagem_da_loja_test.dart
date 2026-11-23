import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/saco_ou_embalagem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// EMBALAGEM DA LOJA (23/11/2026, AUTORIZO do Danilo 10:44).
///
/// Boom! Burger: 1 € a cada 30 € de pedido, no lugar do saco de 0,30 €.
/// Os totais abaixo saíram do servidor a 23/11/2026:
/// `pricing_calculate_loja('restaurant', sub, 4, true, false, false, 1,
/// 'boom-burger-guarda')` (hoje com saco 0,30) − 0,30 + a fórmula do
/// `embalagem_loja_valor` (100 × GREATEST(1, CEIL(sub×100 / 3000)) / 100):
///
///   12,50 € -> embalagem 1,00 | total 16,63
///   29,99 € -> embalagem 1,00 | total 34,99
///   30,00 € -> embalagem 1,00 | total 32,50  (entrega base grátis)
///   30,01 € -> embalagem 2,00 | total 33,51
///   60,01 € -> embalagem 3,00 | total 66,01
///   95,00 € -> embalagem 4,00 | total 103,75
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const boom = 'boom-burger-guarda';
  const outra = 'outro-restaurante';

  setUp(() {
    SmallOrderFeeService.definirEntregaGratisParaTeste(boom, 3000);
    SmallOrderFeeService.definirTaxaBaseParaTeste(null);
    SmallOrderFeeService.definirEmbalagemParaTeste(boom, 100,
        escalaoCents: 3000);
    SmallOrderFeeService.definirEmbalagemParaTeste(outra, null);
    EmbalagemDaLoja.limparParaTeste();
  });

  tearDown(() {
    SmallOrderFeeService.definirEntregaGratisParaTeste(boom, null);
    SmallOrderFeeService.definirEmbalagemParaTeste(boom, null);
    EmbalagemDaLoja.limparParaTeste();
  });

  CartStore cesto(String loja, double subtotal,
          {bool parceira = true, double km = 4}) =>
      CartStore()
        ..configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: parceira,
          vendorName: loja,
          vendorRestaurantId: loja,
          distanceKm: km,
          pickupLocation: const LatLng(40.5373, -7.2680),
          deliveryLocation: const LatLng(40.5400, -7.2700),
        )
        ..addItem(CartItem(
          productId: '$loja-1',
          name: 'Menu',
          price: subtotal,
          basePrice: subtotal,
          quantity: 1,
        ));

  group('o escalão (espelho do embalagem_loja_valor)', () {
    test('1 € a cada 30 €', () {
      double? v(double s) => SmallOrderFeeService.embalagemEur(boom, s);
      expect(v(0.50), 1.00);
      expect(v(30.00), 1.00);
      expect(v(30.01), 2.00);
      expect(v(60.00), 2.00);
      expect(v(60.01), 3.00);
      expect(v(90.01), 4.00);
      expect(v(95.00), 4.00);
    });

    test('sem escalão = valor fixo; sem embalagem = null', () {
      SmallOrderFeeService.definirEmbalagemParaTeste(outra, 150);
      expect(SmallOrderFeeService.embalagemEur(outra, 99), 1.50);
      SmallOrderFeeService.definirEmbalagemParaTeste(outra, null);
      expect(SmallOrderFeeService.embalagemEur(outra, 99), isNull);
      expect(SmallOrderFeeService.embalagemEur(null, 99), isNull);
    });

    test('é a embalagem? (espelho do e_embalagem_da_loja)', () {
      expect(SmallOrderFeeService.ehEmbalagemDaLoja(boom, 2.00), isTrue);
      expect(SmallOrderFeeService.ehEmbalagemDaLoja(boom, 0.30), isFalse);
      expect(SmallOrderFeeService.ehEmbalagemDaLoja(outra, 0.30), isFalse);
      expect(SmallOrderFeeService.ehEmbalagemDaLoja(boom, 0), isFalse);
    });
  });

  group('carrinho da Boom, antes do quote (conta local)', () {
    for (final caso in const [
      (12.50, 1.00, 16.63),
      (29.99, 1.00, 34.99),
      (30.00, 1.00, 32.50),
      (30.01, 2.00, 33.51),
      (60.01, 3.00, 66.01),
      (95.00, 4.00, 103.75),
    ]) {
      test('${caso.$1} € -> Embalagem ${caso.$2} €, total ${caso.$3} €', () {
        final r = cesto(boom, caso.$1).resumo;
        expect(r.doServidor, isFalse);
        expect(r.embalagemDaLoja, isTrue);
        expect(r.sacoRotulo, 'Embalagem');
        expect(r.saco, closeTo(caso.$2, 0.001));
        expect(r.total, closeTo(caso.$3, 0.001), reason: 'igual ao servidor');
      });
    }
  });

  group('com o quote do servidor', () {
    test('bag_label Embalagem, bag_fee 2,00 -> "Embalagem 2,00 €" e o total dele',
        () async {
      final c = cesto(boom, 30.01);
      c.chamarQuoteParaTeste = (_) async => {
            'service_type': 'restaurant',
            'subtotal': 30.01,
            'service_fee': 1.50,
            'delivery_fee': 0.0,
            'bag_fee': 2.00,
            'bag_label': 'Embalagem',
            'embalagem_da_loja': true,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'customer_total': 33.51,
          };
      await c.quoteOrderPricing();
      final r = c.resumo;
      expect(r.doServidor, isTrue);
      expect(r.embalagemDaLoja, isTrue);
      expect(r.saco, 2.00);
      expect(r.total, 33.51, reason: 'o total é o do servidor, ao cêntimo');
    });

    test('o servidor manda: bag_label Saco mesmo com a loja lida', () async {
      final c = cesto(boom, 20);
      c.chamarQuoteParaTeste = (_) async => {
            'service_type': 'restaurant',
            'subtotal': 20.0,
            'service_fee': 1.00,
            'delivery_fee': 2.50,
            'bag_fee': 0.30,
            'bag_label': 'Saco',
            'embalagem_da_loja': false,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'customer_total': 23.80,
          };
      await c.quoteOrderPricing();
      final r = c.resumo;
      expect(r.embalagemDaLoja, isFalse);
      expect(r.sacoRotulo, 'Saco');
      expect(r.saco, 0.30);
      expect(r.total, 23.80);
    });
  });

  group('loja normal (sem embalagem) não muda nada', () {
    test('parceira normal: Saco 0,30 €', () {
      final r = cesto(outra, 20).resumo;
      expect(r.embalagemDaLoja, isFalse);
      expect(r.sacoRotulo, 'Saco');
      expect(r.saco, closeTo(0.30, 0.001));
      // 20 + 5 % (1,00) + 2,50 + 0,30
      expect(r.total, closeTo(23.80, 0.001));
    });

    test('quote de loja normal: "Saco 0,30 €"', () async {
      final c = cesto(outra, 20);
      c.chamarQuoteParaTeste = (_) async => {
            'service_type': 'restaurant',
            'subtotal': 20.0,
            'service_fee': 1.00,
            'delivery_fee': 2.50,
            'bag_fee': 0.30,
            'bag_label': 'Saco',
            'embalagem_da_loja': false,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'customer_total': 23.80,
          };
      await c.quoteOrderPricing();
      final r = c.resumo;
      expect(r.embalagemDaLoja, isFalse);
      expect(r.saco, 0.30);
      expect(r.total, 23.80);
    });

    test('mercado: a embalagem nunca entra (só restaurante)', () {
      final c = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: true,
          vendorName: boom,
          vendorRestaurantId: boom,
          distanceKm: 4,
          pickupLocation: const LatLng(40.5373, -7.2680),
          deliveryLocation: const LatLng(40.5400, -7.2700),
        );
      expect(c.embalagemLocal, isNull);
    });
  });

  group('o que o ecrã diz', () {
    testWidgets('SacoOuEmbalagem: "Embalagem" quando o servidor diz que sim',
        (t) async {
      EmbalagemDaLoja.definirParaTeste('loja-x', 2.00, true);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SacoOuEmbalagem(
            restaurantId: 'loja-x',
            bagFee: 2.00,
            builder: (_, e) => Text(e ? 'Embalagem 2,00 €' : 'Saco 2,00 €'),
          ),
        ),
      ));
      expect(find.text('Embalagem 2,00 €'), findsOneWidget);
    });

    testWidgets('SacoOuEmbalagem: "Saco" numa loja normal', (t) async {
      EmbalagemDaLoja.definirParaTeste('loja-y', 0.30, false);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SacoOuEmbalagem(
            restaurantId: 'loja-y',
            bagFee: 0.30,
            builder: (_, e) => Text(e ? 'Embalagem 0,30 €' : 'Saco 0,30 €'),
          ),
        ),
      ));
      expect(find.text('Saco 0,30 €'), findsOneWidget);
    });

    test('carrinho, pagamento e detalhe usam o nome do servidor', () {
      final cart = File('lib/screens/cart_screen.dart').readAsStringSync();
      final pay =
          File('lib/screens/payment_method_screen.dart').readAsStringSync();
      for (final src in [cart, pay]) {
        expect(src, contains('resumo.embalagemDaLoja'));
        expect(src, contains("'Embalagem'.tr"));
      }
      for (final f in [
        'lib/screens/order_details_screen.dart',
        'lib/screens/order_tracking_screen.dart',
        'lib/screens/restaurant_dashboard_screen.dart',
        'lib/screens/admin/admin_order_detail_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('SacoOuEmbalagem('),
            reason: f);
      }
      expect(File('lib/screens/admin/admin_partner_detail_screen.dart')
          .readAsStringSync(), allOf(
        contains("'embalagem_cents': valor"),
        contains("'embalagem_escalao_cents': escalao"),
        contains('Embalagem por escalão (€)'),
        contains('Escalão a cada (€) de pedido'),
      ));
    });

    test('o ficheiro protegido dos preços não foi tocado para isto', () {
      final src = File('lib/services/pricing_service.dart').readAsStringSync();
      expect(src, isNot(contains('embalagem')));
    });
  });
}
