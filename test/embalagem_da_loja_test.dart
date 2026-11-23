import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/saco_ou_embalagem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// EMBALAGEM DA LOJA (23/11/2026, AUTORIZO do Danilo 10:44).
///
/// Boom! Burger: 1 € a cada 30 € de pedido, no lugar do saco de 0,30 €.
/// Os totais abaixo são a saída REAL do servidor a 23/11/2026 (~12:15), já
/// com a Boom ligada (embalagem_cents=100, embalagem_escalao_cents=3000):
/// `pricing_calculate_loja('restaurant', sub, 4, true, false, false, 1,
/// 'boom-burger-guarda')`:
///
///   12,50 € -> embalagem 1,00 | total 16,63
///   29,99 € -> embalagem 1,00 | total 34,99
///   30,00 € -> embalagem 1,00 | total 32,50  (entrega base grátis)
///   30,01 € -> embalagem 2,00 | total 33,51
///   32,20 € -> embalagem 2,00 | total 35,81
///   60,01 € -> embalagem 3,00 | total 66,01
///   95,00 € -> embalagem 4,00 | total 103,75
///
/// O quote_order_pricing só deixa a embalagem com `mostra_embalagem: true`
/// no p_input; sem ela devolve o saco 0,30 (30,01 € -> 31,81).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const boom = 'boom-burger-guarda';
  const outra = 'outro-restaurante';

  setUp(() {
    // Estes testes são da app COM a chave `mostra_embalagem` ligada; o grupo
    // "interruptor" no fim prova o que acontece com ela desligada.
    SmallOrderFeeService.definirAppMostraEmbalagemParaTeste(true);
    SmallOrderFeeService.definirEntregaGratisParaTeste(boom, 3000);
    SmallOrderFeeService.definirTaxaBaseParaTeste(null);
    SmallOrderFeeService.definirEmbalagemParaTeste(boom, 100,
        escalaoCents: 3000);
    SmallOrderFeeService.definirEmbalagemParaTeste(outra, null);
    EmbalagemDaLoja.limparParaTeste();
  });

  tearDown(() {
    SmallOrderFeeService.definirAppMostraEmbalagemParaTeste(kAppMostraEmbalagem);
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
      // 32,20 €: a prova da Claude.ai (23/11 11:55, com a chave) deu
      // Embalagem 2,00; total = 32,20 + 1,61 (5 %) + 0 (taxa base grátis) + 2.
      (32.20, 2.00, 35.81),
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

  group('interruptor mostra_embalagem (servidor desde 23/11 11:55)', () {
    test('ligado: a cotação manda mostra_embalagem: true', () {
      final entrada = cesto(boom, 30.01).entradaDoQuote()!;
      expect(entrada[kMostraEmbalagemChave], isTrue);
      expect(kMostraEmbalagemChave, 'mostra_embalagem');
    });

    test('desligado: sem a chave, e a conta local fica com o saco 0,30', () {
      SmallOrderFeeService.definirAppMostraEmbalagemParaTeste(false);
      final c = cesto(boom, 30.01);
      expect(c.entradaDoQuote()!.containsKey(kMostraEmbalagemChave), isFalse);
      final r = c.resumo;
      expect(r.embalagemDaLoja, isFalse);
      expect(r.saco, closeTo(0.30, 0.001));
      // = servidor sem a chave: 31,81 (pricing_calculate_loja de 23/11)
      expect(r.total, closeTo(31.81, 0.001));
    });

    test('esta versão sai DESLIGADA até o create_order mandar a chave', () {
      // O createOrder vive em order_store.dart (zona vermelha; a tranca
      // recusou a edição a 23/11). Ligar só a cotação faria o ecrã mostrar
      // a embalagem e o pedido cobrar o saco.
      final store = File('lib/stores/order_store.dart').readAsStringSync();
      if (!store.contains('kMostraEmbalagemChave')) {
        expect(kAppMostraEmbalagem, isFalse,
            reason: 'não se liga a cotação sem o create_order');
      }
    });
  });

  group('outros ecrãs com o nome certo (adendo 1)', () {
    test('assistente: bag_label Embalagem -> "Embalagem"; sem nome -> "Sacos"',
        () {
      final com = AssistantProposal.fromJson(
          {'bag_fee': 2.0, 'bag_label': 'Embalagem', 'customer_total': 33.51});
      final sem = AssistantProposal.fromJson({'bag_fee': 0.3});
      expect(com.bagFeeEEmbalagem, isTrue);
      expect(sem.bagFeeEEmbalagem, isFalse);
      expect(
          File('lib/screens/client/assistant/assistant_cards.dart')
              .readAsStringSync(),
          contains("p.bagFeeEEmbalagem ? 'Embalagem'.tr : 'Sacos'.tr"));
    });

    test('estafeta e fecho mensal', () {
      expect(File('lib/screens/driver_map_screen.dart').readAsStringSync(),
          contains("label: embalagem ? 'Embalagem' : 'Sacos'"));
      expect(
          File('lib/screens/admin/admin_fecho_mensal_screen.dart')
              .readAsStringSync(),
          contains("'sacos' => 'Sacos (sem a embalagem das lojas)'"));
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
