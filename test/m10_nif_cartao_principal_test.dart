// M10 pendências (09/11/2026), bloco A — NIF da fatura no cartão principal do
// mapa nas compras de loja NÃO-parceira (restaurante e mercado), como já
// acontecia no Favor: o estafeta via o NIF só ao abrir "Ver compras" ou na
// folha do talão e passava na caixa sem ele.
//  - aparece desde que aceita (driverAccepted) até fechar o talão;
//  - só o NIF (a caixa "Dei este NIF" continua na folha do talão);
//  - loja parceira, Favor/outros serviços, depois do talão: nada;
//  - o servidor (driver_order_invoice_nif) decide; num erro não aparece nada.
// Pedidos e NIF inventados.
import 'dart:io' as io;

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:bora_app/widgets/driver_invoice_nif_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _pedido({
  OrderServiceType tipo = OrderServiceType.storeShopping,
  OrderStatus estado = OrderStatus.driverAccepted,
  bool parceira = false,
  bool talaoFechado = false,
}) =>
    OrderModel(
      id: 'teste-nif-cartao-0911',
      total: 18.40,
      serviceType: tipo,
      status: estado,
      paymentMethod: PaymentMethod.cash,
      isPartnerStore: parceira,
      isPurchaseFinalized: talaoFechado,
      vendorName: 'Loja Exemplo',
    );

Map<String, dynamic> _bora() => {
      'ok': true,
      'mostrar': true,
      'pediu_fatura': false,
      'tipo': 'bora',
      'nif': '519686233',
    };

Map<String, dynamic> _cliente() => {
      'ok': true,
      'mostrar': true,
      'pediu_fatura': true,
      'tipo': 'cliente',
      'nif': '265148502',
      'nome': 'Ana Teste',
    };

/// Servidor falso que conta as chamadas.
class _Servidor {
  _Servidor(this.resposta);
  final Object? Function() resposta;
  final chamadas = <Map<String, dynamic>>[];

  Future<dynamic> call(String funcao, Map<String, dynamic> params) async {
    expect(funcao, 'driver_order_invoice_nif');
    chamadas.add(params);
    return resposta();
  }
}

Widget _app(OrderModel o, NifRpc rpc) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NifCompraCartaoPrincipal(order: o, rpc: rpc),
        ),
      ),
    );

