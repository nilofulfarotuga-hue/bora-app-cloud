import 'dart:async';
import 'dart:convert';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_offer_screen.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:bora_app/services/tvde_offer_action_handler.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/tvde_driver_store.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [Cartão preso · 06/10/2026 · corrida 3835a143, versão 651] O Danilo
/// aceitou a volta do pacote pelo botão Aceitar da NOTIFICAÇÃO, com a app em
/// segundo plano. O servidor ficou certo em 5 s (motorista a caminho) e o
/// ecrã da corrida abriu certo — mas o cartão sobreposto ficou por cima mais
/// de um minuto a dizer "Nova corrida — agora", "0s", com o Aceitar a rodar.
///
/// O store também estava certo: os registos do servidor mostram a releitura
/// de 10 em 10 s da home (que só corre SEM oferta no store) a correr o minuto
/// todo. Quem não sabia era o cartão. Causa:
///  1. com a app em segundo plano a oferta entrou e a home empilhou o ecrã
///     "Nova corrida" (sem frames, nada se desenhou);
///  2. o botão da notificação trouxe a app para a frente e começou o aceite;
///  3. no primeiro frame o host desenhou o cartão (aceite a decorrer, ainda
///     sem corrida activa) e, a seguir no MESMO build, o `initState` do ecrã
///     "Nova corrida" avisou o host (`fullScreenRideId`) — `setState` a meio
///     do build de um descendente;
///  4. na app publicada o Flutter salta o host nesse frame e deixa-o marcado
///     "por redesenhar" para sempre: todos os avisos seguintes do store são
///     ignorados (`markNeedsBuild` sai logo por ele já estar sujo). O cartão
///     continuou vivo com o seu próprio relógio — contagem até "0s" — e com o
///     "a aceitar" e o "agora" do último desenho. Em modo debug (testes) o
///     mesmo `setState` rebenta com "setState() called during build" — o
///     defeito que a missão de 01/10 viu e deixou anotado.
const _eu = 'motorista-eu';

/// A linha que o servidor falso tem para a corrida e o que o aceite faz.
Map<String, dynamic> _linha = {};
Completer<void>? _aceiteSegura;
bool _aceiteEmFila = false;
int _aceites = 0;

Map<String, dynamic> _json({
  String id = 'r1',
  String status = 'solicitada',
  DateTime? expira,
  String? para = _eu,
  String? driver,
  bool fila = false,
}) =>
    <String, dynamic>{
      'id': id,
      'client_id': 'c1',
      'status': status,
      'origin_lat': 40.5353,
      'origin_lng': -7.2724,
      'dest_lat': 40.5375,
      'dest_lng': -7.2863,
      'est_distance_km': 1.94,
      'est_fare_cents': 0,
      'driver_earn_cents': 375,
      'origin_label': 'Avenida Alexandre Herculano, Guarda',
      'dest_label': 'IMT Guarda',
      'payment_method': 'cash',
      'driver_id': driver,
      'current_offer_driver_id': para,
      'offer_expires_at': expira?.toUtc().toIso8601String(),
      'is_queued': fila,
    };

TvdeRide _oferta({String id = 'r1', DateTime? expira}) => TvdeRide.fromMap(
    _json(id: id, expira: expira ?? DateTime.now().add(const Duration(seconds: 35))));

Future<http.Response> _servidor(http.Request req) async {
  final caminho = req.url.path;
  final objecto =
      (req.headers['accept'] ?? req.headers['Accept'] ?? '').contains('object');
  if (caminho.endsWith('/rpc/tvde_accept_ride')) {
    _aceites++;
    final segura = _aceiteSegura;
    if (segura != null) await segura.future;
    _linha = _json(
      status: _aceiteEmFila ? 'motorista_atribuido' : 'motorista_a_caminho',
      para: null,
      driver: _eu,
      fila: _aceiteEmFila,
    );
    return http.Response(jsonEncode(_linha), 200,
        headers: {'content-type': 'application/json'}, request: req);
  }
  if (caminho.endsWith('/rest/v1/tvde_rides')) {
    final corpo = objecto ? jsonEncode(_linha) : jsonEncode([_linha]);
    return http.Response(corpo, 200,
        headers: {'content-type': 'application/json'}, request: req);
  }
  return http.Response('[]', 200,
      headers: {'content-type': 'application/json'}, request: req);
}

