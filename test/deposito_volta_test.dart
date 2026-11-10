import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/deposito_volta_nota.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// DEPÓSITO VOLTA (09/11/2026) — 0,10 € por lata ou garrafa de plástico até
/// 3 L, numa linha À PARTE (obrigação legal). Quem calcula e cobra é o
/// servidor; a app mostra-o e manda em cada item a chave `deposit_units`,
/// que é o sinal ao `create_order` de que esta versão mostra a linha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Carrinho de mercado com 1 pack de 6 latas (×[packs]) e um queijo.
  CartStore comPack({int packs = 1}) => CartStore()
    ..configureSession(
      serviceType: OrderServiceType.storeShopping,
      isPartnerStore: false,
      vendorName: 'Auchan',
      vendorRestaurantId: 'auchan-guarda',
      distanceKm: 2.0,
      pickupLocation: const LatLng(40.5373, -7.2680),
      deliveryLocation: const LatLng(40.5400, -7.2700),
    )
    ..addItem(CartItem(
      productId: 'auc-coca-pack6',
      name: 'Coca-Cola lata 33 cl pack 6',
      price: 4.59,
      quantity: packs,
      depositUnits: 6,
    ))
    ..addItem(CartItem(
      productId: 'auc-18633',
      name: 'Queijo Boursin',
      price: 2.89,
    ));

  group('CartItem leva o sinal deposit_units', () {
    test('toJson tem SEMPRE a chave, mesmo a 0', () {
      final semDeposito =
          CartItem(productId: 'cnt-queijo-1', name: 'Queijo', price: 2);
      expect(semDeposito.toJson().containsKey('deposit_units'), isTrue,
          reason: 'sem a chave o create_order não cobra o depósito');
      expect(semDeposito.toJson()['deposit_units'], 0);

      final pack = CartItem(
          productId: 'cnt-coca-6', name: 'Pack 6', price: 4, depositUnits: 6);
      expect(pack.toJson()['deposit_units'], 6);
    });

    test('fromJson faz a volta inteira; linha antiga ou estragada dá 0', () {
      final pack = CartItem(
          productId: 'cnt-coca-6',
          name: 'Pack 6',
          price: 4,
          quantity: 2,
          depositUnits: 6);
      final volta = CartItem.fromJson(pack.toJson());
      expect(volta.depositUnits, 6);
      expect(volta.quantity, 2);

      expect(
          CartItem.fromJson({'productId': 'x', 'name': 'Antigo', 'price': 1})
              .depositUnits,
          0);
      expect(
          CartItem.fromJson({
            'productId': 'x',
            'name': 'Negativo',
            'price': 1,
            'deposit_units': -3,
          }).depositUnits,
          0);
    });

    test('o pedido de quote leva deposit_units em cada item', () {
      final entrada = comPack().entradaDoQuote()!;
      final items = (entrada['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(2));
      expect(items.every((i) => i.containsKey('deposit_units')), isTrue);
      expect(items.first['deposit_units'], 6);
      expect(items.last['deposit_units'], 0);
    });
  });

  group('resumo do carrinho', () {
    test('sem quote: a conta provisória soma o depósito ao total', () {
      final cart = comPack(packs: 2);
      final r = cart.resumo;
      expect(r.doServidor, isFalse);
      expect(r.depositoUnidades, 12);
      expect(r.depositoCents, 120);
      // Fora do subtotal: só os produtos.
      expect(r.subtotal, closeTo(4.59 * 2 + 2.89, 0.001));
      expect(
          r.total,
          closeTo(
              cart.pricingBreakdown.customerTotal + cart.smallOrderFee + 1.20,
              0.001));
    });

    test('carrinho sem latas: nada muda', () {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: false,
          vendorName: 'Auchan',
          distanceKm: 2.0,
          pickupLocation: const LatLng(40.5373, -7.2680),
          deliveryLocation: const LatLng(40.5400, -7.2700),
        )
        ..addItem(CartItem(productId: 'auc-1', name: 'Queijo', price: 2.89));
      final r = cart.resumo;
      expect(r.depositoCents, 0);
      expect(r.depositoUnidades, 0);
      expect(r.total,
          closeTo(cart.pricingBreakdown.customerTotal + cart.smallOrderFee,
              0.001));
    });

    test('com quote: o depósito é o do servidor e NÃO se soma outra vez',
        () async {
      final cart = comPack();
      await pumpEventQueue();
      cart.chamarQuoteParaTeste = (_) async => {
            'service_type': cart.serviceType.name,
            'subtotal': cart.subtotal,
            'service_fee': 0.99,
            'delivery_fee': 2.50,
            'bag_fee': 0.10,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'deposit_units': 6,
            'deposit_unit_cents': 10,
            'deposit_cents': 60,
            // Já com o depósito lá dentro (contrato do servidor).
            'customer_total': 11.07,
          };

      await cart.quoteOrderPricing();

      final r = cart.resumo;
      expect(r.doServidor, isTrue);
      expect(r.depositoUnidades, 6);
      expect(r.depositoCents, 60);
      expect(r.total, 11.07, reason: 'o customer_total já traz o depósito');
    });

    test('servidor sem a migração: quote sem as chaves → sem linha', () async {
      final cart = comPack();
      await pumpEventQueue();
      cart.chamarQuoteParaTeste = (_) async => {
            'service_type': cart.serviceType.name,
            'subtotal': cart.subtotal,
            'service_fee': 0.99,
            'delivery_fee': 2.50,
            'bag_fee': 0.10,
            'apartment_surcharge': 0,
            'small_order_fee': 0,
            'customer_total': 11.07,
          };

      await cart.quoteOrderPricing();

      final r = cart.resumo;
      expect(r.doServidor, isTrue);
      expect(r.depositoCents, 0);
      expect(r.total, 11.07);
    });
  });

  group('pedido gravado', () {
    test('OrderModel.fromSupabase lê os 4 campos e o total do depósito', () {
      final order = OrderModel.fromSupabase({
        'id': '00000000-0000-0000-0000-0000000000a1',
        'status': 'driverAccepted',
        'service_type': 'storeShopping',
        'payment_method': 'cash',
        'price': 11.07,
        'vendor_name': 'Auchan',
        'deposit_units': 6,
        'deposit_cents': 60,
        'deposit_ajuste_cents': -10,
        'deposit_from_receipt_cents': 50,
      });
      expect(order.depositUnits, 6);
      expect(order.depositCents, 60);
      expect(order.depositAjusteCents, -10);
      expect(order.depositFromReceiptCents, 50);
      expect(order.depositoVoltaTotal, closeTo(0.50, 0.0001));
    });

    test('pedido antigo, sem as colunas: tudo a 0', () {
      final order = OrderModel.fromSupabase({
        'id': '00000000-0000-0000-0000-0000000000a2',
        'status': 'delivered',
        'service_type': 'restaurant',
        'payment_method': 'card',
        'price': 6.50,
      });
      expect(order.depositUnits, 0);
      expect(order.depositCents, 0);
      expect(order.depositAjusteCents, 0);
      expect(order.depositFromReceiptCents, isNull);
      expect(order.depositoVoltaTotal, 0);
    });
  });

  group('produtos e opções', () {
    test('deposit_units da linha: com, sem e estragado', () {
      expect(unidadesDepositoDaLinha({'deposit_units': 6}), 6);
      expect(unidadesDepositoDaLinha({}), 0);
      expect(unidadesDepositoDaLinha({'deposit_units': null}), 0);
      expect(unidadesDepositoDaLinha({'deposit_units': -1}), 0);
    });

    test('a lata escolhida no menu traz a sua embalagem', () {
      final lata = ProductOptionItem.fromMap(
          {'id': 'o1', 'name': 'Pepsi lata', 'deposit_units': 1}, 'g1');
      final agua = ProductOptionItem.fromMap(
          {'id': 'o2', 'name': 'Água do copo'}, 'g1');
      expect(lata.depositUnits, 1);
      expect(agua.depositUnits, 0);
    });

    test('o erro "coluna não existe" do servidor é reconhecido', () {
      expect(
          faltaColunaDeposito(Exception(
              'PostgrestException(message: column products.deposit_units '
              'does not exist, code: 42703)')),
          isTrue);
      expect(faltaColunaDeposito(Exception('timeout')), isFalse);
    });
  });

  group('nota "+0,10 € depósito Volta"', () {
    test('textos: 1 lata e pack de 6', () {
      expect(DepositoVoltaNota.texto(1), '+0,10 € depósito Volta');
      expect(DepositoVoltaNota.texto(6),
          '+0,60 € depósito Volta (6 embalagens)');
      expect(DepositoVoltaNota.textoCurto(6), '+0,60 € depósito Volta');
      expect(DepositoVoltaNota.rotulo(3), 'Depósito Volta (3 embalagens)');
      expect(DepositoVoltaNota.rotulo(1), 'Depósito Volta (1 embalagem)');
    });

    testWidgets('aparece com depósito e some sem ele', (tester) async {
      Future<void> mostra(Widget w) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: w))));

      await mostra(const DepositoVoltaNota(unidades: 1));
      expect(find.text('+0,10 € depósito Volta'), findsOneWidget);

      await mostra(const DepositoVoltaNota(unidades: 6));
      expect(find.text('+0,60 € depósito Volta (6 embalagens)'),
          findsOneWidget);

      await mostra(const DepositoVoltaNota(unidades: 0));
      expect(find.byKey(const Key('deposito_volta_nota')), findsNothing);
    });

    testWidgets('cartão estreito: a versão curta encolhe, não rebenta',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              child: DepositoVoltaNota.porBaixoDoPreco(
                preco: const Text('4,59 €'),
                unidades: 6,
              ),
            ),
          ),
        ),
      ));
      expect(find.text('+0,60 € depósito Volta'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Sem depósito o preço volta tal e qual (o cartão não muda).
      const preco = Text('4,59 €');
      expect(
          identical(
              DepositoVoltaNota.porBaixoDoPreco(preco: preco, unidades: 0),
              preco),
          isTrue);
    });
  });
}
