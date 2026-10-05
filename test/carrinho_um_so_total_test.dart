import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart' show PaymentMethod;
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// [ronda 04/10 · checkout · fechado a 05/10/2026] O que ficou por fazer na
/// app depois de o servidor estar pronto:
///
///  1. UM SÓ TOTAL — o carrinho e o ecrã de pagamento mostram os mesmos
///     números, da mesma fonte (`CartStore.resumo`): os do servidor assim que
///     o quote chega, o cálculo local até lá.
///  2. O quote guardado só vale para o carrinho com que foi pedido. Antes
///     durava 30 s fosse qual fosse o carrinho: mudar um item e olhar outra
///     vez mostrava a taxa e o total do carrinho ANTERIOR.
///  3. A gorjeta não entra no "Total a pagar" (é cobrada à parte).
///  4. "Deixar à porta" segue no pedido — nunca com pagamento em dinheiro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CartStore comCesto() => CartStore()
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
      productId: 'auc-18633',
      name: 'Queijo Boursin',
      price: 2.89,
      quantity: 1,
    ));

  /// O que o `quote_order_pricing` devolve para o carrinho [c] (mesmas chaves).
  Map<String, dynamic> quoteDe(CartStore c, {double? subtotal}) => {
        'service_type': c.serviceType.name,
        'subtotal': subtotal ?? c.subtotal,
        'service_fee': 0.99,
        'delivery_fee': 2.50,
        'bag_fee': 0.10,
        'apartment_surcharge': 0,
        'small_order_fee': 1.39,
        'customer_total': 7.87,
      };

  group('um só total', () {
    test('sem quote, o resumo é o cálculo local', () {
      final cart = comCesto();
      final r = cart.resumo;

      expect(r.doServidor, isFalse);
      expect(r.subtotal, closeTo(2.89, 0.001));
      expect(r.total,
          closeTo(cart.pricingBreakdown.customerTotal + cart.smallOrderFee, 0.001));
    });

    test('quando o quote chega, o total e as parcelas são os do servidor', () async {
      final cart = comCesto();
      // A leitura da taxa da loja (configureSession) também avisa quando
      // acaba: deixa-se passar antes de começar a contar.
      await pumpEventQueue();
      var avisos = 0;
      cart.addListener(() => avisos++);
      cart.chamarQuoteParaTeste = (_) async => quoteDe(cart);

      await cart.quoteOrderPricing();

      expect(avisos, 1, reason: 'os ecrãs têm de ser avisados para redesenhar');
      final r = cart.resumo;
      expect(r.doServidor, isTrue);
      expect(r.total, 7.87);
      expect(r.taxaServico, 0.99);
      expect(r.entrega, 2.50);
      expect(r.saco, 0.10);
      expect(r.taxaPedidoPequeno, 1.39);
      expect(cart.smallOrderFeeVeioDoServidor, isTrue);
    });

    test('a entrega do resumo vem sem o acréscimo de apartamento', () async {
      final cart = comCesto()..setApartmentDelivery(true);
      cart.chamarQuoteParaTeste = (_) async => {
            ...quoteDe(cart),
            'delivery_fee': 4.00,
            'apartment_surcharge': 1.50,
          };

      await cart.quoteOrderPricing();

      expect(cart.resumo.doServidor, isTrue);
      expect(cart.resumo.apartamento, 1.50);
      expect(cart.resumo.entrega, 2.50);
    });

    test('a gorjeta não entra no total', () async {
      final cart = comCesto();
      final local = cart.resumo.total;
      cart.setTipCents(200);
      expect(cart.resumo.total, local);

      cart.chamarQuoteParaTeste = (_) async => quoteDe(cart);
      await cart.quoteOrderPricing();
      expect(cart.resumo.total, 7.87);

      final ecra = File('lib/screens/cart_screen.dart').readAsStringSync();
      expect(ecra, contains('final totalToPay = resumo.total;'));
    });

    test('o ecrã de pagamento lê o mesmo resumo', () {
      final pay =
          File('lib/screens/payment_method_screen.dart').readAsStringSync();
      expect(pay, contains('final resumo = cartStore.resumo;'));
      expect(pay, contains('isErrand ? errandTotal : resumo.total'));
    });
  });

  group('o quote só vale para o carrinho com que foi pedido', () {
    test('mexer no carrinho larga o quote na hora', () async {
      final cart = comCesto();
      cart.chamarQuoteParaTeste = (_) async => quoteDe(cart);
      await cart.quoteOrderPricing();
      expect(cart.resumo.doServidor, isTrue);

      cart.increaseQuantity(cart.items.first);

      expect(cart.quoteDoCarrinho, isNull);
      expect(cart.resumo.doServidor, isFalse,
          reason: 'o total do carrinho anterior nunca pode ficar no ecrã');
      expect(cart.smallOrderFeeVeioDoServidor, isFalse);
    });

    test('o apartamento entra no quote; o saldo aplicado não', () async {
      final cart = comCesto();
      var chamadas = 0;
      cart.chamarQuoteParaTeste = (_) async {
        chamadas++;
        return quoteDe(cart);
      };
      await cart.quoteOrderPricing();
      expect(cart.resumo.doServidor, isTrue);

      // O saldo não muda as parcelas nem o total do pedido: ligar "Usar saldo
      // Bora" não pode largar o quote (o total piscava para o cálculo local).
      cart.setWalletApplied(100);
      expect(cart.resumo.doServidor, isTrue);
      await cart.quoteOrderPricing();
      expect(chamadas, 1);

      cart.setApartmentDelivery(true);
      expect(cart.quoteDoCarrinho, isNull);
    });

    test('carrinho de loja vazio não pede quote', () async {
      final cart = comCesto();
      var chamadas = 0;
      cart.chamarQuoteParaTeste = (_) async {
        chamadas++;
        return quoteDe(cart);
      };
      cart.removeItem(cart.items.first);

      expect(await cart.quoteOrderPricing(), isNull);
      expect(chamadas, 0);
    });

    test('um pedido que rebenta logo não fica preso: o seguinte volta a tentar',
        () async {
      final cart = comCesto();
      var chamadas = 0;
      cart.chamarQuoteParaTeste = (_) {
        chamadas++;
        throw StateError('servidor em baixo');
      };

      expect(await cart.quoteOrderPricing(), isNull);
      expect(await cart.quoteOrderPricing(), isNull);

      expect(chamadas, 2);
    });

    test('a resposta de um carrinho que entretanto mudou não fica guardada',
        () async {
      final cart = comCesto();
      final servidor = Completer<Object?>();
      cart.chamarQuoteParaTeste = (_) => servidor.future;

      final pedido = cart.quoteOrderPricing();
      final doCarrinhoAntigo = quoteDe(cart);
      cart.increaseQuantity(cart.items.first);
      servidor.complete(doCarrinhoAntigo);
      await pedido;

      expect(cart.quoteDoCarrinho, isNull);
      expect(cart.resumo.doServidor, isFalse);
    });

    test('quote com outro subtotal não é deste carrinho', () async {
      final cart = comCesto();
      cart.chamarQuoteParaTeste =
          (_) async => quoteDe(cart, subtotal: cart.subtotal + 0.50);

      await cart.quoteOrderPricing();

      expect(cart.quoteDoCarrinho, isNull);
      expect(cart.resumo.doServidor, isFalse);
    });

    test('dois pedidos ao mesmo tempo fazem uma chamada, e o seguinte vem da cache',
        () async {
      final cart = comCesto();
      var chamadas = 0;
      final servidor = Completer<Object?>();
      cart.chamarQuoteParaTeste = (_) {
        chamadas++;
        return servidor.future;
      };

      final a = cart.quoteOrderPricing();
      final b = cart.quoteOrderPricing();
      servidor.complete(quoteDe(cart));
      await Future.wait([a, b]);
      await cart.quoteOrderPricing();

      expect(chamadas, 1);
    });

    test('sem moradas não há chamada', () async {
      final cart = CartStore()
        ..configureSession(
          serviceType: OrderServiceType.storeShopping,
          isPartnerStore: false,
          vendorName: 'Auchan',
        );
      var chamadas = 0;
      cart.chamarQuoteParaTeste = (_) async {
        chamadas++;
        return <String, dynamic>{};
      };

      expect(await cart.quoteOrderPricing(), isNull);
      expect(chamadas, 0);
    });
  });

  group('deixar à porta', () {
    test('segue com cartão e MB Way, nunca com dinheiro', () {
      final cart = comCesto()..setDeixarAPorta(true);

      expect(cart.deixarAPortaNoPedido(PaymentMethod.card), isTrue);
      expect(cart.deixarAPortaNoPedido(PaymentMethod.mbway), isTrue);
      expect(cart.deixarAPortaNoPedido(PaymentMethod.cash), isFalse,
          reason: 'em dinheiro alguém tem de receber a nota');
    });

    test('desligado por omissão', () {
      expect(comCesto().deixarAPortaNoPedido(PaymentMethod.card), isFalse);
    });

    test('não passa para "ir buscar" nem para outra loja nem para um favor', () {
      final buscar = comCesto()..setDeixarAPorta(true);
      buscar.setServiceTypeFromOption(OrderServiceType.takeaway);
      expect(buscar.deixarAPorta, isFalse);

      final outraLoja = comCesto()..setDeixarAPorta(true);
      outraLoja.configureSession(
        serviceType: OrderServiceType.storeShopping,
        isPartnerStore: false,
        vendorName: 'Continente',
      );
      expect(outraLoja.deixarAPorta, isFalse);

      final favor = comCesto()..setDeixarAPorta(true);
      favor.configureErrandSession(
        description: 'Ir aos correios',
        location: 'CTT Guarda',
        locationCoords: const LatLng(40.5373, -7.2680),
        dropoff: const LatLng(40.5400, -7.2700),
        speed: 'normal',
        hasPurchase: false,
        estimatedCents: 0,
        quote: const {},
        distanceKm: 2.0,
      );
      expect(favor.deixarAPorta, isFalse);
      expect(favor.deixarAPortaNoPedido(PaymentMethod.card), isFalse);
    });

    test('morre com o carrinho', () {
      final cart = comCesto()..setDeixarAPorta(true);
      cart.clearCart();
      expect(cart.deixarAPorta, isFalse);
    });

    test('o pedido leva o que o carrinho decide, nos dois caminhos', () {
      final store = File('lib/stores/cart_store.dart').readAsStringSync();
      expect(store,
          contains('deixarAPorta: deixarAPortaNoPedido(PaymentMethod.card),'));
      expect(store, contains('deixarAPorta: deixarAPortaNoPedido(paymentMethod),'));
    });
  });

  test('o limite do dinheiro compara o total do servidor que o ecrã mostrou', () {
    // `createOrder` já aceitava `totalServidor` (04/10) e ninguém lho passava:
    // a pré-verificação usava o cálculo local, que não conhece a taxa de
    // pedido pequeno.
    final store = File('lib/stores/cart_store.dart').readAsStringSync();
    expect(
        store,
        contains(
            'totalServidor: resumoMostrado.doServidor ? resumoMostrado.total : null,'));
  });

  test('o retrato do carrinho abandonado tem quem o mande', () {
    final store = File('lib/stores/cart_store.dart').readAsStringSync();
    expect(store, contains("rpc('carrinho_guardar'"));
    expect(store, contains("rpc('carrinho_convertido')"));
    // Lei da casca sem fio: a função só conta se alguém a chamar.
    expect(RegExp(r'_agendarRetrato\(\)').allMatches(store).length,
        greaterThanOrEqualTo(2));
  });
}