/// O que a releitura do store vê, tirado da linha do servidor falso.
Future<TvdeLeituraActual> _lerServidor() async {
  final r = TvdeRide.fromMap(_linha);
  final minha = r.driverId == _eu;
  return TvdeLeituraActual(
    ativas: minha && !r.isQueued && r.isLive ? [r] : const [],
    fila: minha && r.isQueued ? r : null,
    oferta:
        r.status == 'solicitada' && r.currentOfferDriverId == _eu ? r : null,
  );
}

TvdeDriverStore _store() => TvdeDriverStore()
  ..debugUid = _eu
  ..debugLeitor = _lerServidor;

/// O ecrã da oferta só lhe pede a posição; sem ela não mostra a distância.
class _SemPosicao extends ChangeNotifier implements DriverStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A home do motorista reduzida à regra de navegação de hoje (`_syncNav`):
/// oferta → ecrã "Nova corrida"; corrida → ecrã da corrida, só depois de a
/// oferta fechar. Empilha a partir do aviso do store (fora de qualquer
/// build), como a home real faz no `.then` do `loadCurrent`.
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _offerOpen = false;
  bool _activeOpen = false;
  late final TvdeDriverStore _store = context.read<TvdeDriverStore>();

  @override
  void initState() {
    super.initState();
    _store.addListener(_syncNav);
  }

  @override
  void dispose() {
    _store.removeListener(_syncNav);
    super.dispose();
  }

  void _syncNav() {
    if (!mounted) return;
    final active = _store.activeRide;
    if (active != null && active.isLive && !_activeOpen && !_offerOpen) {
      _activeOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const _Corrida()))
          .then((_) => _activeOpen = false);
      return;
    }
    final offer = _store.offeredRide;
    if (offer != null && !_offerOpen && !_activeOpen) {
      _offerOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => TvdeOfferScreen(ride: offer)))
          .then((_) {
        _offerOpen = false;
        _syncNav();
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('HOME')));
}

/// O ecrã da corrida activa: como o real, diz ao cartão global qual corrida
/// está a mostrar A MEIO do build (`_onRideChanged`) e sai quando ela acaba.
class _Corrida extends StatefulWidget {
  const _Corrida();

  @override
  State<_Corrida> createState() => _CorridaState();
}

class _CorridaState extends State<_Corrida> {
  String? _id;

  @override
  void dispose() {
    if (TvdeOfferPresentation.corridaMostrada.value == _id) {
      TvdeOfferPresentation.corridaMostrada.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<TvdeDriverStore>().activeRide;
    if (active == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    if (_id != active.id) {
      _id = active.id;
      TvdeOfferPresentation.corridaMostrada.value = active.id;
    }
    return const Scaffold(body: Center(child: Text('CORRIDA')));
  }
}

Widget _app(TvdeDriverStore store, {Widget home = const _Home()}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TvdeDriverStore>.value(value: store),
      ChangeNotifierProvider<DriverStore>.value(value: _SemPosicao()),
    ],
    child: MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      builder: (context, child) =>
          TvdeOfferOverlayHost(child: child ?? const SizedBox.shrink()),
      home: home,
    ),
  );
}

final _cartao = find.byKey(const Key('tvde_oferta_sobreposta'));
final _ecraOferta = find.byType(TvdeOfferScreen, skipOffstage: false);

