import 'dart:convert';

import 'package:bora_app/screens/admin/admin_orders_screen.dart';
import 'package:bora_app/services/pedido_origem_service.dart';
import 'package:bora_app/widgets/origem_whatsapp_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pedidos do robô de WhatsApp (tabela order_origem): etiqueta "WhatsApp" no
/// cartão do parceiro, coluna "Origem" + filtro no painel admin, e leitura que
/// nunca estraga o ecrã quando a tabela falha. Servidor falso (MockClient)
/// com o SDK verdadeiro. Dados inventados.

const _json = {'content-type': 'application/json; charset=utf-8'};

/// O que o "servidor" responde a order_origem; 404 = tabela ainda sem existir.
int _origemStatus = 200;
List<Map<String, Object?>> _origemRows = [];
final List<Uri> _pedidosOrigem = [];

Map<String, Object?> _pedido(String id, String loja) => {
      'id': id,
      'status': 'created',
      'payment_method': 'cash',
      'payment_status': 'pending',
      'price': 12.5,
      'created_at': '2026-10-28T12:00:00Z',
      'vendor_name': loja,
      'assigned_driver_id': null,
      'customer_name': 'Cliente Teste',
      'service_type': 'delivery',
      'takeaway_pickup_code': null,
      'scheduled_for': null,
      'prep_time_minutes': null,
      'wallet_applied_cents': 0,
      'tokens_applied_count': 0,
      'tokens_applied_value_cents': 0,
      'stripe_charge_cents': 0,
      'is_test_order': false,
    };

