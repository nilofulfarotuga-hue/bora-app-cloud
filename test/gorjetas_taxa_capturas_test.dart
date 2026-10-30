// Gorjetas — regra do Danilo de 30/10/2026 (missão gorjetas-taxa-2026-10-30):
// PROVAS VISUAIS. Desenha os ecrãs das gorjetas no flutter tester, com dados
// fixos, e grava um PNG de cada um em
// `.claude/.ai/provas/gorjetas-taxa-2026-10-30/`. Sem emulador, sem login
// verdadeiro, nada em produção: o servidor é um MockClient e o SDK do
// Supabase é o verdadeiro (mesmo método de test/terms_gate_parceiro_test.dart
// e test/gorjetas_taxa_app_test.dart).
//
// As fotos usam o mesmo método dos goldens do repo (test/golden/
// fabrica_de_fotos.dart): RepaintBoundary → toImage → PNG, com a Inter real e
// os ícones do SDK (sem isto o texto sai em blocos). Cada teste TAMBÉM
// confere os textos, não só grava.
//
//  1. gorjetas_recebidas_motorista.png — o widget real
//     GorjetasRecebidasSection, a ler `tips` do servidor de mentira: a gorjeta
//     real de 29/10 (corrida TVDE, depois, MB Way, 2,00 − 0,28 = 1,72) e uma
//     do carrinho (1,50, inteira, só o valor).
//  2. carrinho_gorjeta_junto.png — o CartScreen real, com o interruptor
//     `tips_checkout_junto_pagamento` ligado: linha "Gorjeta", total já com
//     ela e "A gorjeta vai toda para o estafeta.".
//  3. painel_gorjetas_admin.png — o AdminGorjetasScreen real com 3 linhas e
//     os totais.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/screens/admin/admin_gorjetas_screen.dart';
import 'package:bora_app/screens/cart_screen.dart';
import 'package:bora_app/services/tip_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/gorjetas_recebidas_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'golden/fabrica_de_fotos.dart' show carregaFonteInter, carregaFontesSdk;

const _pasta = '.claude/.ai/provas/gorjetas-taxa-2026-10-30';
const _json = {'content-type': 'application/json; charset=utf-8'};
const _uid = '00000000-0000-4000-8000-000000003010';

/// Largura de telemóvel (lógica) e densidade das fotos (nítidas para ler).
const double _largura = 390;
const double _dpr = 3;

/// Interruptores do servidor de mentira: ligados (os dois), como na prova.
const Map<String, Object?> _interruptores = {
  'tips_enabled': true,
  'tips_checkout_junto_pagamento': true,
};

/// O que o servidor devolve a `from('tips')` do prestador (só as colunas que
/// o widget pede).
final List<Map<String, Object?>> _gorjetasDoPrestador = [
  // A gorjeta real de 29/10: corrida TVDE, paga depois, MB Way.
  {
    'id': 'g-2910',
    'amount_cents': 200,
    'liquido_prestador_cents': 172,
    'method': 'mbway',
    'target': 'tvde',
    'paid_at': '2026-10-29T18:00:00+00:00',
    'status': 'succeeded',
  },
  // Gorjeta do carrinho, cobrada junto da compra: inteira.
  {
    'id': 'g-carrinho',
    'amount_cents': 150,
    'liquido_prestador_cents': 150,
    'method': 'card',
    'target': 'order',
    'paid_at': '2026-10-29T12:30:00+00:00',
    'status': 'succeeded',
  },
];