void main() {
  group('Quando aparece (NifCompraCartaoPrincipal.aplica)', () {
    test('mercado e restaurante não-parceiros, aceite e sem talão: sim', () {
      expect(NifCompraCartaoPrincipal.aplica(_pedido()), isTrue);
      expect(
          NifCompraCartaoPrincipal.aplica(
              _pedido(tipo: OrderServiceType.restaurant)),
          isTrue);
    });

    test('loja parceira: não (a loja trata da fatura)', () {
      expect(NifCompraCartaoPrincipal.aplica(_pedido(parceira: true)), isFalse);
      expect(
          NifCompraCartaoPrincipal.aplica(
              _pedido(tipo: OrderServiceType.restaurant, parceira: true)),
          isFalse);
    });

    test('talão já fechado: não', () {
      expect(
          NifCompraCartaoPrincipal.aplica(_pedido(talaoFechado: true)), isFalse);
    });

    test('só desde que aceita até ao talão: os outros estados não', () {
      for (final e in OrderStatus.values) {
        if (e == OrderStatus.driverAccepted) continue;
        expect(NifCompraCartaoPrincipal.aplica(_pedido(estado: e)), isFalse,
            reason: e.name);
      }
    });

    test('Favor e outros serviços: não (o Favor tem o seu bloco)', () {
      for (final t in OrderServiceType.values) {
        if (t == OrderServiceType.storeShopping ||
            t == OrderServiceType.restaurant) {
          continue;
        }
        expect(NifCompraCartaoPrincipal.aplica(_pedido(tipo: t)), isFalse,
            reason: t.name);
      }
    });
  });

  group('Cartão principal', () {
    testWidgets('mercado não-parceiro: NIF da Bora em grande, sem caixa',
        (t) async {
      final servidor = _Servidor(_bora);
      await t.pumpWidget(_app(_pedido(), servidor.call));
      await t.pumpAndSettle();

      expect(servidor.chamadas, [
        {'p_order_id': 'teste-nif-cartao-0911'}
      ]);
      expect(find.byKey(const Key('driver_invoice_nif_card')), findsOneWidget);
      expect(find.text('NIF PARA A FATURA'), findsOneWidget);
      expect(find.text('519 686 233'), findsOneWidget);
      expect(find.text('Da Bora — o cliente não pediu fatura'), findsOneWidget);
      expect(find.text('Diz este NIF na caixa ANTES de pagar.'), findsOneWidget);
      // A caixa obrigatória fica na folha do talão, não aqui.
      expect(find.byKey(const Key('nif_caixa_dei')), findsNothing);
      expect(find.byKey(const Key('nif_caixa_nao_consegui')), findsNothing);
    });

    testWidgets('restaurante não-parceiro: o NIF que o cliente pediu e o nome',
        (t) async {
      final servidor = _Servidor(_cliente);
      await t.pumpWidget(
          _app(_pedido(tipo: OrderServiceType.restaurant), servidor.call));
      await t.pumpAndSettle();

      expect(servidor.chamadas, hasLength(1));
      expect(find.text('265 148 502'), findsOneWidget);
      expect(find.text('Do cliente — pediu fatura'), findsOneWidget);
      expect(find.text('Nome na fatura: Ana Teste'), findsOneWidget);
    });

    testWidgets(
        'parceira, talão fechado, recolhido ou Favor: nem pergunta ao servidor',
        (t) async {
      for (final o in [
        _pedido(parceira: true),
        _pedido(talaoFechado: true),
        _pedido(estado: OrderStatus.pickedUp),
        _pedido(estado: OrderStatus.callingDriver),
        _pedido(tipo: OrderServiceType.errand),
      ]) {
        final servidor = _Servidor(_bora);
        await t.pumpWidget(_app(o, servidor.call));
        await t.pumpAndSettle();
        expect(servidor.chamadas, isEmpty);
        expect(find.byKey(const Key('driver_invoice_nif_card')), findsNothing);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('o servidor diz que não, dá erro ou não há rede: nada aparece',
        (t) async {
      for (final resposta in <Object? Function()>[
        () => {'ok': true, 'mostrar': false, 'loja_parceira': true},
        () => {'ok': false, 'error': 'nao_e_o_teu_pedido'},
        () => throw const io.SocketException('sem rede'),
      ]) {
        final servidor = _Servidor(resposta);
        await t.pumpWidget(_app(_pedido(), servidor.call));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(servidor.chamadas, hasLength(1));
        expect(find.byKey(const Key('driver_invoice_nif_card')), findsNothing);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('fecha o talão: o NIF sai do cartão principal', (t) async {
      final o = _pedido();
      late StateSetter mudar;
      final servidor = _Servidor(_bora);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (ctx, setState) {
            mudar = setState;
            return NifCompraCartaoPrincipal(order: o, rpc: servidor.call);
          }),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('519 686 233'), findsOneWidget);

      // Como no ecrã: o estado local muda e o realtime confirma a seguir.
      mudar(() => o.isPurchaseFinalized = true);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('driver_invoice_nif_card')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  test('mapa (pela fonte): o cartão principal usa-o logo a seguir ao do Favor',
      () {
    final mapa = io.File('lib/screens/driver_map_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final favor = mapa.indexOf("key: ValueKey('nif_favor_\${focusOrder.id}')");
    // A chamada inteira: só o pedido, sem caixa obrigatória.
    final compra = mapa.indexOf('NifCompraCartaoPrincipal(\n'
        "                  key: ValueKey('nif_compra_\${focusOrder.id}'),\n"
        '                  order: focusOrder,\n'
        '                ),');
    final ganhos = mapa.indexOf("label: 'Ganhos',");
    expect(favor, greaterThan(0));
    expect(compra, greaterThan(favor), reason: 'logo depois do bloco do Favor');
    expect(ganhos, greaterThan(compra), reason: 'antes da linha dos números');
    expect('NifCompraCartaoPrincipal('.allMatches(mapa), hasLength(2),
        reason: 'o construtor e uma só chamada (cartão principal)');
  });
}
