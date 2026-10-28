import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/remote_fees_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// [melhorias-paridade 26/10, item 3] Taxa de serviço para quem não tem conta.
///
/// Cicatriz (26/10, REA): o carrinho do visitante mostrava uma taxa de serviço
/// de recurso (5% num não-parceiro), que não é a regra. Sem número real
/// (quote do servidor ou leitura do servidor), o carrinho escreve "calculada no
/// fim" e o total sai sem ela.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CartStore cesto({required bool parceiro, OrderServiceType tipo = OrderServiceType.restaurant}) =>
      CartStore()
        ..configureSession(
          serviceType: tipo,
          isPartnerStore: parceiro,
          vendorName: 'Loja',
          distanceKm: 2.0,
          pickupLocation: const LatLng(40.5373, -7.2680),
          deliveryLocation: const LatLng(40.5400, -7.2700),
        )
        ..addItem(CartItem(productId: 'p1', name: 'Menu', price: 9.65, quantity: 1));

  test('não-parceiro sem leitura do servidor: taxa por confirmar', () {
    expect(RemoteFeesService.carregadoDoServidor, isFalse);
    final c = cesto(parceiro: false);
    expect(c.taxaServicoConfirmada, isFalse);
  });

  test('parceiro em restaurante: os 5% do contrato contam como reais', () {
    expect(cesto(parceiro: true).taxaServicoConfirmada, isTrue);
  });

  test('com quote do servidor a taxa é real', () async {
    final c = cesto(parceiro: false);
    c.chamarQuoteParaTeste = (_) async => {
          'service_type': c.serviceType.name,
          'subtotal': c.subtotal,
          'service_fee': 0.99,
          'delivery_fee': 2.50,
          'bag_fee': 0.30,
          'apartment_surcharge': 0,
          'small_order_fee': 0,
          'customer_total': 13.44,
        };
    await c.quoteOrderPricing();
    expect(c.taxaServicoConfirmada, isTrue);
  });

  test('o carrinho escreve "calculada no fim" e tira a taxa do total', () {
    final s = File('lib/screens/cart_screen.dart').readAsStringSync();
    expect(s.contains("valorTexto: 'calculada no fim'.tr"), isTrue);
    expect(s.contains('(taxaPorConfirmar ? resumo.taxaServico : 0)'), isTrue);
  });

  test('as taxas leem-se pela get_setting quando não há sessão', () {
    final s = File('lib/services/definicoes_publicas.dart').readAsStringSync();
    expect(s.contains("rpc('get_setting'"), isTrue);
    expect(File('lib/services/remote_fees_service.dart').readAsStringSync().contains('lerDefinicoesPublicas'),
        isTrue);
    expect(File('lib/services/small_order_fee.dart').readAsStringSync().contains('lerDefinicoesPublicas'),
        isTrue);
  });
}
