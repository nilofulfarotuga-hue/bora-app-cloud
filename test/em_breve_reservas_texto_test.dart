// "EM BREVE" NUMA RESERVA DE MESA: O AVISO DIZ RESERVAS, NÃO PEDIDOS.
//
// Achado a 28/10/2026 na auditoria no emulador: ao tocar em "Reservar mesa"
// numa loja marcada "Em breve", o aviso dizia "Esta loja ainda não está a
// aceitar pedidos." — mas o cliente não está a fazer um pedido, está a reservar
// mesa. O aviso das entregas e das compras (carrinho, "+", ficha do produto)
// continua a dizer pedidos.
import 'dart:convert';
import 'dart:io';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/business_view_models.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/screens/client/reservation/reservation_availability_screen.dart';
import 'package:bora_app/screens/restaurant_menu_screen.dart';
import 'package:bora_app/screens/restaurant_options_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/favorite_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/widgets/bora/coming_soon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pedidos = 'Esta loja ainda não está a aceitar pedidos.';
const _reservas = 'Esta loja ainda não está a aceitar reservas.';

const _d = DayHours(open: '11:00', close: '23:00');
const _horario =
    BusinessHours(mon: _d, tue: _d, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d);

RestaurantModel _loja({required bool emBreve}) => RestaurantModel(
      id: 'loja-em-breve',
      name: 'Tasca do Zé',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      businessHours: _horario,
      reservationsEnabled: true,
      comingSoon: emBreve,
    );

Widget _botao(void Function(BuildContext) aoTocar) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => aoTocar(ctx),
            child: const Text('tocar'),
          ),
        ),
      ),
    );

String _ler(String caminho) => File(caminho).readAsStringSync();

const _lojaEmBreve = 'tasca-em-breve';
const _lojaAberta = 'tasca-aberta';

