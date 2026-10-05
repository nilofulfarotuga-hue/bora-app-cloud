// HOME: TOCAR NUMA FAIXA ABRE A PÁGINA CERTA E CONTA O CLIQUE.
//
// Prova da missão fecho-home-dinheiro-2026-10-05 (B4). As faixas e os
// destinos são os que estão no banco a 05/10/2026 (`home_banners`):
// "Sushi na Guarda" → cozinha `sushi`; "Novidade: Natur House" → loja
// `naturhouse-guarda`. A vista conta uma vez, o clique conta sempre, pela
// função `banner_evento` do servidor. E a lupa: "hamburguer" sem acento cai
// na cozinha hambúrguer, que junta as lojas "Fast Food".
import 'dart:convert';

import 'package:bora_app/screens/restaurants_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/favorite_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/utils/cozinhas.dart';
import 'package:bora_app/widgets/home/home_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _sushiId = '11111111-1111-1111-1111-111111111111';
const _naturId = '9799d7b7-1787-4242-b068-8462398b6050';

final _faixas = [
  {
    'id': _sushiId,
    'titulo': 'Sushi na Guarda',
    'subtitulo': 'Fuku, Jyosmi e Amaya — peça já',
    'imagem_url': null,
    'cor_inicio': '#16A34A',
    'cor_fim': '#22C55E',
    'tipo_destino': 'cozinha',
    'destino': 'sushi',
    'ordem': 20,
    'ativo': true,
  },
  {
    'id': _naturId,
    'titulo': 'Novidade: Natur House',
    'subtitulo': 'Reeducação alimentar e suplementos',
    'imagem_url': null,
    'cor_inicio': '#16A34A',
    'cor_fim': '#22C55E',
    'tipo_destino': 'loja',
    'destino': 'naturhouse-guarda',
    'ordem': 30,
    'ativo': true,
  },
];

/// O que a app mandou para `banner_evento` (p_banner, p_tipo).
final List<Map<String, dynamic>> _eventos = [];

/// Rotas abertas por cima da home.
class _Rotas extends NavigatorObserver {
  final abertas = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      abertas.add(route);
}

Future<_Rotas> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rotas = _Rotas();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
      ChangeNotifierProvider<CartStore>(create: (_) => CartStore()),
      ChangeNotifierProvider<FavoriteStore>(create: (_) => FavoriteStore()),
    ],
    child: MaterialApp(
      navigatorObservers: [rotas],
      home: const Scaffold(
        body: HomeBannerCarousel(fallback: Text('banner antigo')),
      ),
    ),
  ));
  // As faixas chegam do servidor de brincar (pedido em tempo real).
  for (var i = 0; i < 30 && find.text('Sushi na Guarda').evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  return rotas;
}

Future<void> _esperarEventos(WidgetTester tester, int n) async {
  for (var i = 0; i < 30 && _eventos.length < n; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

Future<void> _arrumar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 5));
  tester.takeException();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      httpClient: MockClient((req) async {
        final caminho = req.url.path;
        var corpo = '[]';
        if (caminho.endsWith('/home_banners')) {
          corpo = jsonEncode(_faixas);
        } else if (caminho.endsWith('/rpc/banner_evento')) {
          _eventos.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
          corpo = 'null';
        }
        return http.Response(corpo, 200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _eventos.clear();
  });

  testWidgets('faixa de Sushi abre os restaurantes de sushi e conta o clique',
      (tester) async {
    final rotas = await _montar(tester);
    expect(find.text('Sushi na Guarda'), findsOneWidget);

    await tester.tap(find.text('Sushi na Guarda'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Abriu a lista de restaurantes filtrada pela cozinha "sushi".
    expect(rotas.abertas, hasLength(2)); // a home + a de sushi
    expect(
        find.byWidgetPredicate(
            (w) => w is RestaurantsScreen && w.cozinha == 'sushi'),
        findsOneWidget);

    // Vista da primeira faixa + clique na de Sushi, pela função do servidor.
    await _esperarEventos(tester, 2);
    expect(_eventos, anyElement(equals({'p_banner': _sushiId, 'p_tipo': 'view'})));
    expect(_eventos, anyElement(equals({'p_banner': _sushiId, 'p_tipo': 'click'})));
    await _arrumar(tester);
  });

  testWidgets('faixa de loja procura a loja pelo id do destino',
      (tester) async {
    final rotas = await _montar(tester);
    // Passa para a segunda faixa (Natur House) como o cliente faria.
    await tester.drag(find.text('Sushi na Guarda'), const Offset(-600, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Novidade: Natur House'), findsOneWidget);

    await tester.tap(find.text('Novidade: Natur House'));
    // O servidor de brincar não tem a loja: a app avisa em vez de abrir
    // uma página vazia (no banco real ela existe e está ligada).
    for (var i = 0;
        i < 30 &&
            find.text('Esta loja não está disponível de momento.')
                .evaluate()
                .isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Esta loja não está disponível de momento.'),
        findsOneWidget);
    expect(rotas.abertas, hasLength(1)); // nenhuma página nova

    // A vista da de Sushi já contou no teste anterior (uma vez por sessão).
    await _esperarEventos(tester, 2);
    expect(_eventos, anyElement(equals({'p_banner': _naturId, 'p_tipo': 'view'})));
    expect(_eventos, anyElement(equals({'p_banner': _naturId, 'p_tipo': 'click'})));
    await _arrumar(tester);
  });

  test('lupa: "hamburguer" sem acento acha a cozinha e as lojas Fast Food', () {
    expect(cozinhaDaPesquisa('hamburguer'), 'hamburguer');
    expect(cozinhaDaPesquisa('Hambúrguer'), 'hamburguer');
    expect(cozinhaDaPesquisa('hamburg'), 'hamburguer');
    // As três lojas do banco com 'Fast Food' entram pela cozinha.
    expect(cozinhaChaves('Fast Food'), contains('hamburguer'));
    expect(cozinhaChaves('Sushi · Japonesa'), contains('sushi'));
  });
}