/// O que `admin_listar_gorjetas` devolve (colunas novas incluídas).
final List<Map<String, Object?>> _linhasAdmin = [
  // A de 29/10: depois, MB Way, 2,00 − 0,28 = 1,72; o prestador pagou a taxa.
  {
    'id': 'g-2910',
    'criada_em': '2026-10-29T18:00:00+00:00',
    'alvo': 'tvde',
    'pedido': null,
    'corrida': 'b36ecbb4-0000',
    'cliente_nome': 'Ana',
    'prestador_nome': 'Bruno',
    'valor_cents': 200,
    'metodo': 'mbway',
    'momento': 'after',
    'estado': 'succeeded',
    'taxa_stripe_cents': 28,
    'liquido_prestador_cents': 172,
    'cobrada_junto': false,
    'como_foi_paga': 'depois',
    'quem_pagou_taxa': 'prestador',
    'taxa_descontada_prestador_cents': 28,
    'taxa_por_ler': false,
  },
  // Junto da compra: 1,50, sem taxa à parte, inteira.
  {
    'id': 'g-junto',
    'criada_em': '2026-10-29T12:30:00+00:00',
    'alvo': 'order',
    'pedido': 'abc12345-0000',
    'corrida': null,
    'cliente_nome': 'Marta',
    'prestador_nome': 'Rui',
    'valor_cents': 150,
    'metodo': 'card',
    'momento': 'checkout',
    'estado': 'succeeded',
    'taxa_stripe_cents': null,
    'liquido_prestador_cents': 150,
    'cobrada_junto': true,
    'como_foi_paga': 'junto_da_compra',
    'quem_pagou_taxa': 'nenhuma',
    'taxa_descontada_prestador_cents': 0,
    'taxa_por_ler': false,
  },
  // Em dinheiro: 1,00, entregue em mão.
  {
    'id': 'g-dinheiro',
    'criada_em': '2026-10-28T19:10:00+00:00',
    'alvo': 'order',
    'pedido': 'def67890-0000',
    'corrida': null,
    'cliente_nome': 'Paulo',
    'prestador_nome': 'Rui',
    'valor_cents': 100,
    'metodo': 'cash',
    'momento': 'checkout',
    'estado': 'cash_collected',
    'taxa_stripe_cents': null,
    'liquido_prestador_cents': 100,
    'cobrada_junto': false,
    'como_foi_paga': 'dinheiro',
    'quem_pagou_taxa': 'nenhuma',
    'taxa_descontada_prestador_cents': 0,
    'taxa_por_ler': false,
  },
];

/// Cada pedido que chegou ao servidor de mentira ("MÉTODO /caminho").
final List<String> _pedidos = [];

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

Map<String, Object?> _sessao() {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return {
    'access_token': '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${_b64({'sub': _uid, 'exp': exp, 'role': 'authenticated'})}.assinatura',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-de-teste',
    'user': {
      'id': _uid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'gorjetas.capturas@bora.app',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-10-30T00:00:00Z',
    },
  };
}

http.Response _ok(http.Request req, Object? corpo) =>
    http.Response(jsonEncode(corpo), 200, headers: _json, request: req);

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  _pedidos.add('${req.method} $caminho');
  if (caminho.endsWith('/auth/v1/token')) return _ok(req, _sessao());
  if (caminho.endsWith('/rest/v1/rpc/get_setting')) {
    final chave = (jsonDecode(req.body) as Map)['p_key'];
    return _ok(req, _interruptores[chave]);
  }
  if (caminho.endsWith('/rest/v1/rpc/admin_listar_gorjetas')) {
    return _ok(req, _linhasAdmin);
  }
  if (caminho.endsWith('/rest/v1/tips')) return _ok(req, _gorjetasDoPrestador);
  return _ok(req, const []);
}

/// O cliente do Supabase acaba as respostas fora do relógio falso do teste.
Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Ecrã de telemóvel: 390 px de largura lógica, [altura] lógica, densidade 3.
void _telemovel(WidgetTester t, {double altura = 844}) {
  t.view.physicalSize = Size(_largura * _dpr, altura * _dpr);
  t.view.devicePixelRatio = _dpr;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

final _chaveFoto = GlobalKey();

/// O tema real da app. Única diferença: o título da barra de cima (que no tema
/// tem `fontFamily: null`, e no flutter test cai em blocos) passa a Inter, como
/// a fábrica de fotos já fez com os botões (`kHarnessVersion` v3).
ThemeData _tema() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle:
          base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Inter'),
    ),
  );
}

/// Envolve o ecrã com o tema real, como a fábrica de fotos dos goldens.
Widget _quadro(Widget home, {List<SingleChildWidget> providers = const []}) {
  final app = RepaintBoundary(
    key: _chaveFoto,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _tema(),
      home: home,
    ),
  );
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}

/// Grava o PNG da foto e confere que existe, é PNG e não está vazio.
Future<int> _grava(WidgetTester tester, String ficheiro) async {
  final boundary =
      _chaveFoto.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_pasta);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('$_pasta/$ficheiro').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  final f = File('$_pasta/$ficheiro');
  expect(f.existsSync(), isTrue, reason: '$ficheiro não foi gravado');
  final b = f.readAsBytesSync();
  expect(b.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: '$ficheiro não é PNG');
  expect(b.length, greaterThan(20000),
      reason: '$ficheiro saiu quase vazio (${b.length} bytes)');
  return b.length;
}

