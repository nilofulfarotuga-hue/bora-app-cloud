import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/driver/tvde/tvde_offer_screen.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:bora_app/stores/driver_store.dart';
import 'package:bora_app/stores/tvde_driver_store.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [Oferta fantasma · 01/10/2026 · corrida 03874579] O Danilo aceitou a
/// oferta 1 s depois do push, fez a viagem e finalizou. Ao voltar à home
/// apareceu outra vez o ecrã "Nova corrida" da MESMA corrida: sem som, com
/// os botões mortos e sem maneira de sair. Outras vezes ficava só um aviso
/// em cima, como se houvesse outro pedido.
///
/// O servidor estava limpo (uma oferta, um push, zero pushes depois de
/// finalizar). Era a app:
///  1. o realtime chegava ANTES da resposta do aceite, a home abria o ecrã da
///     corrida por cima da oferta, e o `pop()` do aceite fechava a corrida em
///     vez da oferta — que ficava presa por baixo até ao fim da viagem;
///  2. a notificação nascia depois de o aceite a ter mandado cancelar;
///  3. uma leitura do servidor que saiu antes do aceite chegava depois e
///     escrevia a oferta de volta;
///  4. o cartão global desenhava o que houvesse no store, sem olhar se era a
///     corrida que ele já levava.
///
/// E o que NÃO pode regredir: a oferta NOVA durante uma corrida activa (a
/// sobreposição de 20/09) continua a aparecer.
TvdeRide _ride({
  String id = 'r1',
  String status = 'solicitada',
  DateTime? expira,
  String? para,
}) {
  return TvdeRide(
    id: id,
    clientId: 'c1',
    status: status,
    originLat: 40.5396,
    originLng: -7.2841,
    destLat: 40.5381,
    destLng: -7.2653,
    estDistanceKm: 2.9,
    estFareCents: 500,
    driverEarnCents: 400,
    originLabel: 'Rua A, Guarda',
    destLabel: 'Rua B, Guarda',
    offerExpiresAt: expira,
    currentOfferDriverId: para,
  );
}

/// O store verdadeiro, com o servidor a responder ao aceite DEVAGAR.
class _LojaLenta extends TvdeDriverStore {
  _LojaLenta(this.atraso);
  final Duration atraso;
  int aceites = 0;

  @override
  Future<TvdeRide> acceptOffer(String rideId) async {
    aceites++;
    await Future<void>.delayed(atraso);
    final r = _ride(id: rideId, status: 'motorista_a_caminho');
    debugInjectar(activa: r);
    return r;
  }
}

/// O ecrã da oferta só lhe pede a posição; sem ela não mostra a distância.
class _SemPosicao extends ChangeNotifier implements DriverStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A home do motorista reduzida à sua regra de navegação (`_syncNav`).
/// [comoA0110] = true reproduz a home de 01/10, que abria o ecrã da corrida
/// mesmo com a oferta aberta — o empilhamento que criou o fantasma, e que
/// ainda pode acontecer por outro caminho (o botão Aceitar da notificação).
class _Home extends StatefulWidget {
  const _Home({required this.comoA0110});
  final bool comoA0110;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _offerOpen = false;
  bool _activeOpen = false;

  void _syncNav() {
    if (!mounted) return;
    final store = context.read<TvdeDriverStore>();
    final active = store.activeRide;
    if (active != null &&
        active.isLive &&
        !_activeOpen &&
        (widget.comoA0110 || !_offerOpen)) {
      _activeOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const _Corrida()))
          .then((_) => _activeOpen = false);
      return;
    }
    final offer = store.offeredRide;
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
  Widget build(BuildContext context) {
    context.watch<TvdeDriverStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNav());
    return const Scaffold(body: Center(child: Text('HOME')));
  }
}

/// O ecrã da corrida activa: sai sozinho quando a corrida acaba, como o real.
class _Corrida extends StatelessWidget {
  const _Corrida();

  @override
  Widget build(BuildContext context) {
    final active = context.watch<TvdeDriverStore>().activeRide;
    if (active == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    return const Scaffold(body: Center(child: Text('CORRIDA')));
  }
}

Widget _app(TvdeDriverStore store, {required bool comoA0110}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TvdeDriverStore>.value(value: store),
      ChangeNotifierProvider<DriverStore>.value(value: _SemPosicao()),
    ],
    // Sem o cartão global por cima: o `initState` do ecrã da oferta avisa o
    // host a meio de um build, o que em modo debug rebenta com "setState
    // during build" (defeito antigo, reportado à parte — não é desta missão).
    child: MaterialApp(home: _Home(comoA0110: comoA0110)),
  );
}

