// CARRINHO: A FRASE "FALTAM X € PARA…" SÓ APARECE UMA VEZ.
//
// Achado a 28/10/2026 no emulador: o carrinho mostrava duas linhas iguais —
// "Faltam X € para evitar a taxa de pedido pequeno" (resumo) e, mais abaixo,
// a mesma frase como subtítulo da tira "Juntar mais". Ficou a do resumo (é a
// que aparece sempre, com a tira ligada ou não, e diz também o mínimo da taxa
// quando falta mais do que uma coisa). A tira ficou só com o título e os
// produtos para juntar.
//
// Este teste monta a tira de verdade (CartStore real, lojas e produtos vindos
// de um servidor de brincar) e prova duas coisas: a tira APARECE e NÃO escreve
// "Faltam".
import 'dart:convert';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/services/small_order_fee.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/juntar_mais_tira.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _loja = 'loja-juntar-mais';

http.Response _json(http.Request req, Object corpo) => http.Response(
      jsonEncode(corpo),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _produto(String id, String nome, double preco) => {
      'id': id,
      'restaurant_id': _loja,
      'name': nome,
      'price': preco,
      'is_available': true,
      'category': 'Bebidas',
    };

CartStore _carrinho(double precoDoPrato) {
  final cart = CartStore()
    ..configureSession(
      serviceType: OrderServiceType.restaurant,
      isPartnerStore: true,
      vendorName: 'Loja de teste',
      vendorRestaurantId: _loja,
    );
  cart.addItem(CartItem(
    productId: 'prato-no-carrinho',
    name: 'Prato',
    price: precoDoPrato,
    basePrice: precoDoPrato,
  ));
  return cart;
}

Future<void> _montar(WidgetTester t, CartStore cart) async {
  t.view.physicalSize = const Size(2600, 2400); // ~1000 px lógicos: cabem os 3 cartões
  t.view.devicePixelRatio = 2.6;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CartStore>.value(value: cart),
      ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: JuntarMaisTira())),
    ),
  ));
  // O catálogo chega do servidor de brincar em tempo real, fora do relógio do
  // teste: espera (no máximo 3 s) até a tira ter produtos para mostrar.
  final alvo = find.byKey(const Key('tira_juntar_mais'));
  for (var i = 0; i < 30 && alvo.evaluate().isEmpty; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 300));
}

/// Desmonta e deixa correr o que ficou agendado (lojas em tempo real), como
/// fazem os outros testes que montam o RestaurantStore.
Future<void> _arrumar(WidgetTester t) async {
  await t.pump(const Duration(seconds: 10));
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(minutes: 5));
  t.takeException();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async {
        switch (req.url.path) {
          case '/rest/v1/restaurants':
            return _json(req, [
              {
                'id': _loja,
                'name': 'Loja de teste',
                'is_partner': true,
                'category': 'restaurant',
                'approval_status': 'approved',
                'is_active_admin': true,
                // Entrega grátis a partir de 30 €. Tem de vir daqui: o
                // CartStore volta a ler esta coluna ao configurar a sessão e
                // apagava o valor posto à mão pelo teste.
                'free_delivery_min_cents': 3000,
              }
            ]);
          case '/rest/v1/products':
            return _json(req, [
              _produto('p-agua', 'Água', 1.0),
              _produto('p-sumo', 'Sumo', 1.5),
              _produto('p-cafe', 'Café', 2.0),
              _produto('p-vinho', 'Vinho', 9.0),
            ]);
          default:
            return _json(req, const []);
        }
      }),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BoraLang.notifier.value = AppLang.pt;
    InterruptoresApp.instance
        .definirParaTeste({InterruptoresApp.juntarMais: true});
    // Entrega grátis a partir de 30 €.
    SmallOrderFeeService.definirEntregaGratisParaTeste(_loja, 3000);
  });

  tearDown(() => SmallOrderFeeService.definirEntregaGratisParaTeste(_loja, null));

  testWidgets(
      'falta para a entrega grátis: a tira aparece com os 3 mais baratos e '
      'sem a frase "Faltam…"', (t) async {
    final cart = _carrinho(10);
    expect(cart.faltaParaEntregaGratis, 20,
        reason: 'o cenário precisa de faltar dinheiro para a entrega grátis');

    await _montar(t, cart);

    expect(find.byKey(const Key('tira_juntar_mais')), findsOneWidget,
        reason: 'sem a tira este teste não provava nada');
    expect(find.text('Juntar mais'), findsOneWidget);
    expect(find.byKey(const Key('juntar_p-agua')), findsOneWidget);
    expect(find.byKey(const Key('juntar_p-sumo')), findsOneWidget);
    expect(find.byKey(const Key('juntar_p-cafe')), findsOneWidget);
    expect(find.byKey(const Key('juntar_p-vinho')), findsNothing);
    expect(find.textContaining('Faltam'), findsNothing);
    expect(find.textContaining('entrega grátis'), findsNothing);
    expect(t.takeException(), isNull);
    await _arrumar(t);
  });

  testWidgets('já chega à entrega grátis: a tira desaparece', (t) async {
    final cart = _carrinho(35);
    expect(cart.faltaParaEntregaGratis, 0);

    await _montar(t, cart);

    expect(find.byKey(const Key('tira_juntar_mais')), findsNothing);
    expect(find.textContaining('Faltam'), findsNothing);
    expect(t.takeException(), isNull);
    await _arrumar(t);
  });
}
