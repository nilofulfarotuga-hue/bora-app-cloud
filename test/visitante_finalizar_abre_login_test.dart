// B3 (missão app-fechar-2026-11-01) — COMPRA SEM CONTA.
//
// G1: o toque REAL no "Finalizar pedido" do visitante abre "Entrar ou criar
// conta". Cicatriz de 26/10: `garantirContactoDoCliente` devolvia false em
// silêncio e o botão "não fazia nada". O conserto de 28/10 (6f9e2d4) só tinha
// um teste de texto; este monta o CartScreen verdadeiro e toca no botão.
//
// G4: com a loja fechada e o agendamento ligado, falta escolher a hora — o
// "Finalizar" ficava cinzento e mudo (PADRAO 1.2). Agora fica ativo e, ao
// tocar, diz "Escolhe a hora da entrega".
//
// Sem rede: o servidor é um MockClient que responde `null`/`[]` a tudo; a
// cotação do carrinho e as janelas do agendamento são falsas.
import 'dart:convert';

import 'package:bora_app/auth/auth_store.dart';
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/screens/cart_screen.dart';
import 'package:bora_app/screens/client_login_screen.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/bora/bora_accent_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

/// Cada pedido que chegou ao servidor de mentira ("MÉTODO /caminho").
final List<String> _pedidos = [];

Future<http.Response> _servidor(http.Request req) async {
  _pedidos.add('${req.method} ${req.url.path}');
  // get_setting → null (interruptores desligados); o resto → lista vazia.
  final corpo = req.url.path.endsWith('/rest/v1/rpc/get_setting') ? null : [];
  return http.Response(jsonEncode(corpo), 200, headers: _json, request: req);
}

/// Faz de servidor do agendamento (igual a test/agendar_pedido_carrinho_test).
class _AgendarFalso implements AgendarPedidoApi {
  _AgendarFalso({required this.ligado});
  final bool ligado;

  @override
  Future<ConfigAgendar> config() async => ConfigAgendar(ligado: ligado);

  @override
  Future<List<JanelaAgendada>> janelas(
      String restaurantId, DateTime dia) async {
    if (!ligado) return const [];
    final ini = DateTime.utc(dia.year, dia.month, dia.day, 19, 30);
    return [
      JanelaAgendada(inicio: ini, fim: ini.add(const Duration(minutes: 30))),
    ];
  }

  @override
  Future<void> gravar(String orderId, DateTime instante) async {}

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async =>
      const [];
}

/// Carrinho com 1 item (Auchan, 2,89 €), cotação falsa (sem servidor).
Future<CartStore> _carrinho(WidgetTester t, {bool fechada = false}) async {
  final cart = CartStore()
    ..configureSession(
      serviceType: OrderServiceType.storeShopping,
      isPartnerStore: false,
      vendorName: 'Auchan',
      vendorRestaurantId: 'auchan-guarda',
      distanceKm: 2.0,
      pickupLocation: const LatLng(40.5373, -7.2680),
      deliveryLocation: const LatLng(40.5400, -7.2700),
      vendorFechada: fechada,
      vendorAvisoFechada: 'Auchan está fechada agora.',
    );
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
  await t.runAsync(() async {
    await AgendarPedidoEstado.instance.verificarLoja('auchan-guarda');
  });
  cart.addItem(CartItem(
    productId: 'auc-18633',
    name: 'Queijo Boursin',
    price: 2.89,
    quantity: 1,
  ));
  expect(cart.items, hasLength(1));
  return cart;
}

/// Visitante: "Sou Cliente" sem conta (AuthStore.entrarComoVisitante).
Future<AuthStore> _visitante(WidgetTester t) async {
  final auth = (await t.runAsync(() async {
    final a = AuthStore();
    await a.entrarComoVisitante();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return a;
  }))!;
  addTearDown(auth.dispose);
  expect(auth.isVisitante, isTrue);
  expect(auth.currentClient, isNull);
  return auth;
}

Future<void> _abrirCarrinho(
    WidgetTester t, CartStore cart, AuthStore auth) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthStore>.value(value: auth),
      ChangeNotifierProvider<CartStore>.value(value: cart),
      ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
    ],
    child: const MaterialApp(home: CartScreen()),
  ));
  // O SDK do Supabase acaba as respostas fora do relógio falso do teste.
  for (var i = 0; i < 10; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }
}

BoraAccentButton _botaoFinalizar(WidgetTester t) => t.widget<BoraAccentButton>(
    find.widgetWithText(BoraAccentButton, 'Finalizar pedido'));

/// Desmonta e deixa correr o que ficou agendado (temporizadores do carrinho).
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
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(_servidor),
    );
  });

  setUp(() {
    _pedidos.clear();
    AgendarPedidoEstado.instance.reporParaTeste(_AgendarFalso(ligado: false));
  });

  testWidgets(
      'G1 — visitante toca em "Finalizar pedido" → abre "Entrar ou '
      'criar conta" (nunca um botão mudo)', (t) async {
    await t.runAsync(
        () => AgendarPedidoEstado.instance.carregarConfig(forcar: true));
    final auth = await _visitante(t);
    final cart = await _carrinho(t);
    await _abrirCarrinho(t, cart, auth);

    expect(find.byType(ClientLoginScreen), findsNothing);
    expect(_botaoFinalizar(t).onPressed, isNotNull,
        reason: 'o botão do visitante tem de estar ativo');

    await t.tap(find.text('Finalizar pedido'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600)); // animação da rota

    expect(find.byType(ClientLoginScreen), findsOneWidget);
    final login = t.widget<ClientLoginScreen>(find.byType(ClientLoginScreen));
    expect(login.voltarAoChamador, isTrue,
        reason: 'depois de entrar volta ao MESMO carrinho');
    expect(find.text('Entrar ou criar conta'), findsOneWidget);
    // O visitante não chegou a nenhum pagamento nem pedido.
    expect(_pedidos.where((p) => p.contains('create_order')), isEmpty);

    await _arrumar(t);
  });

  testWidgets(
      'G4 — falta escolher a hora: o "Finalizar" fica ativo e diz '
      '"Escolhe a hora da entrega" (sem abrir o pagamento)', (t) async {
    AgendarPedidoEstado.instance.reporParaTeste(_AgendarFalso(ligado: true));
    await t.runAsync(
        () => AgendarPedidoEstado.instance.carregarConfig(forcar: true));
    final auth = await _visitante(t);
    final cart = await _carrinho(t, fechada: true);
    expect(cart.agendamentoEmFalta, isTrue,
        reason: 'loja fechada + agendamento ligado + sem janela escolhida');
    await _abrirCarrinho(t, cart, auth);
    // Com a loja fechada o seletor escolhe sozinho a primeira hora livre;
    // o caso "falta a hora" é o cliente (ou a hora caducada) a deixá-la vazia.
    AgendarPedidoEstado.instance.limpar();
    await t.pump();
    expect(cart.agendamentoEmFalta, isTrue,
        reason: 'hora limpa: o Finalizar tem de explicar o que falta');

    expect(_botaoFinalizar(t).onPressed, isNotNull,
        reason: 'PADRAO 1.2: nunca cinzento e mudo');

    await t.tap(find.text('Finalizar pedido'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('Escolhe a hora da entrega'), findsOneWidget);
    expect(find.byType(ClientLoginScreen), findsNothing,
        reason: 'sem hora escolhida não segue para conta nem pagamento');

    await _arrumar(t);
  });
}