http.Response _json(http.Request req, Object corpo) => http.Response(
      jsonEncode(corpo),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _linhaDaLoja(String id, {required bool emBreve}) => {
      'id': id,
      'name': 'Tasca $id',
      'is_partner': true,
      'category': 'restaurant',
      'approval_status': 'approved',
      'is_active_admin': true,
      'reservations_enabled': true,
      'coming_soon': emBreve,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async {
        if (req.url.path == '/rest/v1/restaurants') {
          return _json(req, [
            _linhaDaLoja(_lojaEmBreve, emBreve: true),
            _linhaDaLoja(_lojaAberta, emBreve: false),
          ]);
        }
        return _json(req, const []);
      }),
    );
  });

  setUp(() => BoraLang.notifier.value = AppLang.pt);
  tearDown(() => BoraLang.notifier.value = AppLang.pt);

  group('o aviso "Em breve"', () {
    testWidgets('numa reserva diz "reservas" e não "pedidos"', (t) async {
      await t.pumpWidget(_botao(
          (ctx) => showComingSoonBlockedSnackBar(ctx, reserva: true)));
      await t.tap(find.text('tocar'));
      await t.pump();
      expect(find.text(_reservas), findsOneWidget);
      expect(find.text(_pedidos), findsNothing);
    });

    testWidgets('nas entregas e compras continua a dizer "pedidos"',
        (t) async {
      await t.pumpWidget(
          _botao((ctx) => showComingSoonBlockedSnackBar(ctx)));
      await t.tap(find.text('tocar'));
      await t.pump();
      expect(find.text(_pedidos), findsOneWidget);
      expect(find.text(_reservas), findsNothing);
    });

    testWidgets('em inglês, o aviso da reserva também se traduz', (t) async {
      BoraLang.notifier.value = AppLang.en;
      await t.pumpWidget(_botao(
          (ctx) => showComingSoonBlockedSnackBar(ctx, reserva: true)));
      await t.tap(find.text('tocar'));
      await t.pump();
      expect(find.text('This store is not accepting reservations yet.'),
          findsOneWidget);
      expect(find.text(_reservas), findsNothing);
    });

    testWidgets('em inglês, o aviso dos pedidos também se traduz', (t) async {
      BoraLang.notifier.value = AppLang.en;
      await t.pumpWidget(
          _botao((ctx) => showComingSoonBlockedSnackBar(ctx)));
      await t.tap(find.text('tocar'));
      await t.pump();
      expect(find.text('This store is not accepting orders yet.'),
          findsOneWidget);
      expect(find.text(_pedidos), findsNothing);
    });

    test('o texto PT dos pedidos e das reservas não mudou', () {
      expect(kComingSoonBlockedMessage, _pedidos);
      expect(kComingSoonReservationBlockedMessage, _reservas);
    });
  });

  group('ecrã de opções do restaurante (Entrega / Ir buscar / Reservar mesa)',
      () {
    Future<void> abrir(WidgetTester t, {required bool emBreve}) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        home: RestaurantOptionsScreen(
          business: _loja(emBreve: emBreve),
          restaurant: const Restaurant(
              name: 'Tasca do Zé', isPartner: true, menu: []),
          restaurantId: 'loja-em-breve',
        ),
      ));
      await t.pump();
    }

    testWidgets('"Reservar mesa" numa loja "Em breve" diz reservas',
        (t) async {
      await abrir(t, emBreve: true);
      expect(find.text('Reservar mesa'), findsOneWidget);
      await t.tap(find.text('Reservar mesa'));
      await t.pump();
      expect(find.text(_reservas), findsOneWidget);
      expect(find.text(_pedidos), findsNothing);
    });
  });

  group('menu do restaurante (botão "Reservar mesa" por cima da ementa)', () {
    Future<void> abrirMenu(WidgetTester t, String lojaId) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.6;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CartStore>(create: (_) => CartStore()),
          ChangeNotifierProvider<FavoriteStore>(
              create: (_) => FavoriteStore()),
          ChangeNotifierProvider<RestaurantStore>(
              create: (_) => RestaurantStore()),
        ],
        child: MaterialApp(
          home: RestaurantMenuScreen(
            restaurant: Restaurant(
                name: 'Tasca $lojaId', isPartner: true, menu: const []),
            restaurantId: lojaId,
          ),
        ),
      ));
      // As lojas chegam do servidor de brincar em tempo real, fora do relógio
      // do teste: espera (no máximo 3 s) até o botão aparecer.
      final botao = find.text('Reservar mesa');
      for (var i = 0; i < 30 && botao.evaluate().isEmpty; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(botao, findsOneWidget,
          reason: 'sem o botão este teste não provava nada');
    }

    Future<void> arrumar(WidgetTester t) async {
      await t.pump(const Duration(seconds: 10));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(minutes: 5));
      t.takeException();
    }

    testWidgets('loja "Em breve": avisa reservas e NÃO entra no fluxo',
        (t) async {
      await abrirMenu(t, _lojaEmBreve);
      await t.tap(find.text('Reservar mesa'));
      await t.pump();
      expect(find.text(_reservas), findsOneWidget);
      expect(find.text(_pedidos), findsNothing);
      expect(find.byType(ReservationAvailabilityScreen), findsNothing,
          reason: 'entrou no fluxo de reserva (que cobra €3) numa loja '
              '"Em breve"');
      await arrumar(t);
    });

    testWidgets('loja aberta: continua a entrar no fluxo de reserva',
        (t) async {
      await abrirMenu(t, _lojaAberta);
      await t.tap(find.text('Reservar mesa'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ReservationAvailabilityScreen), findsOneWidget);
      expect(find.text(_reservas), findsNothing);
      await arrumar(t);
    });
  });

  group('os sítios que chamam o aviso', () {
    test('as duas entradas de "Reservar mesa" pedem o aviso das reservas', () {
      final opcoes = _ler('lib/screens/restaurant_options_screen.dart');
      final lista = _ler('lib/screens/restaurants_screen.dart');
      for (final fonte in [opcoes, lista]) {
        expect(fonte, contains('showComingSoonBlockedSnackBar(context, reserva: true)'));
        // e nenhuma das duas chama o aviso dos pedidos sem o "reserva: true"
        expect(
          RegExp(r'showComingSoonBlockedSnackBar\(context\)')
              .allMatches(fonte)
              .length,
          0,
          reason: 'sobrou um aviso de "pedidos" num fluxo de reserva',
        );
      }
    });

    test(
        'o menu do restaurante: só o botão "Reservar mesa" pede o aviso das '
        'reservas; os "+" continuam com o dos pedidos', () {
      final menu = _ler('lib/screens/restaurant_menu_screen.dart');
      expect(RegExp('reserva: true').allMatches(menu).length, 1,
          reason: 'só o botão "Reservar mesa" é uma reserva');
      expect(menu, contains('showComingSoonBlockedSnackBar(context)'),
          reason: 'os "+" da ementa continuam a dizer pedidos');
    });

    test('o carrinho e o "+" dos produtos continuam com o aviso dos pedidos',
        () {
      for (final ficheiro in [
        'lib/screens/cart_screen.dart',
        'lib/screens/product_detail_screen.dart',
        'lib/screens/store_products_screen.dart',
      ]) {
        expect(_ler(ficheiro), isNot(contains('reserva: true')),
            reason: '$ficheiro é compra/entrega, não reserva');
      }
    });
  });
}
