import 'dart:async';
import 'dart:io';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:bora_app/stores/tvde_driver_store.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [É dele · 04/10/2026 · corrida 8c7f5ca6] A oferta entrou às 16:57:55 para
/// UM só motorista; ele aceitou às 16:58:18, a 2 s do fim do prazo — e o ecrã
/// mostrou "Esta corrida já foi para outro motorista." por cima da corrida
/// que era DELE. O cartão decidia só pelo relógio: prazo passado = "foi para
/// outro", sem olhar a quem a corrida pertencia nem ao aceite a decorrer.
///
/// O que estes testes prendem:
///  1. a regra pura: o aviso só vale quando a corrida NÃO é dele (pelo
///     `user_id`, nunca pelo `drivers.id`);
///  2. com o aceite a caminho do servidor (pelo cartão ou pelo botão da
///     notificação) o prazo não conta — nunca aparece o aviso;
///  3. prazo passado → pergunta-se primeiro de quem é; se é dele fecha em
///     silêncio, se não é aparece o aviso de sempre;
///  4. [Bloco 4] responder cala o aviso JÁ, em todos os caminhos.
const _eu = '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7'; // user_id (auth uid)
const _outro = 'aaaaaaaa-0000-4000-8000-000000000001';

TvdeRide _ride({
  String id = 'r1',
  String status = 'solicitada',
  DateTime? expira,
  DateTime? reservaExpira,
  DateTime? marcada,
  String? driver,
  String? para,
  String? donoReserva,
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
    reservationOfferExpiresAt: reservaExpira,
    scheduledAt: marcada,
    reservationStatus: marcada == null ? null : 'a_procurar',
    driverId: driver,
    currentOfferDriverId: para,
    reservationDriverId: donoReserva,
  );
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

Widget _host(TvdeDriverStore store) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        builder: (context, child) =>
            TvdeOfferOverlayHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('HOME'))),
      ),
    );

/// O aceite vai a caminho do servidor por outro caminho (botão da
/// notificação): o store diz "a aceitar".
class _LojaAAceitar extends TvdeDriverStore {
  @override
  bool aceiteEmCurso(String rideId) => true;
}

/// O servidor responde "a corrida é tua" (aceite noutro aparelho): o store
/// relê e a corrida entra como activa.
class _LojaDele extends TvdeDriverStore {
  int perguntas = 0;

  @override
  Future<bool> ofertaExpiradaEMinha(String rideId,
      {bool reserva = false}) async {
    perguntas++;
    // Como o verdadeiro: a resposta do servidor nunca chega a meio do build.
    await Future<void>.value();
    debugInjectar(
        activa: _ride(
            id: rideId, status: 'motorista_a_caminho', driver: _eu));
    return true;
  }
}

