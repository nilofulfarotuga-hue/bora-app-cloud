// rolagem-lista-compras-2026-11-15 (Danilo no KFC, pedido 3910a6f8, Android):
// na Lista de compras do estafeta, depois de marcar "Comprado", eram precisas
// 3 ou 4 tentativas para descer até ao botão de fechar a compra (havia uma
// rolagem dentro de outra). Agora: o botão está numa barra fixa, visível e
// tocável sem rolar; arrastar em cima dos produtos rola a folha toda; marcar
// um produto não faz a lista saltar.

import 'dart:convert';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:bora_app/services/compra_rascunho_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response _json(Object? corpo, http.Request req) => http.Response(
      jsonEncode(corpo),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

OrderModel _pedidoKfc(int n) => OrderModel.fromSupabase({
      'id': '3910a6f8-teste',
      'status': 'driverAccepted',
      'service_type': 'restaurant',
      'is_partner_store': false,
      'payment_method': 'cash',
      'price': 40,
      'vendor_name': 'KFC',
      'customer_name': 'Cliente Teste',
      'bag_count': 1,
      'items': [
        for (var i = 1; i <= n; i++)
          {'productId': 'p$i', 'name': 'Produto $i do menu', 'price': 4.5, 'quantity': 1},
      ],
    });

Future<void> _assentar(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Altura de telemóvel Android comum (860 lógicos). A largura é 520 porque a
/// letra quadrada dos testes do Flutter é mais larga do que a real (a 412 a
/// linha do total transbordava só no teste; com a letra real cabe).
void _telemovel(WidgetTester t) {
  t.view.physicalSize = const Size(520, 860);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _abrir(WidgetTester t, int produtos) async {
  _telemovel(t);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: listaDeComprasParaTeste(_pedidoKfc(produtos))),
  ));
  await _assentar(t);
}

ScrollPosition _rolagem(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('lista_compras_rolagem')),
        matching: find.byType(Scrollable)).first)
    .position;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async =>
          _json(req.url.path.contains('/rpc/') ? null : [], req)),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CompraRascunhoService.limparParaTeste();
    CompraRascunhoService.enviarParaTeste = (b) async => {'ok': true, 'applied': true};
    CompraRascunhoService.lerParaTeste = (id) async => {'ok': true, 'finalized': false};
  });

  testWidgets('com 6 produtos o botão está à vista e tocável sem rolar',
      (t) async {
    await _abrir(t, 6);
    final botao = find.byKey(const Key('lista_compras_confirmar'));
    expect(botao, findsOneWidget);
    expect(botao.hitTestable(), findsOneWidget,
        reason: 'na barra fixa, por cima de tudo');
    final r = t.getRect(botao);
    expect(r.bottom, lessThanOrEqualTo(860));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(_rolagem(t).pixels, 0, reason: 'sem ter rolado nada');
    // e continua fora da zona que rola
    expect(
        find.descendant(
            of: find.byKey(const Key('lista_compras_rolagem')), matching: botao),
        findsNothing);
  });

  testWidgets('arrastar em cima dos produtos rola a folha toda (uma só rolagem)',
      (t) async {
    await _abrir(t, 8);
    final antes = _rolagem(t).pixels;
    await t.drag(find.text('Produto 1 do menu'), const Offset(0, -400));
    await _assentar(t);
    expect(_rolagem(t).pixels, greaterThan(antes),
        reason: 'o dedo em cima da lista mexe a folha (antes só mexia a lista de dentro)');
    expect(find.byKey(const Key('lista_compras_confirmar')).hitTestable(),
        findsOneWidget);
  });

  testWidgets('marcar Comprado não faz a lista saltar e no fim o botão liga',
      (t) async {
    await _abrir(t, 5);
    for (var i = 0; i < 5; i++) {
      // o botão 'Comprado' só existe nos produtos por marcar
      final comprado = find.text('Comprado').first;
      await t.ensureVisible(comprado);
      await _assentar(t);
      final antes = _rolagem(t).pixels;
      await t.tap(comprado);
      await _assentar(t);
      final depois = _rolagem(t).pixels;
      // Ao marcar, o produto perde a linha dos botões e a folha encolhe: no fundo
      // a posição encosta ao novo fim (desce no máximo o que o produto encolheu).
      // O que não pode acontecer é voltar ao início nem saltar para baixo.
      expect(depois, lessThanOrEqualTo(antes + 1),
          reason: 'a lista não salta para baixo ao marcar o produto ${i + 1}');
      expect(antes - depois, lessThan(60),
          reason: 'a lista não volta ao início ao marcar o produto ${i + 1}');
    }
    final botao = find.descendant(
        of: find.byKey(const Key('lista_compras_confirmar')),
        matching: find.byType(ElevatedButton));
    expect(t.widget<ElevatedButton>(botao).onPressed, isNotNull,
        reason: 'todos marcados: Confirmar compra ligado');
    expect(botao.hitTestable(), findsOneWidget);
    expect(find.text('Confirmar compra'), findsOneWidget);
  });

  test('a folha abre na altura máxima e cabe acima do teclado', () {
    const mq = MediaQueryData(size: Size(412, 860), padding: EdgeInsets.only(top: 24));
    expect(alturaFolhaListaCompras(mq), closeTo((860 - 24) * 0.92, 0.01));
    final comTeclado = mq.copyWith(viewInsets: const EdgeInsets.only(bottom: 300));
    expect(alturaFolhaListaCompras(comTeclado), closeTo((860 - 300 - 24) * 0.92, 0.01));
  });
}
