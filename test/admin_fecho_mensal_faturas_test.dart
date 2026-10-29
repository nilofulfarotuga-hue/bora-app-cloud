import 'dart:convert';

import 'package:bora_app/screens/admin/admin_fecho_mensal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// missao-geral-2026-10-28, H2/N4 — "Fecho do mês" do painel, parte das
/// faturas da Bora. Servidor falso (MockClient) com o SDK verdadeiro.
/// Prova no ecrã:
///  1. a nota do IVA aparece e vem do servidor (texto do admin_monthly_closeout);
///  2. "Faturas uma a uma" mostra nome da fatura, NIF, a taxa de cancelamento
///     e deixa de fora a linha sem valor;
///  3. escolher a semana 26/10 a 01/11 vai buscar também novembro e fica só
///     com as faturas de segunda a domingo.
/// Dados inventados.

const _json = {'content-type': 'application/json; charset=utf-8'};
const _fraseIva =
    'IVA: até outubro de 2026, isenção do art. 53.º do CIVA (M10); a partir de novembro de 2026, regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.';

final List<Map<String, dynamic>> _rpc = [];

Map<String, Object?> _linha(String id, String data, num valor,
        {String? nif, String nome = 'Consumidor final', String estado = 'por_lancar', String desc = 'Taxa de serviço e intermediação — plataforma Bora'}) =>
    {
      'id': id,
      'order_id': 'pedido-$id-teste',
      'data': data,
      'valor': valor,
      'cliente_nif': nif,
      'cliente_nome': nome,
      'iva': null,
      'descricao': desc,
      'estado': estado,
      'created_at': '${data}T12:00:00Z',
    };

final _outubro = [
  _linha('o1', '2026-10-20', 3.62, nif: '123456789', nome: 'Cliente Teste Lda'),
  _linha('o2', '2026-10-27', 2.5, desc: 'Taxa de cancelamento — plataforma Bora'),
  _linha('o3', '2026-10-30', 0, estado: 'sem_valor'),
  _linha('o4', '2026-10-31', 1.0),
];
final _novembro = [
  _linha('n1', '2026-11-01', 2.0),
  _linha('n2', '2026-11-02', 4.0),
];

Future<http.Response> _servidor(http.Request req) async {
  final p = req.url.path;
  Map<String, dynamic> corpo() =>
      req.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(req.body) as Map);
  http.Response ok(Object? o) =>
      http.Response(jsonEncode(o), 200, headers: _json, request: req);
  if (p.endsWith('/rpc/admin_monthly_closeout')) {
    _rpc.add({'rpc': 'admin_monthly_closeout', ...corpo()});
    return ok({
      'totais': {'pedidos_entregues': 4},
      'para_as_financas': {
        'regime': 'simplificado; IVA isento art. 53.º CIVA (M10)',
        'rubricas': <String, Object?>{},
        'total_a_declarar': 10.0,
        'faturas_recibo': <Object?>[],
        'texto': 'Receita própria da Bora em outubro de 2026: 10.00 €. $_fraseIva',
      },
      'parceiros': <Object?>[],
      'estafetas': <Object?>[],
      'pedidos_no_prejuizo': <Object?>[],
      'servicos': <Object?>[],
    });
  }
  if (p.endsWith('/rpc/driver_monthly_invoice_summary')) {
    return ok({'estafetas': <Object?>[]});
  }
  if (p.endsWith('/rpc/admin_bora_invoices_month')) {
    final c = corpo();
    _rpc.add({'rpc': 'admin_bora_invoices_month', ...c});
    final linhas = c['p_month'] == 11 ? _novembro : _outubro;
    return ok({
      'linhas': linhas,
      'por_dia': [
        {'data': '2026-10-20', 'documentos': 1, 'total': 3.62, 'por_lancar': 1},
      ],
      'nota': 'Uma fatura por linha, com o NIF quando houver.',
    });
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

Future<void> _abrir(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
      home: AdminFechoMensalScreen(mesInicial: '2026-10')));
  await _servidorResponde(tester);
}

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

  setUp(_rpc.clear);

  testWidgets('a nota do IVA aparece e é a do servidor', (tester) async {
    await _abrir(tester);
    expect(_rpc.where((c) => c['rpc'] == 'admin_monthly_closeout'), hasLength(1));
    final nota = find.byKey(const ValueKey('fecho_nota_iva'));
    expect(nota, findsOneWidget);
    expect(find.descendant(of: nota, matching: find.text(_fraseIva)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('faturas uma a uma: nome, NIF, cancelamento, sem a de valor 0',
      (tester) async {
    await _abrir(tester);
    expect(find.text('Faturas uma a uma (3)'), findsOneWidget);
    await tester.tap(find.text('Faturas uma a uma (3)'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-20 · pedido pedido-o · Cliente Teste Lda'),
        findsOneWidget);
    expect(find.textContaining('NIF 123456789'), findsOneWidget);
    expect(find.textContaining('Taxa de cancelamento'), findsOneWidget);
    expect(find.textContaining('sem NIF (consumidor final)'), findsNWidgets(2));
    expect(find.textContaining('2026-10-30'), findsNothing);
  });

  testWidgets('semana 26/10 a 01/11: busca novembro e fica com seg..dom',
      (tester) async {
    await _abrir(tester);
    expect(find.text('Semana: mês inteiro'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('faturas_semana')));
    await tester.pumpAndSettle();
    expect(find.text('Semana de 28/09 a 04/10'), findsOneWidget);
    expect(find.text('Semana de 26/10 a 01/11'), findsOneWidget);
    await tester.tap(find.text('Semana de 26/10 a 01/11'));
    await tester.pump();
    await _servidorResponde(tester);
    await tester.pumpAndSettle();

    final mesesPedidos = _rpc
        .where((c) => c['rpc'] == 'admin_bora_invoices_month')
        .map((c) => c['p_month'])
        .toList();
    expect(mesesPedidos, [10, 11]);
    expect(find.text('Semana: 26/10 a 01/11'), findsOneWidget);
    // 27/10 (cancelamento), 31/10 e 01/11; fora: 20/10, 02/11 e a de valor 0.
    expect(find.text('Faturas uma a uma (3)'), findsOneWidget);
    await tester.tap(find.text('Faturas uma a uma (3)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-27 · pedido'), findsOneWidget);
    expect(find.textContaining('2026-10-31 · pedido'), findsOneWidget);
    expect(find.textContaining('2026-11-01 · pedido'), findsOneWidget);
    expect(find.textContaining('2026-11-02'), findsNothing);
    expect(find.textContaining('2026-10-20 · pedido'), findsNothing);
    expect(find.textContaining('escolha "mês inteiro"'), findsOneWidget);
  });
}
