import 'dart:io';

import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/services/notification_service.dart';
import 'package:bora_app/stores/tvde_driver_store.dart';
import 'package:bora_app/widgets/tvde/tvde_offer_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// [Oferta sobreposta 20/09/2026] A cicatriz: o Danilo estava no ecrã da
/// corrida activa quando entrou a oferta da reserva da meia-noite. O toque
/// chegou, o cartão não — vivia só dentro da home, tapado. Não houve forma
/// de aceitar. Estes testes prendem as seis coisas que passaram a ser
/// verdade:
///  1. o cartão da oferta imediata tem Aceitar e Recusar SEMPRE visíveis;
///  2. serve os dois casos: livre ("agora") e ocupado ("depois desta");
///  3. a oferta de reserva também tem cartão, com a hora marcada;
///  4. expirada nas mãos dele → frase honesta e fecha-se sozinho (nunca
///     `SizedBox.shrink()` em silêncio);
///  5. o contador vem do prazo em cada rebuild, não de um número guardado;
///  6. o cartão desenha-se POR CIMA de qualquer rota (host no builder do
///     MaterialApp) e esconde-se quando o ecrã inteiro já mostra a mesma.
/// Mais os guardas de código: ganchos globais (nunca num ecrã), botões na
/// notificação, filtro de oferta morta no store, chaves no painel.
TvdeRide _ride({
  String id = 'r1',
  String status = 'solicitada',
  DateTime? expira,
  DateTime? reservaExpira,
  DateTime? marcada,
  int earn = 400,
  String? origem = 'Rua A, Guarda',
  String? destino = 'Rua B, Guarda',
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
    driverEarnCents: earn,
    originLabel: origem,
    destLabel: destino,
    offerExpiresAt: expira,
    reservationOfferExpiresAt: reservaExpira,
    scheduledAt: marcada,
    reservationStatus: marcada == null ? null : 'a_procurar',
  );
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('cartão da oferta imediata', () {
    testWidgets('livre: "agora", ganho em grande, Aceitar e Recusar vivos',
        (tester) async {
      var aceitou = 0;
      var recusou = 0;
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 30))),
        current: null,
        agora: () => agora,
        onAccept: () async => aceitou++,
        onReject: () async => recusou++,
        onExpiredDismiss: () {},
      )));

      expect(find.text('Nova corrida — agora'), findsOneWidget);
      expect(find.text('€4.00'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.textContaining('Recolha: Rua A'), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tvde_oferta_aceitar')));
      await tester.pump();
      expect(aceitou, 1);
      expect(recusou, 0);
    });

    testWidgets('ocupado: "depois desta corrida" e a ligação em km',
        (tester) async {
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 25))),
        current: _ride(id: 'activa', status: 'em_andamento'),
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )));
      expect(find.text('Nova corrida — depois desta corrida'), findsOneWidget);
      expect(find.textContaining('km de onde vais largar'), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
    });

    testWidgets('Recusar chama o recusar e nunca o aceitar', (tester) async {
      var aceitou = 0;
      var recusou = 0;
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 30))),
        current: null,
        agora: () => agora,
        onAccept: () async => aceitou++,
        onReject: () async => recusou++,
        onExpiredDismiss: () {},
      )));
      await tester.tap(find.byKey(const Key('tvde_oferta_recusar')));
      await tester.pump();
      expect(recusou, 1);
      expect(aceitou, 0);
    });

    testWidgets('o contador ressincroniza do prazo em cada rebuild',
        (tester) async {
      var agora = DateTime(2026, 9, 20, 22, 0, 0);
      final expira = agora.add(const Duration(seconds: 30));
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: expira),
        current: null,
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )));
      expect(find.text('30s'), findsOneWidget);
      // O relógio salta 12 s (o telemóvel esteve a dormir): o ticker seguinte
      // redesenha e o número vem do prazo, não de "30 − 1".
      agora = agora.add(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('18s'), findsOneWidget);
      expect(find.text('29s'), findsNothing);
    });

    testWidgets('expirada nas mãos dele: frase honesta e fecha-se sozinha',
        (tester) async {
      var fechou = 0;
      var expirou = 0;
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.subtract(const Duration(seconds: 3))),
        current: null,
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 4),
        onAccept: () async {},
        onReject: () async {},
        onExpired: () => expirou++,
        onExpiredDismiss: () => fechou++,
      )));
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsOneWidget);
      expect(find.text('Aceitar'), findsNothing);
      expect(find.text('Recusar'), findsNothing);
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsNothing);
      // A notificação morre NO MOMENTO da expiração (uma vez só); o cartão
      // ainda fica uns segundos a explicar.
      expect(expirou, 1);
      expect(fechou, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(expirou, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(fechou, 1);
    });

    testWidgets('a oferta expira enquanto ele olha → muda para a frase',
        (tester) async {
      var agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeOfferOverlayCard(
        offer: _ride(expira: agora.add(const Duration(seconds: 2))),
        current: null,
        agora: () => agora,
        onAccept: () async {},
        onReject: () async {},
        onExpiredDismiss: () {},
      )));
      expect(find.text('Aceitar'), findsOneWidget);
      agora = agora.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Esta corrida já foi para outro motorista.'),
          findsOneWidget);
      expect(find.text('Aceitar'), findsNothing);
    });
  });

  group('cartão da oferta de reserva', () {
    testWidgets('viva: hora marcada, Aceitar reserva e Recusar',
        (tester) async {
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: _ride(
          marcada: DateTime(2026, 9, 21, 0, 0),
          reservaExpira: agora.add(const Duration(minutes: 4)),
        ),
        agora: () => agora,
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () {},
      )));
      expect(find.text('Reserva para aceitar'), findsOneWidget);
      expect(find.textContaining('00:00'), findsOneWidget);
      expect(find.text('Aceitar reserva'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
    });

    testWidgets('expirada: frase honesta e fecha-se sozinha', (tester) async {
      var fechou = 0;
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      await tester.pumpWidget(_app(TvdeReservationOverlayCard(
        ride: _ride(
          marcada: DateTime(2026, 9, 21, 0, 0),
          reservaExpira: agora.subtract(const Duration(seconds: 1)),
        ),
        agora: () => agora,
        tempoAteFechar: const Duration(seconds: 3),
        onAccept: () {},
        onReject: () {},
        onExpiredDismiss: () => fechou++,
      )));
      expect(find.text('Esta reserva já foi para outro motorista.'),
          findsOneWidget);
      expect(find.text('Aceitar reserva'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(fechou, 1);
    });
  });

  group('host global (por cima de qualquer ecrã)', () {
    Widget host(TvdeDriverStore store) => ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            builder: (context, child) =>
                TvdeOfferOverlayHost(child: child ?? const SizedBox.shrink()),
            home: const _Pagina('HOME'),
          ),
        );

    testWidgets(
        'a oferta imediata aparece por cima de uma rota empilhada e a de '
        'reserva também', (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(host(store));
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsNothing);

      // Empilha um ecrã por cima da home (o "ecrã da corrida activa").
      await tester.tap(find.text('empilhar'));
      await tester.pumpAndSettle();
      expect(find.text('POR CIMA'), findsOneWidget);

      store.debugInjectar(
          oferta: _ride(
              expira: DateTime.now().add(const Duration(seconds: 30))));
      await tester.pump();
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsOneWidget);
      expect(find.text('Aceitar'), findsOneWidget);
      expect(find.text('POR CIMA'), findsOneWidget);

      // Sai a imediata, entra a de reserva: também por cima.
      store.debugInjectar(
          reserva: _ride(
        id: 'res',
        status: 'agendada',
        marcada: DateTime.now().add(const Duration(hours: 2)),
        reservaExpira: DateTime.now().add(const Duration(minutes: 4)),
      ));
      await tester.pump();
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsNothing);
      expect(find.byKey(const Key('tvde_reserva_sobreposta')), findsOneWidget);
      expect(find.text('Aceitar reserva'), findsOneWidget);

      store.debugInjectar();
      await tester.pump();
      expect(find.byKey(const Key('tvde_reserva_sobreposta')), findsNothing);
    });

    testWidgets('esconde-se enquanto o ecrã inteiro mostra a mesma oferta',
        (tester) async {
      final store = TvdeDriverStore();
      await tester.pumpWidget(host(store));
      store.debugInjectar(
          oferta: _ride(
              id: 'x', expira: DateTime.now().add(const Duration(seconds: 30))));
      await tester.pump();
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsOneWidget);

      TvdeOfferPresentation.fullScreenRideId.value = 'x';
      await tester.pump();
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsNothing);

      TvdeOfferPresentation.fullScreenRideId.value = null;
      await tester.pump();
      expect(find.byKey(const Key('tvde_oferta_sobreposta')), findsOneWidget);
    });
  });

  group('notificação com botões (Bloco 3)', () {
    test('Aceitar abre a app; Recusar corre sem UI e cala o telemóvel', () {
      final imediata = tvdeOfferNotificationActions(reserva: false);
      expect(imediata.map((a) => a.id),
          [kTvdeOfferAcceptAction, kTvdeOfferRejectAction]);
      expect(imediata[0].showsUserInterface, isTrue);
      expect(imediata[0].cancelNotification, isFalse);
      expect(imediata[1].showsUserInterface, isFalse);
      expect(imediata[1].cancelNotification, isTrue);

      final reserva = tvdeOfferNotificationActions(reserva: true);
      expect(reserva.map((a) => a.id),
          [kTvdeReservationAcceptAction, kTvdeReservationRejectAction]);
    });

    test('o corpo leva o GANHO do motorista, e cai no antigo sem ele', () {
      expect(
        tvdeOfferNotificationBody({
          'originLabel': 'Rua A',
          'destLabel': 'Rua B',
          'distanceKm': '2.9',
          'driverEarn': '4.00',
          'collectCash': '5.00',
          'fare': '5.00',
        }),
        'Ganhas €4.00 · Rua A → Rua B · 2.9km · cobras €5.00 ao cliente',
      );
      // Edge antiga (sem driverEarn): o body dela manda, nunca vazio.
      expect(
        tvdeOfferNotificationBody({'body': 'Rua A -> Rua B • €5.00'}),
        'Rua A -> Rua B • €5.00',
      );
      expect(tvdeOfferNotificationBody({}), 'Recolha → Destino • €0.00');
    });

    test('a notificação vive até ao prazo da oferta (mínimo 5 s)', () {
      final agora = DateTime(2026, 9, 20, 22, 0, 0);
      expect(tvdeOfferNotificationTimeoutMs({}, agora: agora), 45000);
      expect(
          tvdeOfferNotificationTimeoutMs({
            'offerExpiresAt':
                agora.add(const Duration(seconds: 40)).toIso8601String()
          }, agora: agora),
          40000);
      expect(
          tvdeOfferNotificationTimeoutMs({
            'offerExpiresAt':
                agora.subtract(const Duration(seconds: 40)).toIso8601String()
          }, agora: agora),
          5000);
    });
  });

  group('guardas de código', () {
    String ler(String p) => File(p).readAsStringSync();

    test('os ganchos da oferta registam-se no main.dart, nunca num ecrã', () {
      final registo = RegExp(
          r'NotificationService\.(tvdeOfferReload|tvdeReservationReload|tvdeOfferAction)\s*=');
      final infractores = <String>[];
      for (final f in Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (registo.hasMatch(f.readAsStringSync())) {
          infractores.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(infractores, isEmpty,
          reason: 'gancho preso ao ciclo de vida de um ecrã (cicatriz de '
              '20/08 e 20/09): fica a null com outro ecrã por cima');
      final main = ler('lib/main.dart');
      expect(main, contains('NotificationService.tvdeOfferReload ='));
      expect(main, contains('NotificationService.tvdeReservationReload ='));
      expect(main, contains('NotificationService.tvdeOfferAction ='));
    });

    test('o host envolve o Navigator inteiro (builder do MaterialApp)', () {
      final main = ler('lib/main.dart');
      final builder = main.indexOf('builder: (context, child) =>');
      final home = main.indexOf('home: const AppUpdateGate(');
      expect(builder, greaterThan(0));
      expect(main.substring(builder, home), contains('TvdeOfferOverlayHost('));
    });

    test('a faixa antiga do ecrã da corrida saiu; o cartão é um só', () {
      final activo = ler('lib/screens/driver/tvde/tvde_ride_active_screen.dart');
      expect(activo, isNot(contains('class _QueuedOfferBanner')));
      final home = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      expect(home, isNot(contains('TvdeReservationOfferCard(')));
    });

    test('uma oferta morta nunca chega à UI (filtro no store)', () {
      final store = ler('lib/stores/tvde_driver_store.dart');
      expect(store, contains('offer_expires_at.gt.'));
      expect(store, contains('reservation_offer_expires_at.gt.'));
    });

    test('as notificações de oferta levam os botões', () {
      final ns = ler('lib/services/notification_service.dart');
      expect('tvdeOfferNotificationActions(reserva: false)'.allMatches(ns),
          hasLength(2),
          reason: 'primeiro plano E segundo plano');
      expect(ns, contains('tvdeOfferNotificationActions(reserva: true)'));
      expect(ns, contains("'tvde_reject_ride'"));
      expect(ns, contains("'tvde_reservation_reject'"));
    });

    test('o painel deixa editar os limites da sobreposição', () {
      final s = ler('lib/screens/admin/admin_platform_settings_screen.dart');
      for (final k in [
        'tvde_backtoback_enabled',
        'tvde_backtoback_max_queue',
        'tvde_backtoback_min_stage',
        'tvde_queue_pickup_radius_km',
      ]) {
        expect(s, contains("'$k'"), reason: '$k tem de estar na lista');
      }
      final rides = ler('lib/screens/admin/admin_tvde_rides_screen.dart');
      expect(rides, contains('admin_tvde_force_redispatch'));
      expect(rides, contains('offer_driver_name'));
    });

    test('o cliente lê as três coisas na mesma frase', () {
      final c = ler('lib/screens/client/tvde/tvde_ride_tracking_screen.dart');
      expect(
          c,
          contains(
              'aceitou a tua corrida · está a terminar outra viagem · chega em ~{1} min'));
    });
  });
}

class _Pagina extends StatelessWidget {
  const _Pagina(this.titulo);
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titulo),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const _Pagina('POR CIMA')),
              ),
              child: const Text('empilhar'),
            ),
          ],
        ),
      ),
    );
  }
}