const _avisoCorrida = 'Esta corrida já foi para outro motorista.';
const _avisoReserva = 'Esta reserva já foi para outro motorista.';
final _cartao = find.byKey(const Key('tvde_oferta_sobreposta'));
final _expirada = find.byKey(const Key('tvde_oferta_expirada'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugLimparOfertasTvdeTratadas();
  });

  group('regra pura: devoMostrarFoiParaOutro', () {
    test('a corrida é minha (driver_id = o meu user_id): nunca se mostra', () {
      expect(
          devoMostrarFoiParaOutro(
              _ride(status: 'motorista_a_caminho', driver: _eu), _eu),
          isFalse);
      // Em fila também é dele.
      expect(
          devoMostrarFoiParaOutro(
              _ride(status: 'motorista_atribuido', driver: _eu), _eu),
          isFalse);
    });

    test('a reserva é minha (reservation_driver_id): nunca se mostra', () {
      expect(
          devoMostrarFoiParaOutro(
              _ride(
                  status: 'agendada',
                  marcada: DateTime(2026, 10, 5, 9, 0),
                  donoReserva: _eu),
              _eu),
          isFalse);
    });

    test('é de OUTRO motorista: mostra-se', () {
      expect(
          devoMostrarFoiParaOutro(
              _ride(status: 'motorista_a_caminho', driver: _outro), _eu),
          isTrue);
      expect(
          devoMostrarFoiParaOutro(
              _ride(
                  status: 'agendada',
                  marcada: DateTime(2026, 10, 5, 9, 0),
                  donoReserva: _outro),
              _eu),
          isTrue);
    });

    test('expirou para mim, foi cancelada, ou a RLS já a esconde: mostra-se',
        () {
      // Ainda à procura, sem dono: o prazo passou nas mãos dele.
      expect(devoMostrarFoiParaOutro(_ride(para: _eu), _eu), isTrue);
      expect(devoMostrarFoiParaOutro(_ride(status: 'cancelada_cliente'), _eu),
          isTrue);
      // A linha deixou de lhe ser visível (passou a outro).
      expect(devoMostrarFoiParaOutro(null, _eu), isTrue);
    });

    test('com o aceite a decorrer nunca se mostra, seja qual for a linha', () {
      expect(
          devoMostrarFoiParaOutro(_ride(para: _eu), _eu, aceiteEmCurso: true),
          isFalse);
      expect(devoMostrarFoiParaOutro(null, _eu, aceiteEmCurso: true), isFalse);
    });

    test('identidade: compara com o user_id; sem sessão não afirma que é dele',
        () {
      // Um `drivers.id` qualquer não é o user_id — não conta como "minha".
      expect(
          devoMostrarFoiParaOutro(
              _ride(status: 'motorista_a_caminho', driver: _eu),
              'drivers-id-interno'),
          isTrue);
      final minha = _ride(status: 'motorista_a_caminho', driver: _eu);
      expect(devoMostrarFoiParaOutro(minha, null), isTrue);
      expect(devoMostrarFoiParaOutro(minha, ''), isTrue);
    });
  });

  group('cartão da oferta imediata', () {
    testWidgets(
        'a corrida de 04/10: aceitou a 2 s do fim e o servidor demora — o '
        'prazo passa e o aviso NÃO aparece', (tester) async {
      var agora = DateTime(2026, 10, 4, 16, 58, 18);
      final resposta = Completer<void>();
      var expirou = 0;
      var fechou = 0;
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 2))),
        current: null,
        agora: () => agora,
        onAccept: () => resposta.future,
        onReject: () async {},
        onExpired: () => expirou++,
        onExpiredDismiss: () => fechou++,
      )));
      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')));
      await tester.pump();

      // O prazo passa com o aceite ainda a caminho.
      agora = agora.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_avisoCorrida), findsNothing,
          reason: 'disse "foi para outro" de uma corrida que ele aceitou');
      expect(_expirada, findsNothing);
      expect(_cartao, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(expirou, 0);
      expect(fechou, 0);

      resposta.complete();
      await tester.pump();
    });

    testWidgets(
        'aceite a decorrer por OUTRO caminho (botão da notificação): mesmo '
        'com o prazo passado fica à espera, sem aviso e sem botões vivos',
        (tester) async {
      final agora = DateTime(2026, 10, 4, 16, 58, 21);
      var aceitou = 0;
      var recusou = 0;
      var expirou = 0;
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 1))),
        current: null,
        agora: () => agora,
        aAceitar: true,
        onAccept: () async => aceitou++,
        onReject: () async => recusou++,
        onExpired: () => expirou++,
        onExpiredDismiss: () {},
      )));
      expect(find.text(_avisoCorrida), findsNothing);
      expect(_cartao, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(expirou, 0);

      await tester.pump(kTvdeRecusaGuardaAoAparecer);
      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')),
          warnIfMissed: false);
      await tester.tap(find.byKey(const Key('tvde_oferta_recusar')),
          warnIfMissed: false);
      await tester.pump();
      expect(aceitou, 0);
      expect(recusou, 0);
    });

    testWidgets(
        'prazo passado e a corrida É dele (aceite por outro caminho): fecha '
        'em silêncio — o aviso nunca aparece', (tester) async {
      final agora = DateTime(2026, 10, 4, 16, 58, 21);
      var perguntas = 0;
      var expirou = 0;
      var fechou = 0;
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 1))),
        current: null,
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        eMinha: () async {
          perguntas++;
          return true;
        },
        onAccept: () async {},
        onReject: () async {},
        onExpired: () => expirou++,
        onExpiredDismiss: () => fechou++,
      )));
      expect(find.text(_avisoCorrida), findsNothing);
      await tester.pump();
      expect(perguntas, 1);
      expect(expirou, 1, reason: 'a notificação morre na mesma');
      expect(fechou, 1, reason: 'sai JÁ, sem os segundos do aviso');
      expect(find.text(_avisoCorrida), findsNothing);
      expect(_expirada, findsNothing);

      // Nem depois: não há aviso atrasado nem segundo fecho.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(_avisoCorrida), findsNothing);
      expect(fechou, 1);
      expect(perguntas, 1);
    });

    testWidgets(
        'prazo passado e a corrida NÃO é dele: o aviso de sempre, depois de '
        'confirmar, e fecha-se sozinho', (tester) async {
      final agora = DateTime(2026, 10, 4, 16, 58, 21);
      var fechou = 0;
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 1))),
        current: null,
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        eMinha: () async => false,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () => fechou++,
      )));
      await tester.pump();
      expect(find.text(_avisoCorrida), findsOneWidget);
      expect(find.text('Aceitar'), findsNothing);
      expect(fechou, 0);
      await tester.pump(const Duration(seconds: 4));
      expect(fechou, 1);
    });

    testWidgets('a pergunta falha (sem rede): vale o aviso, nunca fica mudo',
        (tester) async {
      final agora = DateTime(2026, 10, 4, 16, 58, 21);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 1))),
        current: null,
        agora: () => agora,
        eMinha: () async => throw StateError('sem rede'),
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )));
      await tester.pump();
      expect(find.text(_avisoCorrida), findsOneWidget);
    });
  });

  group('cartão da oferta de reserva', () {
    TvdeRide reserva(DateTime agora) => _ride(
          status: 'agendada',
          marcada: DateTime(2026, 10, 5, 9, 0),
          reservaExpira: agora.subtract(const Duration(seconds: 1)),
        );

    testWidgets('aceite a decorrer com o prazo passado: sem aviso',
        (tester) async {
      final agora = DateTime(2026, 10, 4, 17, 0, 0);
      var expirou = 0;
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: reserva(agora),
        agora: () => agora,
        aAceitar: true,
        onAccept: () {},
        onReject: () {},
        onExpired: () => expirou++,
        onExpiredDismiss: () {},
      )));
      expect(find.text(_avisoReserva), findsNothing);
      expect(find.byKey(const Key('tvde_reserva_sobreposta')), findsOneWidget);
      expect(expirou, 0);
    });

    testWidgets('prazo passado e a reserva É dele: fecha em silêncio',
        (tester) async {
      final agora = DateTime(2026, 10, 4, 17, 0, 0);
      var fechou = 0;
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: reserva(agora),
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        eMinha: () async => true,
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () => fechou++,
      )));
      await tester.pump();
      expect(find.text(_avisoReserva), findsNothing);
      expect(fechou, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(_avisoReserva), findsNothing);
      expect(fechou, 1);
    });

    testWidgets('prazo passado e NÃO é dele: o aviso de sempre',
        (tester) async {
      final agora = DateTime(2026, 10, 4, 17, 0, 0);
      var fechou = 0;
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: reserva(agora),
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        eMinha: () async => false,
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () => fechou++,
      )));
      await tester.pump();
      expect(find.text(_avisoReserva), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(fechou, 1);
    });
  });

  group('host global', () {
    testWidgets(
        'aceite a decorrer pelo botão da notificação + prazo passado: o '
        'cartão espera, sem aviso', (tester) async {
      final store = _LojaAAceitar();
      await tester.pumpWidget(_host(store));
      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().subtract(const Duration(seconds: 1))));
      await tester.pump();
      await tester.pump();
      expect(find.text(_avisoCorrida), findsNothing);
      expect(_cartao, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'prazo passado e o servidor diz que a corrida é dele: nenhum aviso, '
        'o cartão sai e fica a corrida', (tester) async {
      final store = _LojaDele();
      await tester.pumpWidget(_host(store));
      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().subtract(const Duration(seconds: 1))));
      await tester.pump();
      expect(find.text(_avisoCorrida), findsNothing);
      await tester.pump();
      expect(store.perguntas, 1);
      expect(store.activeRide?.id, 'r1');
      expect(store.offeredRide, isNull);
      expect(find.text(_avisoCorrida), findsNothing);
      expect(_expirada, findsNothing);
      expect(_cartao, findsNothing);
      // O "abrir a corrida se ainda não abriu" espera 700 ms pela home.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_avisoCorrida), findsNothing);
    });

    testWidgets('prazo passado e não é dele (sem sessão): o aviso aparece',
        (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(_host(store));
      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().subtract(const Duration(seconds: 1))));
      await tester.pump();
      await tester.pump();
      expect(find.text(_avisoCorrida), findsOneWidget);
    });
  });

  group('store', () {
    test('sem aceite nenhum a decorrer, aceiteEmCurso é falso', () {
      expect(TvdeDriverStore().aceiteEmCurso('r1'), isFalse);
    });

    test('ofertaExpiradaEMinha: a corrida que já leva é dele, sem perguntar',
        () async {
      final store = TvdeDriverStore();
      store.debugInjectar(
          activa: _ride(status: 'motorista_a_caminho', driver: _eu));
      expect(await store.ofertaExpiradaEMinha('r1'), isTrue);
      expect(await store.ofertaExpiradaEMinha('outra'), isFalse,
          reason: 'sem sessão não se afirma que é dele');
    });
  });

  group('guardas de código (Bloco 4: nada fica por cima)', () {
    String ler(String p) => File(p).readAsStringSync();

    test('o botão da notificação cala o aviso ANTES de esperar pela app', () {
      final f = ler('lib/services/tvde_offer_action_handler.dart');
      final cala = f.indexOf('cancelTvdeRideNotification(rideId)');
      final espera = f.indexOf('for (var tentativa = 0;');
      expect(cala, greaterThan(0));
      expect(espera, greaterThan(cala),
          reason: 'o aviso ficava a tocar durante o arranque da app');
      // E não aceita duas vezes a corrida que já é dele.
      expect(f, contains('store.aceiteEmCurso(rideId)'));
      expect(f, contains('store.activeRide?.id == rideId'));
    });

    test('aceitar a reserva cala o aviso pelo id, antes da resposta', () {
      final f = ler('lib/stores/tvde_driver_store.dart');
      final ini = f.indexOf('Future<void> acceptReservation(String rideId)');
      expect(ini, greaterThan(0));
      final corpo = f.substring(ini, ini + 700);
      final cala = corpo.indexOf('cancelTvdeRideNotification(rideId)');
      final rpc = corpo.indexOf("'tvde_reservation_accept'");
      expect(cala, greaterThan(0));
      expect(rpc, greaterThan(cala));
    });

    test('arranque a frio pelo botão Aceitar: a acção não se perde', () {
      final f = ler('lib/services/notification_service.dart');
      final ini = f.indexOf('getNotificationAppLaunchDetails()');
      expect(ini, greaterThan(0));
      final corpo = f.substring(ini, ini + 1600);
      expect(corpo, contains('notificationResponse?.actionId'));
      expect(corpo, contains('_kTvdeOfferActionIds.contains('));
      expect(corpo, contains('_entregarAccaoTvdeAFrio('));
    });

    test('segundo plano: o aviso que nasce depois da resposta morre logo', () {
      final f = ler('lib/services/notification_service.dart');
      final posta = f.indexOf('BG full-screen offer notif posted');
      expect(posta, greaterThan(0));
      final corpo = f.substring(posta, posta + 600);
      expect(corpo, contains('ofertaTvdeJaTratadaPersistida(rideId'));
      expect(corpo, contains('plugin.cancel(rideId.hashCode)'));
    });

    test('o cartão global passa o "a aceitar" e a pergunta do dono', () {
      final f = ler('lib/widgets/tvde/tvde_offer_overlay_host.dart');
      expect('aAceitar: store.aceiteEmCurso('.allMatches(f), hasLength(2),
          reason: 'imediata E reserva');
      expect(f, contains('eMinha: () => _ofertaEMinha(store, offer.id)'));
      expect(f, contains('store.ofertaExpiradaEMinha(reserva.id'));
    });
  });
}