/// Desmonta e deixa correr o que ficou agendado (temporizadores do carrinho e
/// das lojas), como fazem os outros testes que montam estas lojas.
Future<void> _arrumar(WidgetTester t) async {
  await t.pump(const Duration(seconds: 10));
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(minutes: 5));
  t.takeException();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // A Inter real e os ícones do SDK: sem isto o flutter test desenha blocos.
    await carregaFonteInter();
    await carregaFontesSdk();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
    await Supabase.instance.client.auth
        .signInWithPassword(email: 'gorjetas.capturas@bora.app', password: 'x');
  });

  setUp(_pedidos.clear);

  // ── 1. O que o motorista vê ──────────────────────────────────────────────
  testWidgets('gorjetas_recebidas_motorista.png — taxa de 0,28 € e líquido 1,72 €',
      (tester) async {
    expect(Supabase.instance.client.auth.currentUser?.id, _uid);
    _telemovel(tester, altura: 260);
    await tester.pumpWidget(_quadro(Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [GorjetasRecebidasSection()],
        ),
      ),
    )));
    await _servidorResponde(tester);

    // O widget leu `tips` do servidor de mentira (não de um texto à mão).
    expect(_pedidos.where((p) => p.endsWith('/rest/v1/tips')), hasLength(1));

    // A linha da gorjeta real de 29/10, frase por frase.
    expect(
        find.text('Gorjeta 2,00 € · taxa do pagamento −0,28 € · recebes 1,72 €'),
        findsOneWidget);
    expect(find.text('Gorjeta · corrida · MB WAY'), findsOneWidget);
    expect(find.text('1,72 €'), findsOneWidget, reason: 'o que ele recebe');
    // A do carrinho: só o valor, sem frase de taxa.
    expect(find.text('Gorjeta · entrega · cartão'), findsOneWidget);
    expect(find.text('1,50 €'), findsOneWidget);
    expect(find.textContaining('−0,28 €'), findsOneWidget,
        reason: 'só a gorjeta paga depois tem taxa');
    expect(find.textContaining('recebes'), findsOneWidget);
    // O total soma o que ele recebe (1,72 + 1,50), não o bruto (3,50).
    expect(find.text('Gorjetas (últimos 30 dias)'), findsOneWidget);
    expect(find.text('3,22 €'), findsOneWidget);
    expect(find.text('3,50 €'), findsNothing);
    expect(tester.takeException(), isNull);

    final bytes = await _grava(tester, 'gorjetas_recebidas_motorista.png');
    // ignore: avoid_print
    print('gorjetas_recebidas_motorista.png: $bytes bytes');
    await _arrumar(tester);
  });

  // ── 2. O carrinho com a gorjeta junto da compra ──────────────────────────
  testWidgets('carrinho_gorjeta_junto.png — linha Gorjeta, total com ela e o texto',
      (tester) async {
    _telemovel(tester);
    // O mesmo carrinho de test/carrinho_um_so_total_test.dart: 2,89 € + taxa
    // 0,99 + entrega 2,50 + saco 0,10 + pedido pequeno 1,39 = 7,87 €.
    final cart = CartStore()
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
    cart.chamarQuoteParaTeste = (_) async => {
          'service_type': cart.serviceType.name,
          'subtotal': cart.subtotal,
          'service_fee': 0.99,
          'delivery_fee': 2.50,
          'bag_fee': 0.10,
          'apartment_surcharge': 0,
          'small_order_fee': 1.39,
          'customer_total': 7.87,
        };
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await cart.quoteOrderPricing();
    cart.setTipCents(200); // o cliente escolheu 2,00 €
    // A cotação e o resumo continuam SEM a gorjeta (ela só se soma ao ecrã).
    expect(cart.resumo.total, 7.87);

    await tester.pumpWidget(_quadro(const CartScreen(), providers: [
      ChangeNotifierProvider<CartStore>.value(value: cart),
      ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
    ]));
    await _servidorResponde(tester);

    // O interruptor foi lido do servidor de mentira, as duas chaves.
    expect(_pedidos.where((p) => p.endsWith('/rest/v1/rpc/get_setting')).length,
        greaterThanOrEqualTo(2));
    expect(TipService.textoDoCarrinho(vaiJunto: true),
        'A gorjeta vai toda para o estafeta.');
    expect(find.text('Carrinho'), findsOneWidget, reason: 'título do ecrã legível');
    // O painel do pagamento rola: leva o fim (Gorjeta + Total) ao ecrã.
    final fim = find.text('Total a pagar');
    expect(fim, findsOneWidget);
    await tester.ensureVisible(fim);
    await tester.pump(const Duration(milliseconds: 400));

    // Texto sob o seletor: a versão "junto" (e não a "cobrada à parte").
    expect(find.text('A gorjeta vai toda para o estafeta.'), findsOneWidget);
    expect(find.textContaining('cobrada à parte'), findsNothing);
    // A linha "Gorjeta" com os 2,00 € e o total já com ela: 7,87 + 2,00.
    expect(find.text('Gorjeta'), findsOneWidget);
    expect(find.text('2,00 €'), findsOneWidget);
    expect(find.text('9,87 €'), findsOneWidget, reason: 'Total a pagar com a gorjeta');
    expect(find.text('7,87 €'), findsNothing,
        reason: 'o total sem a gorjeta não pode ficar no ecrã');
    expect(tester.takeException(), isNull);

    final bytes = await _grava(tester, 'carrinho_gorjeta_junto.png');
    // ignore: avoid_print
    print('carrinho_gorjeta_junto.png: $bytes bytes');
    await _arrumar(tester);
  });

  // ── 3. O painel admin ────────────────────────────────────────────────────
  testWidgets('painel_gorjetas_admin.png — 3 linhas e os totais', (tester) async {
    _telemovel(tester, altura: 930);
    await tester.pumpWidget(_quadro(const AdminGorjetasScreen()));
    await _servidorResponde(tester);

    expect(_pedidos.where((p) => p.endsWith('/rest/v1/rpc/admin_listar_gorjetas')),
        hasLength(1));
    // Interruptores lidos do servidor: os dois ligados.
    final interruptores =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(interruptores.map((s) => s.value), [true, true]);
    expect(find.text('Gorjeta do carrinho junto com a compra'), findsOneWidget);
    expect(find.text('Gorjetas'), findsOneWidget, reason: 'título do ecrã legível');

    // Totais do período: 3 pagas, 4,50 € dadas, 4,22 € líquidos, taxa 0,28 €.
    expect(find.textContaining('3 gorjetas pagas · € 4.50'), findsOneWidget);
    expect(find.text('Líquido para os prestadores: € 4.22'), findsOneWidget);
    expect(
        find.textContaining(
            'descontadas aos prestadores (gorjetas pagas depois): € 0.28'),
        findsOneWidget);
    expect(find.textContaining('pagas pela Bora (gorjetas à parte no carrinho): € 0.00'),
        findsOneWidget);
    expect(find.textContaining('A Bora não ganha nada com gorjetas'), findsOneWidget);

    // A linha de 29/10: depois, MB Way, 2,00, taxa 0,28 paga pelo prestador.
    expect(find.text('€ 2.00 · Ana → Bruno'), findsOneWidget);
    expect(find.textContaining('Corrida b36ecbb4 · MB Way · depois (na avaliação) · paga'),
        findsOneWidget);
    expect(
        find.textContaining('Taxa da Stripe € 0.28, paga pelo prestador'),
        findsOneWidget);
    expect(find.textContaining('líquido para o prestador € 1.72'), findsOneWidget);
    // Junto da compra: 1,50, sem taxa, inteira.
    expect(find.text('€ 1.50 · Marta → Rui'), findsOneWidget);
    expect(find.textContaining('junto da compra (um pagamento só)'), findsOneWidget);
    expect(find.textContaining('Sem taxa à parte · líquido para o prestador € 1.50 (inteira)'),
        findsOneWidget);
    // Em dinheiro: 1,00.
    expect(find.text('€ 1.00 · Paulo → Rui'), findsOneWidget);
    expect(find.textContaining(' · dinheiro · em dinheiro (entregue)'), findsOneWidget);
    expect(find.textContaining('em dinheiro · em dinheiro'), findsNothing);
    expect(find.textContaining('Sem taxa à parte · líquido para o prestador € 1.00 (inteira)'),
        findsOneWidget);
    // Só as pagas por cartão/MB Way se reembolsam (a de dinheiro não tem botão).
    expect(find.text('Reembolsar'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final bytes = await _grava(tester, 'painel_gorjetas_admin.png');
    // ignore: avoid_print
    print('painel_gorjetas_admin.png: $bytes bytes');
    await _arrumar(tester);
  });
}