Future<http.Response> _servidor(http.Request req) async {
  final p = req.url.path;
  http.Response ok(Object? o) =>
      http.Response(jsonEncode(o), 200, headers: _json, request: req);
  if (p.endsWith('/rest/v1/orders')) {
    return ok([
      _pedido('aaaa1111x', 'Boom! Burger'),
      _pedido('bbbb2222x', 'Boom! Burger'),
      _pedido('cccc3333x', 'Outra Loja'),
    ]);
  }
  if (p.endsWith('/rest/v1/order_origem')) {
    _pedidosOrigem.add(req.url);
    if (_origemStatus != 200) {
      return http.Response(
          jsonEncode({
            'code': 'PGRST205',
            'message': 'Could not find the table public.order_origem',
          }),
          _origemStatus,
          headers: _json,
          request: req);
    }
    // Responde só às linhas pedidas (como faz o filtro in.(...)).
    final pedido = req.url.queryParameters['order_id'] ?? '';
    return ok(_origemRows
        .where((r) => pedido.contains(r['order_id'] as String))
        .toList());
  }
  return ok(<Object?>[]);
}

Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<void> _abreAdmin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: AdminOrdersScreen()));
  await _servidorResponde(tester);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
  });

  setUp(() {
    _origemStatus = 200;
    _origemRows = [];
    _pedidosOrigem.clear();
  });

  group('etiqueta WhatsApp', () {
    testWidgets('mostra "WhatsApp" com o ícone de chat quando origem=whatsapp',
        (tester) async {
      await tester.pumpWidget(
          _app(const OrigemWhatsAppChip(origem: kOrigemWhatsApp)));
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.byIcon(Icons.chat), findsOneWidget);
    });

    testWidgets('não mostra nada quando a origem é "app" ou null',
        (tester) async {
      for (final origem in <String?>['app', null]) {
        await tester.pumpWidget(_app(OrigemWhatsAppChip(origem: origem)));
        expect(find.text('WhatsApp'), findsNothing);
        expect(find.byIcon(Icons.chat), findsNothing);
        expect(tester.getSize(find.byType(OrigemWhatsAppChip)), Size.zero);
      }
    });
  });

  group('cartão do parceiro: bloco Cliente', () {
    testWidgets(
        'WhatsApp sem telefone no pedido: etiqueta + telefone de order_origem',
        (tester) async {
      await tester.pumpWidget(_app(const ClienteDoPedido(
        nome: 'Maria',
        origem: kOrigemWhatsApp,
        telefonePedido: '  ',
        telefoneOrigem: '+351912345678',
      )));
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('+351912345678'), findsOneWidget);
    });

    testWidgets('WhatsApp com telefone no pedido: usa o do pedido',
        (tester) async {
      await tester.pumpWidget(_app(const ClienteDoPedido(
        nome: 'Maria',
        origem: kOrigemWhatsApp,
        telefonePedido: '+351911111111',
        telefoneOrigem: '+351912345678',
      )));
      expect(find.text('+351911111111'), findsOneWidget);
      expect(find.text('+351912345678'), findsNothing);
    });

    testWidgets('pedido da app: sem etiqueta e sem telefone em texto',
        (tester) async {
      await tester.pumpWidget(_app(const ClienteDoPedido(
        nome: null,
        origem: kOrigemApp,
        telefonePedido: '+351911111111',
        telefoneOrigem: '+351912345678',
      )));
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Cliente BORA'), findsOneWidget);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('+351911111111'), findsNothing);
      expect(find.text('+351912345678'), findsNothing);
    });
  });

  group('regras puras', () {
    test('rótulo: WhatsApp só para whatsapp, o resto é App', () {
      expect(rotuloOrigem('whatsapp'), 'WhatsApp');
      expect(rotuloOrigem('app'), 'App');
      expect(rotuloOrigem(null), 'App');
    });

    test('telefone: o do pedido manda; senão o de order_origem; senão nada',
        () {
      expect(telefoneDoCliente(doPedido: ' 911 ', daOrigem: '922'), '911');
      expect(telefoneDoCliente(doPedido: '', daOrigem: ' 922 '), '922');
      expect(telefoneDoCliente(doPedido: null, daOrigem: null), isNull);
    });

    test('filtro da lista admin: Todas | App | WhatsApp', () {
      final pedidos = <Map<String, dynamic>>[
        {'id': 'p1'},
        {'id': 'p2'},
        {'id': 'p3'},
      ];
      final origens = <String, PedidoOrigem>{
        'p2': const PedidoOrigem(origem: kOrigemWhatsApp),
        'p3': const PedidoOrigem(origem: kOrigemApp),
      };
      List<Object?> ids(String f) =>
          filtrarPedidosPorOrigem(pedidos, origens, f)
              .map((p) => p['id'])
              .toList();
      expect(ids(kFiltroOrigemTodas), ['p1', 'p2', 'p3']);
      expect(ids(kOrigemWhatsApp), ['p2']);
      // sem linha em order_origem (p1) conta como "App"
      expect(ids(kOrigemApp), ['p1', 'p3']);
      // leitura falhada (null): a lista fica como está, qualquer filtro
      expect(
          filtrarPedidosPorOrigem(pedidos, null, kOrigemWhatsApp), pedidos);
    });
  });

  group('leitura de order_origem', () {
    test('lê em lote só as linhas que existem', () async {
      _origemRows = [
        {'order_id': 'x1', 'origem': 'whatsapp', 'client_phone': '+351900000001'},
        {'order_id': 'x2', 'origem': 'app', 'client_phone': null},
      ];
      final r = await carregarOrigensPedidos(['x1', 'x2', 'x3']);
      expect(r, isNotNull);
      expect(r!.keys.toSet(), {'x1', 'x2'});
      expect(r['x1']!.ehWhatsApp, isTrue);
      expect(r['x1']!.clientPhone, '+351900000001');
      expect(r['x2']!.ehWhatsApp, isFalse);
      expect(_pedidosOrigem, hasLength(1));
      expect(_pedidosOrigem.single.queryParameters['select'],
          'order_id,origem,client_phone');
    });

    test('muitos pedidos vão em lotes de 50 e sem ids repetidos', () async {
      final ids = List.generate(120, (i) => 'id$i');
      final r = await carregarOrigensPedidos([...ids, 'id0']);
      expect(r, isEmpty);
      expect(_pedidosOrigem, hasLength(3));
    });

    test('tabela sem existir / sem permissão: devolve null e não rebenta',
        () async {
      for (final estado in [404, 401, 500]) {
        _origemStatus = estado;
        expect(await carregarOrigensPedidos(['x1']), isNull,
            reason: 'HTTP $estado');
      }
    });

    test('sem ids não vai ao servidor', () async {
      expect(await carregarOrigensPedidos(<String>[]), isEmpty);
      expect(_pedidosOrigem, isEmpty);
    });
  });

  group('lista de pedidos do admin', () {
    testWidgets('mostra "Origem" por pedido (WhatsApp / App) e filtra',
        (tester) async {
      _origemRows = [
        {
          'order_id': 'bbbb2222x',
          'origem': 'whatsapp',
          'client_phone': '+351900000002',
        },
      ];
      await _abreAdmin(tester);

      expect(find.textContaining('ID: '), findsNWidgets(3));
      // uma linha "Origem" por pedido; só o 2.º é WhatsApp, os outros são App
      expect(find.byType(OrigemPedidoLinha), findsNWidgets(3));
      expect(find.byType(OrigemWhatsAppChip), findsOneWidget);
      expect(find.text('App'), findsNWidgets(3)); // 2 linhas + 1 chip do filtro
      expect(find.text('Origem:'), findsOneWidget); // rótulo do filtro

      // o pedido foi pedido a order_origem, em lote, com os 3 ids
      expect(_pedidosOrigem, hasLength(1));
      final in_ = _pedidosOrigem.single.queryParameters['order_id']!;
      expect(in_, allOf(contains('aaaa1111x'), contains('bbbb2222x'),
          contains('cccc3333x')));

      await tester.tap(find.widgetWithText(FilterChip, 'WhatsApp'));
      await tester.pump();
      expect(find.textContaining('ID: '), findsOneWidget);
      expect(find.text('ID: BBBB2222'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'App'));
      await tester.pump();
      expect(find.textContaining('ID: '), findsNWidgets(2));
      expect(find.text('ID: BBBB2222'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Todas'));
      await tester.pump();
      expect(find.textContaining('ID: '), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'se order_origem falhar a lista fica igual a hoje: sem Origem, sem filtro, sem erro',
        (tester) async {
      _origemStatus = 404;
      await _abreAdmin(tester);

      expect(find.textContaining('ID: '), findsNWidgets(3));
      expect(find.byType(OrigemPedidoLinha), findsNothing);
      expect(find.byType(OrigemWhatsAppChip), findsNothing);
      expect(find.text('Origem:'), findsNothing);
      expect(find.textContaining('Erro'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
