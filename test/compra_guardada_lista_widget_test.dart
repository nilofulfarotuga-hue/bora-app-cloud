// Compra guardada (14/11/2026, pedido b2b746d7 · Auchan) — o cenário real no
// ecrã: o estafeta marca a compra, a app troca de pedido/fecha/rebenta, e ao
// reabrir a lista está tudo como estava. O "servidor" é um falso em memória que
// responde às RPCs estafeta_guardar/ler_progresso_compra como a migração.

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

/// A linha de order_purchase_drafts do servidor falso.
Map<String, dynamic>? _linhaServidor;
int _gravacoes = 0;

http.Response _json(Object? corpo, http.Request req) => http.Response(
      jsonEncode(corpo),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// estafeta_guardar_progresso_compra do servidor falso (mesmas regras da
/// migração: seq atrasado ignorado, null = manter o que lá está).
Future<Map<String, dynamic>> _servidorGuardar(Map<String, dynamic> b) async {
  // ida e volta pelo JSON, como na rede
  b = jsonDecode(jsonEncode(b)) as Map<String, dynamic>;
  final seq = b['p_seq'] as int;
  final atual = _linhaServidor;
  if (atual != null && (atual['client_seq'] as int) > seq) {
    return {'ok': true, 'applied': false, 'stale': true};
  }
  _gravacoes++;
  _linhaServidor = {
    'order_id': b['p_order_id'],
    'itens': b['p_itens'] ?? atual?['itens'] ?? {},
    'extras': b['p_extras'] ?? atual?['extras'] ?? [],
    'bag_count': b['p_sacos'] ?? atual?['bag_count'],
    'receipt_total_cents': b['p_total_talao_cents'] ?? atual?['receipt_total_cents'],
    'receipt_photo_path': b['p_foto_url'] ?? atual?['receipt_photo_path'],
    'client_seq': seq,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
  return {'ok': true, 'applied': true, 'seq': seq};
}

Future<Object?> _servidorLer(String orderId) async =>
    {'ok': true, 'finalized': false, 'rascunho': _linhaServidor};

// Fotos do catálogo, NIF, peso variável…: nada a mostrar.
Future<http.Response> _responder(http.Request req) async =>
    _json(req.url.path.contains('/rpc/') ? null : [], req);

OrderModel _pedidoAuchan() => OrderModel.fromSupabase({
      'id': 'b2b746d7-teste',
      'status': 'driverAccepted',
      'service_type': 'storeShopping',
      'is_partner_store': false,
      'payment_method': 'cash',
      'price': 30,
      'vendor_name': 'Auchan',
      'customer_name': 'Cliente Teste',
      'bag_count': 1,
      'items': [
        {'productId': 'p-pizza', 'name': 'Pizza 4 queijos', 'price': 3.45, 'quantity': 2},
        {'productId': 'p-queijo', 'name': 'Queijo ralado', 'price': 1.15, 'quantity': 1},
        {'productId': 'p-leite', 'name': 'Leite meio-gordo', 'price': 0.92, 'quantity': 6},
      ],
    });

/// Alguns cartões (NIF, fotos) ficam a carregar contra o servidor falso: o
/// pumpAndSettle nunca assentaria. Uns quantos desenhos chegam.
Future<void> _assentar(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _abrirLista(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: listaDeComprasParaTeste(_pedidoAuchan())),
  ));
  await _assentar(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async => _responder(req)),
    );
  });

  setUp(() {
    _linhaServidor = null;
    _gravacoes = 0;
    // cada teste começa com o telemóvel vazio (a cópia do teste anterior
    // reporia a lista — é o comportamento certo, mas não o que se testa aqui)
    SharedPreferences.setMockInitialValues({});
    CompraRascunhoService.limparParaTeste();
    CompraRascunhoService.enviarParaTeste = _servidorGuardar;
    CompraRascunhoService.lerParaTeste = _servidorLer;
  });

  testWidgets(
      'marca a compra, a app fecha a meio, reabre: tudo como estava (servidor)',
      (t) async {
    t.view.physicalSize = const Size(1080, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _abrirLista(t);
    expect(find.text('0 de 3 comprados'), findsOneWidget);

    // Pizzas: "Não há" (vai trocar); queijo: "Não há"; leite: comprado.
    await t.tap(find.text('Não há').first); // pizza
    await _assentar(t);
    await t.tap(find.text('Não há').first); // queijo (a pizza já não tem botões)
    await _assentar(t);
    await t.tap(find.text('Comprado').first); // leite
    await _assentar(t);
    // sacos: 1 → 2
    await t.tap(find.byIcon(Icons.add_circle_outline).last);
    await _assentar(t);

    expect(find.text('1 de 3 comprados'), findsOneWidget);
    expect(find.text('Guardado'), findsOneWidget,
        reason: 'o estafeta vê que ficou guardado');
    expect(_gravacoes, greaterThanOrEqualTo(4));
    final itens = _linhaServidor!['itens'] as Map;
    expect(itens['p-pizza#0'], {'s': 'unavailable', 'q': 2});
    expect(itens['p-queijo#0'], {'s': 'unavailable', 'q': 1});
    expect(itens['p-leite#0'], {'s': 'bought', 'q': 6});
    expect(_linhaServidor!['bag_count'], 2);

    // A app "morre": a folha desaparece, a memória e o telemóvel são limpos —
    // só o servidor sabe o que foi marcado.
    await t.pumpWidget(const SizedBox.shrink());
    CompraRascunhoService.limparParaTeste();
    SharedPreferences.setMockInitialValues({});

    await _abrirLista(t);
    expect(find.text('1 de 3 comprados'), findsOneWidget,
        reason: 'reabriu com o leite comprado');
    expect(find.text('Comprado'), findsNothing,
        reason: 'os 3 itens já estão decididos: não há botões por marcar');
    expect(find.text('2'), findsWidgets); // os 2 sacos voltaram
    expect(find.text('Confirmar compra'), findsOneWidget,
        reason: 'tudo decidido: pode fechar o talão sem refazer nada');
  });

  testWidgets('sem rede: fica no telemóvel e reabre igual', (t) async {
    t.view.physicalSize = const Size(1080, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    CompraRascunhoService.enviarParaTeste =
        (p) async => throw Exception('sem rede');

    await _abrirLista(t);
    await t.tap(find.text('Comprado').first); // pizza
    await t.pump();
    await t.pump(const Duration(seconds: 12)); // 3 tentativas falhadas
    expect(find.text('Guardado no telemóvel · envia com rede'), findsOneWidget);

    // Trocou de pedido (a folha fechou) e voltou: memória limpa, telemóvel não.
    await t.pumpWidget(const SizedBox.shrink());
    CompraRascunhoService.limparParaTeste();
    CompraRascunhoService.enviarParaTeste =
        (p) async => throw Exception('sem rede');
    CompraRascunhoService.lerParaTeste = _servidorLer;
    await _abrirLista(t);
    expect(find.text('1 de 3 comprados'), findsOneWidget);
    expect(_linhaServidor, isNull, reason: 'nada chegou ao servidor');
    // ao reabrir voltou a tentar sozinho (3 tentativas); depois fica marcada a
    // seguinte (30 s), que se cancela para não ficar pendurada no fim do teste
    await t.pump(const Duration(seconds: 12));
    expect(find.text('Guardado no telemóvel · envia com rede'), findsOneWidget);
    CompraRascunhoService.limparParaTeste();
  });
}