/// O cliente do Supabase acaba a resposta fora do relógio falso do teste:
/// dá-lhe uns instantes reais e redesenha.
Future<void> _servidorResponde(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Deixa passar [total] de relógio, um segundo de cada vez.
Future<void> _passar(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero; t < total; t += const Duration(seconds: 1)) {
    await tester.pump(const Duration(seconds: 1));
  }
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugLimparOfertasTvdeTratadas();
    TvdeOfferScreen.debugSemPlataforma = true;
    _linha = _json(expira: DateTime.now().add(const Duration(seconds: 35)));
    _aceiteSegura = null;
    _aceiteEmFila = false;
    _aceites = 0;
  });

  tearDown(() {
    TvdeOfferScreen.debugSemPlataforma = false;
    TvdeOfferPresentation.fullScreenRideId.value = null;
    TvdeOfferPresentation.activeRideOpenOverride.value = null;
    TvdeOfferPresentation.corridaMostrada.value = null;
  });

  group('a causa: o ecrã "Nova corrida" abre com o cartão global montado', () {
    testWidgets(
        'a corrida de 06/10: oferta empilhada, aceite pelo botão da notificação '
        'a meio — o cartão nunca fica preso, nem com "0s"', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));

      // 1. A oferta entra e a home empilha o ecrã "Nova corrida" — sem frame
      //    pelo meio, como com a app em segundo plano.
      _linha = _json(expira: DateTime.now().add(const Duration(seconds: 35)));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      // 2. O botão Aceitar da notificação começa o aceite (o servidor ainda
      //    não respondeu).
      _aceiteSegura = Completer<void>();
      final aceite = store.acceptOffer('r1');
      expect(store.aceiteEmCurso('r1'), isTrue);

      // 3. O primeiro frame: o host desenha e o ecrã "Nova corrida" nasce.
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'o ecrã da oferta avisou o cartão global a meio do build — '
              'na app publicada isto congela o cartão');
      await tester.pump();
      expect(_ecraOferta, findsOneWidget);
      expect(_cartao, findsNothing,
          reason: 'com o ecrã inteiro aberto o cartão não a duplica');

      // 4. O servidor responde: a corrida é dele.
      _aceiteSegura!.complete();
      await _servidorResponde(tester);
      await aceite;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(store.activeRide?.id, 'r1');
      expect(store.offeredRide, isNull);
      expect(_ecraOferta, findsNothing);
      expect(find.text('CORRIDA'), findsOneWidget);
      expect(_cartao, findsNothing);

      // 5. Passa o prazo da oferta e mais um minuto: nada por cima.
      await _passar(tester, const Duration(seconds: 100));
      expect(_cartao, findsNothing,
          reason: 'cartão "Nova corrida" preso por cima da corrida aceite');
      expect(find.text('0s'), findsNothing);
      expect(find.text('Nova corrida — agora'), findsNothing);
      expect(find.text('CORRIDA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'depois de o ecrã "Nova corrida" abrir e fechar, o cartão continua a '
        'seguir o store (oferta nova a meio da corrida aparece; sai quando '
        'sai do store)', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      await tester.pump();
      expect(_ecraOferta, findsOneWidget);
      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      await _servidorResponde(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('CORRIDA'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A sobreposição de 20/09: oferta NOVA durante a corrida.
      store.debugInjectar(
          activa: store.activeRide,
          oferta: _oferta(id: 'r2'));
      await tester.pump();
      expect(_cartao, findsOneWidget);
      expect(find.text('Nova corrida — depois desta corrida'), findsOneWidget);
      store.clearOffer();
      await tester.pump();
      expect(_cartao, findsNothing,
          reason: 'o host deixou de seguir o store (congelado)');
    });
  });

  group('os três caminhos do aceite põem a corrida no MESMO store e tiram a '
      'oferta', () {
    testWidgets('1. ecrã inteiro "Nova corrida"', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      await _servidorResponde(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_aceites, 1);
      expect(store.activeRide?.id, 'r1');
      expect(store.activeRide?.status, 'motorista_a_caminho');
      expect(store.offeredRide, isNull);
      expect(store.aceiteEmCurso('r1'), isFalse);
      expect(_cartao, findsNothing);
      expect(find.text('CORRIDA'), findsOneWidget);
    });

    testWidgets('2. cartão sobreposto (motorista noutro ecrã)', (tester) async {
      // O ecrã da corrida "abre-se" (a home real fá-lo); aqui só não se monta.
      TvdeOfferPresentation.activeRideOpenOverride.value = true;
      final store = _store();
      await tester.pumpWidget(_app(store,
          home: const Scaffold(body: Center(child: Text('AGENDA')))));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      expect(_cartao, findsOneWidget);
      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')));
      await tester.pump();
      await _servidorResponde(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_aceites, 1);
      expect(store.activeRide?.id, 'r1');
      expect(store.offeredRide, isNull);
      expect(_cartao, findsNothing);
      await tester.pump(const Duration(seconds: 5)); // o aviso "Corrida aceite"
    });

    testWidgets('3. botão Aceitar da notificação (gancho global)',
        (tester) async {
      TvdeOfferPresentation.activeRideOpenOverride.value = true;
      final store = _store();
      await tester.pumpWidget(_app(store,
          home: const Scaffold(body: Center(child: Text('WAZE POR CIMA')))));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      unawaited(tvdeResponderOfertaGlobal('r1', kTvdeOfferAcceptAction));
      // Sem sessão nos testes o gancho espera ~7 s pelo arranque.
      await _passar(tester, const Duration(seconds: 9));
      expect(_aceites, 1);
      expect(store.activeRide?.id, 'r1');
      expect(store.offeredRide, isNull);
      expect(_cartao, findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('em fila (sobreposição): vai para a fila e a oferta sai',
        (tester) async {
      TvdeOfferPresentation.activeRideOpenOverride.value = true;
      _aceiteEmFila = true;
      final store = _store();
      await tester.pumpWidget(_app(store,
          home: const Scaffold(body: Center(child: Text('CORRIDA ACTUAL')))));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')));
      await tester.pump();
      await _servidorResponde(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(store.queuedRide?.id, 'r1');
      expect(store.offeredRide, isNull);
      expect(_cartao, findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'aceite pendurado (o servidor nunca responde): ao fim do tempo do '
        'aceite o cartão sai e diz porquê — nunca fica em "0s"',
        (tester) async {
      TvdeOfferPresentation.activeRideOpenOverride.value = true;
      _aceiteSegura = Completer<void>(); // nunca se completa
      _linha = _json(expira: DateTime.now().add(const Duration(seconds: 3)));
      final store = _store();
      await tester.pumpWidget(_app(store,
          home: const Scaffold(body: Center(child: Text('AGENDA')))));
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _passar(tester, const Duration(seconds: 14));
      expect(store.aceiteEmCurso('r1'), isFalse);
      expect(store.offeredRide, isNull);
      expect(_cartao, findsNothing);
      expect(find.text('0s'), findsNothing);
      expect(find.text('Esta corrida já não está disponível.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('rede de segurança do cartão (mesmo com quem o mostra congelado)', () {
    // O cartão sozinho, com o "a aceitar" que lhe deram e mais nada — é o que
    // acontecia com o host congelado: ninguém lhe tirava o "a aceitar".
    Future<_Contas> montar(WidgetTester tester,
        {required Future<bool> Function() eMinha}) async {
      final contas = _Contas();
      var agora = DateTime(2026, 10, 6, 18, 34, 31);
      contas.avancar = (d) => agora = agora.add(d);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TvdeOfferOverlayCard(
            offer: _oferta(expira: agora.subtract(const Duration(seconds: 1))),
            current: null,
            agora: () => agora,
            aAceitar: true,
            onAccept: () async {},
            onReject: () async {},
            onExpired: () => contas.expirou++,
            onExpiredDismiss: () => contas.fechou++,
            eMinha: () {
              contas.perguntas++;
              return eMinha();
            },
          ),
        ),
      ));
      return contas;
    }

    Future<void> passar(WidgetTester tester, _Contas c, int segundos) async {
      for (var i = 0; i < segundos; i++) {
        c.avancar(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('prazo a 0 e "a aceitar" há 4 s, e é DELE: fecha em silêncio',
        (tester) async {
      final c = await montar(tester, eMinha: () async => true);
      expect(_cartao, findsOneWidget);
      expect(find.text('0s'), findsOneWidget);
      await passar(tester, c, 3);
      expect(c.perguntas, 0, reason: 'perguntou antes dos 4 s');
      await passar(tester, c, 2);
      await tester.pump();
      expect(c.perguntas, 1);
      expect(c.fechou, 1);
      expect(_cartao, findsNothing);
      expect(find.text('0s'), findsNothing);
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsNothing);
    });

    testWidgets('ainda não é dele: espera pelo aceite e volta a perguntar; '
        'quando passa a ser, fecha em silêncio', (tester) async {
      final respostas = <bool>[false, true];
      final c = await montar(tester, eMinha: () async => respostas.removeAt(0));
      await passar(tester, c, 5);
      await tester.pump();
      expect(c.perguntas, 1);
      expect(_cartao, findsOneWidget, reason: 'desistiu cedo demais');
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsNothing);
      await passar(tester, c, 4);
      await tester.pump();
      expect(c.perguntas, 2);
      expect(c.fechou, 1);
      expect(_cartao, findsNothing);
    });

    testWidgets('nunca é dele: ao fim de 16 s o aviso honesto, e sai',
        (tester) async {
      final c = await montar(tester, eMinha: () async => false);
      await passar(tester, c, 17);
      await tester.pump();
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsOneWidget);
      expect(find.text('0s'), findsNothing);
      expect(c.expirou, 1);
      await passar(tester, c, 6);
      await tester.pump();
      expect(c.fechou, 1);
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsNothing);
      expect(_cartao, findsNothing);
    });

    testWidgets('sem rede para perguntar: também nunca fica preso',
        (tester) async {
      final c = await montar(tester,
          eMinha: () async => throw StateError('sem rede'));
      await passar(tester, c, 30);
      await tester.pump();
      expect(c.fechou, 1);
      expect(_cartao, findsNothing);
      expect(find.text('0s'), findsNothing);
    });
  });

  group('o host nunca desenha a corrida que está aberta no ecrã da corrida',
      () {
    testWidgets('mesmo que o store ainda a tenha como oferta', (tester) async {
      final store = _store();
      await tester.pumpWidget(_app(store,
          home: const Scaffold(body: Center(child: Text('CORRIDA')))));
      TvdeOfferPresentation.corridaMostrada.value = 'r1';
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      expect(_cartao, findsNothing);

      // Outra corrida (a sobreposição de 20/09) continua a aparecer.
      store.debugInjectar(oferta: _oferta(id: 'r2'));
      await tester.pump();
      expect(_cartao, findsOneWidget);

      // O ecrã da corrida fecha-se: a regra deixa de valer para r1.
      TvdeOfferPresentation.corridaMostrada.value = null;
      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      await tester.pump();
      expect(_cartao, findsOneWidget);
    });
  });

  group('realtime: a corrida da oferta muda → a oferta sai do store na hora',
      () {
    Map<String, dynamic> evento(String status,
            {String? driver, String? para}) =>
        _json(status: status, driver: driver, para: para);

    test('passou a ser minha (aceite por outro caminho)', () {
      final store = _store()..debugInjectar(oferta: TvdeRide.fromMap(_linha));
      store.debugEventoRealtime(evento('motorista_a_caminho', driver: _eu));
      expect(store.offeredRide, isNull);
      expect(store.activeRide?.id, 'r1');
    });

    test('minha e já terminada (o evento chegou atrasado)', () {
      final store = _store()..debugInjectar(oferta: TvdeRide.fromMap(_linha));
      store.debugEventoRealtime(evento('finalizada', driver: _eu));
      expect(store.offeredRide, isNull,
          reason: 'a corrida já é dele e acabou; a oferta ficou em memória');
    });

    test('cancelada ou foi para outro motorista', () {
      final store = _store()..debugInjectar(oferta: TvdeRide.fromMap(_linha));
      store.debugEventoRealtime(evento('cancelada_cliente'));
      expect(store.offeredRide, isNull);

      store.debugInjectar(oferta: TvdeRide.fromMap(_linha));
      store.debugEventoRealtime(evento('solicitada', para: 'outro'));
      expect(store.offeredRide, isNull);
    });

    test('a mesma oferta, ainda minha e à procura, fica', () {
      final store = _store()..debugInjectar(oferta: TvdeRide.fromMap(_linha));
      store.debugEventoRealtime(evento('solicitada', para: _eu));
      expect(store.offeredRide?.id, 'r1');
    });
  });
}

class _Contas {
  int expirou = 0;
  int fechou = 0;
  int perguntas = 0;
  late void Function(Duration) avancar;
}