Widget _host(TvdeDriverStore store) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        builder: (context, child) =>
            TvdeOfferOverlayHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('HOME'))),
      ),
    );

final _ecraOferta = find.byType(TvdeOfferScreen, skipOffstage: false);
final _cartao = find.byKey(const Key('tvde_oferta_sobreposta'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugLimparOfertasTvdeTratadas();
    TvdeOfferScreen.debugSemPlataforma = true;
  });
  tearDown(() {
    TvdeOfferScreen.debugSemPlataforma = false;
    TvdeOfferPresentation.fullScreenRideId.value = null;
  });

  group('aceite com o servidor a responder 2 s depois', () {
    Future<void> viagemInteira(WidgetTester tester,
        {required bool comoA0110}) async {
      final store = _LojaLenta(const Duration(seconds: 2));
      await tester.pumpWidget(_app(store, comoA0110: comoA0110));

      // Entra a oferta: a home abre o ecrã "Nova corrida".
      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().add(const Duration(seconds: 30))));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Nova corrida'), findsOneWidget);
      expect(_ecraOferta, findsOneWidget);

      // Aceita. O servidor ainda não respondeu.
      await tester.tap(find.text('Aceitar'));
      await tester.pump();
      expect(store.aceites, 1);

      // 300 ms depois chega o REALTIME — antes da resposta do aceite.
      await tester.pump(const Duration(milliseconds: 300));
      store.debugInjectar(
          activa: _ride(id: 'r1', status: 'motorista_a_caminho'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Com a resposta ainda a caminho, já só existe o ecrã da corrida.
      expect(find.text('CORRIDA'), findsOneWidget);
      expect(_ecraOferta, findsNothing,
          reason: 'o ecrã da oferta ficou por baixo do ecrã da corrida');

      // Chega a resposta do aceite (aos 2 s). Nada pode fechar a corrida.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('CORRIDA'), findsOneWidget,
          reason: 'o fecho do aceite fechou o ecrã da corrida');
      expect(_ecraOferta, findsNothing);

      // Faz a viagem e finaliza: volta à home.
      store.debugInjectar();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('CORRIDA'), findsNothing);
      expect(find.text('Nova corrida'), findsNothing,
          reason: 'a oferta da corrida já feita reapareceu na home');
      expect(_ecraOferta, findsNothing,
          reason: 'ficou um TvdeOfferScreen na pilha do Navigator');
      expect(store.offeredRide, isNull);
      expect(TvdeOfferPresentation.fullScreenRideId.value, isNull);
    }

    testWidgets(
        'home de hoje: a corrida só abre depois de a oferta se fechar; no fim '
        'da viagem não há oferta nenhuma', (tester) async {
      await viagemInteira(tester, comoA0110: false);
    });

    testWidgets(
        'a corrida de 01/10: o ecrã da corrida empilhado POR CIMA da oferta — '
        'a oferta tira-se do meio e nunca reaparece', (tester) async {
      await viagemInteira(tester, comoA0110: true);
    });

    testWidgets('o aceite falha: fecha a oferta, não o que estiver por cima',
        (tester) async {
      final store = _LojaQueFalha();
      await tester.pumpWidget(_app(store, comoA0110: true));
      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().add(const Duration(seconds: 30))));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Aceitar'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_ecraOferta, findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      // O aviso do "já não está disponível" tem o seu tempo; deixa-o sair.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('a sobreposição de 20/09 não regride', () {
    testWidgets('oferta NOVA durante a corrida activa aparece, com Aceitar',
        (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(_host(store));
      store.debugInjectar(
        activa: _ride(id: 'activa', status: 'em_andamento'),
        oferta: _ride(
            id: 'nova',
            expira: DateTime.now().add(const Duration(seconds: 30))),
      );
      await tester.pump();
      expect(_cartao, findsOneWidget);
      expect(find.text('Nova corrida — depois desta corrida'), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
      expect(store.ofertaApresentavel(store.offeredRide!), isTrue);
    });

    testWidgets('a "oferta" que é a própria corrida activa não se desenha',
        (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(_host(store));
      store.debugInjectar(
        activa: _ride(id: 'r1', status: 'motorista_a_caminho'),
        oferta: _ride(
            id: 'r1', expira: DateTime.now().add(const Duration(seconds: 30))),
      );
      await tester.pump();
      expect(_cartao, findsNothing);
    });

    testWidgets('oferta que deixou de procurar motorista não se desenha; '
        'com o aceite a decorrer o cartão fica à vista', (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(_host(store));
      final prazo = DateTime.now().add(const Duration(seconds: 30));

      store.debugInjectar(oferta: _ride(id: 'x', expira: prazo));
      await tester.pump();
      expect(_cartao, findsOneWidget);

      // Tocou em Aceitar: a oferta fica marcada antes de o servidor
      // responder. O cartão não pode sumir sem dizer nada.
      await marcarOfertaTvdeTratada('x', prazo: prazo);
      store.debugInjectar(oferta: _ride(id: 'x', expira: prazo));
      await tester.pump();
      expect(_cartao, findsOneWidget);

      store.debugInjectar(
          oferta: _ride(id: 'y', status: 'motorista_a_caminho', expira: prazo));
      await tester.pump();
      expect(_cartao, findsNothing);
    });

    testWidgets('sem prazo do servidor o cartão conta 25 s e fecha-se',
        (tester) async {
      var fechou = 0;
      var agora = DateTime(2026, 10, 1, 11, 0, 0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TvdeOfferOverlayCard(
            offer: _ride(),
            current: null,
            agora: () => agora,
            tempoAteFechar: const Duration(seconds: 2),
            onAccept: () async {},
            onReject: () async {},
            onExpiredDismiss: () => fechou++,
          ),
        ),
      ));
      expect(find.text('25s'), findsOneWidget);
      agora = agora.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('15s'), findsOneWidget,
          reason: 'a contagem ficava congelada em 25 s');
      agora = agora.add(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(fechou, 1);
    });
  });

  group('ofertas já tratadas (a notificação que nascia depois do aceite)', () {
    final t0 = DateTime(2026, 10, 1, 10, 19, 40);

    // A pausa do servidor antes de voltar a oferecer a mesma corrida.
    const pausaDoServidor = Duration(seconds: 35);

    test('a mesma roda fica tapada; uma roda nova passa', () async {
      final prazo = t0.add(const Duration(seconds: 40));
      expect(ofertaTvdeJaTratada('r1', prazo: prazo, agora: t0), isFalse);
      await marcarOfertaTvdeTratada('r1', prazo: prazo, quando: t0);
      // Logo a seguir: tapada, mesmo com o prazo re-ancorado pela Edge do
      // push para mais tarde (a mesma roda).
      final logo = t0.add(const Duration(seconds: 2));
      expect(ofertaTvdeJaTratada('r1', prazo: prazo, agora: logo), isTrue);
      expect(
          ofertaTvdeJaTratada('r1',
              prazo: prazo.add(const Duration(seconds: 3)), agora: logo),
          isTrue);
      // Leitura muito atrasada da mesma roda: continua tapada pelo prazo.
      final tarde = t0.add(const Duration(minutes: 3));
      expect(ofertaTvdeJaTratada('r1', prazo: prazo, agora: tarde), isTrue);
      // O prazo gravado para o outro isolate perde os microssegundos.
      expect(
          ofertaTvdeJaTratada('r1',
              prazo: prazo.add(const Duration(microseconds: 400)),
              agora: tarde),
          isTrue);
      // Roda NOVA (o servidor só a faz depois da pausa): é oferta outra vez.
      final rodaNova = t0.add(pausaDoServidor);
      expect(
          ofertaTvdeJaTratada('r1',
              prazo: rodaNova.add(const Duration(seconds: 40)),
              agora: rodaNova),
          isFalse);
      expect(ofertaTvdeJaTratada('outra', prazo: prazo, agora: logo), isFalse);
    });

    test('recusada pelo botão da notificação (sem prazo): a roda nova, 35 s '
        'depois, tem aviso', () async {
      await marcarOfertaTvdeTratada('r1', quando: t0);
      expect(
          ofertaTvdeJaTratada('r1', agora: t0.add(const Duration(seconds: 5))),
          isTrue);
      expect(kTvdeOfertaTratadaJanela, lessThan(pausaDoServidor),
          reason: 'a janela não pode chegar à roda seguinte');
      expect(
          ofertaTvdeJaTratada('r1',
              prazo: t0.add(const Duration(seconds: 75)),
              agora: t0.add(pausaDoServidor)),
          isFalse);
      expect(ofertaTvdeJaTratada('r1', agora: t0.add(pausaDoServidor)),
          isFalse);
    });

    test('o outro isolate lê a marca gravada', () async {
      await marcarOfertaTvdeTratada('r1');
      debugLimparOfertasTvdeTratadas(); // memória de outro isolate: vazia
      expect(ofertaTvdeJaTratada('r1'), isFalse);
      expect(await ofertaTvdeJaTratadaPersistida('r1'), isTrue);
      expect(await ofertaTvdeJaTratadaPersistida('r2'), isFalse);
    });

    test('desmarcar devolve a oferta (aceite que falhou por rede)', () async {
      await marcarOfertaTvdeTratada('r1');
      desmarcarOfertaTvdeTratada('r1');
      expect(ofertaTvdeJaTratada('r1'), isFalse);
    });
  });

  group('leituras do servidor fora de ordem (a oferta ressuscitada)', () {
    final prazo = DateTime.now().add(const Duration(seconds: 30));
    TvdeLeituraActual antes() =>
        TvdeLeituraActual(ativas: const [], oferta: _ride(expira: prazo));
    TvdeLeituraActual depois() => TvdeLeituraActual(
        ativas: [_ride(id: 'r1', status: 'motorista_a_caminho')]);

    test('a leitura que saiu antes do aceite não escreve a oferta de volta',
        () async {
      final store = TvdeDriverStore();
      final respostas = <Completer<TvdeLeituraActual>>[];
      store.debugLeitor = () {
        final c = Completer<TvdeLeituraActual>();
        respostas.add(c);
        return c.future;
      };

      final leitura = store.loadCurrent(); // sai ANTES do aceite
      await Future<void>.delayed(Duration.zero);
      expect(respostas, hasLength(1));

      // Entretanto ele aceita: a corrida passa a ser dele.
      store.debugInjectar(
          activa: _ride(id: 'r1', status: 'motorista_a_caminho'));

      // A resposta velha chega agora — "tens uma oferta, não tens corrida".
      respostas[0].complete(antes());
      await Future<void>.delayed(Duration.zero);
      expect(store.offeredRide, isNull,
          reason: 'a leitura velha ressuscitou a oferta');
      expect(store.activeRide?.id, 'r1',
          reason: 'a leitura velha apagou a corrida activa');

      // Em vez de escrever, voltou a perguntar; a resposta fresca é que vale.
      expect(respostas, hasLength(2));
      respostas[1].complete(depois());
      await leitura;
      expect(store.offeredRide, isNull);
      expect(store.activeRide?.id, 'r1');
    });

    test('de duas leituras, só a mais recente escreve', () async {
      final store = TvdeDriverStore();
      final respostas = <Completer<TvdeLeituraActual>>[];
      store.debugLeitor = () {
        final c = Completer<TvdeLeituraActual>();
        respostas.add(c);
        return c.future;
      };
      final velha = store.loadCurrent();
      final nova = store.loadCurrent();
      await Future<void>.delayed(Duration.zero);
      respostas[1].complete(depois());
      await nova;
      respostas[0].complete(antes()); // a velha chega no fim
      await velha;
      expect(store.offeredRide, isNull);
      expect(store.activeRide?.id, 'r1');
    });

    test('nunca entra como oferta a corrida que já é dele ou já respondeu',
        () async {
      final store = TvdeDriverStore();
      // O servidor devolve a mesma corrida como activa E como oferta.
      store.debugLeitor = () async => TvdeLeituraActual(
            ativas: [_ride(id: 'r1', status: 'motorista_a_caminho')],
            oferta: _ride(id: 'r1', expira: prazo),
          );
      await store.loadCurrent();
      expect(store.activeRide?.id, 'r1');
      expect(store.offeredRide, isNull);

      // Recusou a r2 há um minuto; uma leitura atrasada da mesma roda não a
      // traz de volta…
      await marcarOfertaTvdeTratada('r2',
          prazo: prazo,
          quando: DateTime.now().subtract(const Duration(minutes: 1)));
      store.debugLeitor = () async => TvdeLeituraActual(
          ativas: const [], oferta: _ride(id: 'r2', expira: prazo));
      await store.loadCurrent();
      expect(store.offeredRide, isNull);

      // …mas uma roda NOVA da r2 (prazo mais tarde) é oferta a sério.
      store.debugLeitor = () async => TvdeLeituraActual(
          ativas: const [],
          oferta: _ride(
              id: 'r2', expira: prazo.add(const Duration(seconds: 40))));
      await store.loadCurrent();
      expect(store.offeredRide?.id, 'r2');
    });

    test('oferta nova durante a corrida activa entra (sobreposição)',
        () async {
      final store = TvdeDriverStore();
      store.debugLeitor = () async => TvdeLeituraActual(
            ativas: [_ride(id: 'activa', status: 'em_andamento')],
            oferta: _ride(id: 'nova', expira: prazo),
          );
      await store.loadCurrent();
      expect(store.activeRide?.id, 'activa');
      expect(store.offeredRide?.id, 'nova');
      expect(store.ofertaApresentavel(store.offeredRide!), isTrue);
    });
  });

  group('guardas de código', () {
    String ler(String p) => File(p).readAsStringSync();

    test('o ecrã da oferta nunca fecha "o ecrã de cima"', () {
      final f = ler('lib/screens/driver/tvde/tvde_offer_screen.dart');
      expect(f, contains('removeRoute('));
      // O único pop do ficheiro é o de `_fecharEstaRota`, com a rota no topo.
      expect(f, isNot(contains('Navigator.of(context).pop(')),
          reason: 'um pop solto volta a poder fechar o ecrã da corrida');
      expect('nav.pop('.allMatches(f), hasLength(1));
      expect(f, isNot(contains('.maybePop(')));
    });

    test('a home não abre a corrida por cima da oferta, e volta a decidir '
        'quando a oferta fecha', () {
      final f = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      final ini = f.indexOf('void _syncNav()');
      final fim = f.indexOf('void _maybeResumeDeliveryFlow()');
      final corpo = f.substring(ini, fim);
      expect(
          RegExp(r'active\.isLive &&\s*!_activeOpen &&\s*!_offerOpen &&')
              .hasMatch(corpo),
          isTrue);
      expect(
          RegExp(r'_offerOpen = false;\s*_syncNav\(\);').hasMatch(corpo), isTrue);
    });

    test('aceitar e recusar matam a notificação pelo id e marcam a oferta',
        () {
      final f = ler('lib/stores/tvde_driver_store.dart');
      for (final metodo in ['acceptOffer', 'rejectOffer']) {
        final ini = f.indexOf(RegExp('Future<[^>]+> $metodo\\(String rideId\\)'));
        expect(ini, greaterThan(0), reason: metodo);
        final corpo = f.substring(ini, ini + 1400);
        expect(corpo, contains('marcarOfertaTvdeTratada(rideId'),
            reason: metodo);
        expect(corpo, contains('cancelTvdeRideNotification(rideId)'),
            reason: metodo);
      }
    });

    test('o aviso pergunta se a oferta já foi respondida antes de aparecer',
        () {
      final f = ler('lib/services/notification_service.dart');
      final ini = f.indexOf('Future<void> _showTvdeOfferNotification(');
      final corpo = f.substring(ini, f.indexOf('void _showChatBanner('));
      final canal = corpo.indexOf('createNotificationChannel(');
      final pergunta = corpo.indexOf('ofertaTvdeJaTratada(');
      final mostra = corpo.indexOf('plugin.show(');
      expect(canal, greaterThan(0));
      expect(pergunta, greaterThan(canal),
          reason: 'a pergunta tem de vir DEPOIS do await do canal');
      expect(mostra, greaterThan(pergunta));
      expect(corpo.indexOf('ofertaTvdeJaTratada(', mostra), greaterThan(mostra),
          reason: 'e outra vez depois do show');
      // Segundo plano: lê o que o outro isolate gravou.
      expect(f, contains('ofertaTvdeJaTratadaPersistida(rideId'));
    });
  });
}

class _LojaQueFalha extends TvdeDriverStore {
  @override
  Future<TvdeRide> acceptOffer(String rideId) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    throw StateError('offer_no_longer_valid');
  }
}
