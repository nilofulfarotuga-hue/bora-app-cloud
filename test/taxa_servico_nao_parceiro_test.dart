import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/remote_fees_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/valor_com_risco.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAXA DE SERVIÇO DO NÃO-PARCEIRO — 2,50 € → 0,99 € (2026-09-08).
///
/// Os números esperados não foram inventados aqui: são a saída literal de
/// `pricing_calculate` corrida contra a produção a 2026-09-08 —
///
///   select pricing_calculate('storeShopping', 13.50, 2.0, false, false,
///                            false, 1);
///   → (2.50, 0.99, 0.99, 5.16, 17.09, 0.00, 0.10)
///     delivery_fee, service_fee, platform_commission, driver_earnings,
///     customer_total, apartment_surcharge, bag_fee
///
/// Se o cliente e o servidor deixarem de bater ao cêntimo, este teste parte.
void main() {
  // O CartStore grava o carrinho em SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('o carrinho bate ao cêntimo com o servidor', () {
    test('mercado sem contrato: 0,99 € de taxa e 17,09 € de total', () {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: false,
          vendorName: 'Continente',
          distanceKm: 2.0,
        )
        ..addItem(CartItem(
          productId: 'p1',
          name: 'Cabaz de teste',
          price: 13.50,
          quantity: 1,
        ));

      final p = cart.pricingBreakdown;
      expect(p.serviceFee, 0.99, reason: 'servidor: service_fee = 0.99');
      expect(p.deliveryFee, 2.50, reason: 'servidor: delivery_fee = 2.50');
      expect(p.bagFee, 0.10, reason: 'servidor: bag_fee = 0.10');
      expect(p.customerTotal, closeTo(17.09, 0.001),
          reason: 'servidor: customer_total = 17.09');
      // No não-parceiro a comissão da plataforma É a taxa de serviço.
      expect(p.platformCommission, closeTo(0.99, 0.001));
    });

    test('a taxa mostrada é a do servidor, não a constante protegida', () {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: false,
          vendorName: 'Lidl',
          distanceKm: 2.0,
        );
      expect(cart.taxaServicoNaoParceiro, 0.99);
      expect(cart.taxaServicoNaoParceiro, isNot(2.50));
    });

    test('a loja parceira não é tocada — a taxa dela é 5% do subtotal', () {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.restaurant,
          isPartnerStore: true,
          vendorName: 'Sabores de Casa',
          distanceKm: 2.0,
        )
        ..addItem(CartItem(
          productId: 'p1',
          name: 'Prato do dia',
          price: 20.00,
          quantity: 1,
        ));

      expect(cart.taxaServicoNaoParceiro, isNull);
      expect(cart.taxaServicoRiscada, isNull);
      expect(cart.pricingBreakdown.serviceFee, closeTo(1.00, 0.001));
    });

    test('encomenda/levar compras não leva esta taxa', () {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.sendPackage,
          isPartnerStore: false,
          vendorName: 'Encomenda',
          distanceKm: 2.0,
        );
      expect(cart.taxaServicoNaoParceiro, isNull);
      expect(cart.taxaServicoRiscada, isNull);
    });
  });

  group('valores de recurso e a regra do risco', () {
    test('sem leitura do servidor ficam 0,99 € e 2,50 € riscado', () {
      expect(RemoteFeesService.taxaServicoNaoParceiroEur, 0.99);
      expect(RemoteFeesService.taxaServicoNaoParceiroRiscadaEur, 2.50);
    });

    test('risco a 0 (ou nulo) faz o riscado desaparecer', () {
      const semRisco =
          TaxaServicoNaoParceiro(atualCents: 99, riscoCents: 0);
      expect(semRisco.riscoEur, isNull);
    });

    test('uma subida não se anuncia como descida', () {
      const subiu =
          TaxaServicoNaoParceiro(atualCents: 250, riscoCents: 99);
      expect(subiu.riscoEur, isNull);
      const igual =
          TaxaServicoNaoParceiro(atualCents: 99, riscoCents: 99);
      expect(igual.riscoEur, isNull);
    });
  });

  group('o risco no ecrã', () {
    testWidgets('mostra o antigo riscado e o actual a verde', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ValorComRisco(valor: 0.99, riscado: 2.50),
        ),
      ));

      final antigo = tester.widget<Text>(find.text('€2.50'));
      expect(antigo.style?.decoration, TextDecoration.lineThrough,
          reason: 'o valor antigo tem de aparecer riscado');

      final actual = tester.widget<Text>(find.text('€0.99'));
      expect(actual.style?.color, const Color(0xFF16A34A),
          reason: 'o valor actual é verde Bora');
      expect(actual.style?.fontWeight, FontWeight.w800);

      // O riscado é MAIS PEQUENO que o actual — nunca compete com ele.
      expect(antigo.style!.fontSize!, lessThan(actual.style!.fontSize!));
    });

    testWidgets('sem risco só aparece o valor actual', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ValorComRisco(valor: 0.99)),
      ));
      expect(find.text('€0.99'), findsOneWidget);
      expect(find.text('€2.50'), findsNothing);
    });
  });
}
