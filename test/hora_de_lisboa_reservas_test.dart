// Hora de Lisboa nas reservas (21/10/2026, bloco A3 da super-missão
// fechar-pendencias-2026-10-20).
//
// A Bora só opera em Portugal: o dia e a hora de uma limpeza ou de uma corrida
// marcada são SEMPRE os de Lisboa, seja qual for o fuso do telemóvel. Antes,
// três ecrãs usavam o relógio do aparelho:
//   - o assistente da limpeza (escolha, limite de antecedência e envio);
//   - o acompanhamento da limpeza (a linha "Quando");
//   - "As minhas reservas" do Motorista (o cartão e o "Mudar hora").
//
// Cada teste diz o resultado em hora de Lisboa e tem de dar o mesmo com o
// relógio do processo em Lisboa, em UTC, no Brasil ou no Japão:
//   TZ=UTC1 flutter test test/hora_de_lisboa_reservas_test.dart   (UTC)
//   TZ=BRT3 …                                                      (UTC-2)
//   TZ=JST-9 …                                                     (UTC+10)
// (no Windows o runtime soma +1 h de verão — ver a nota
// tz-muda-o-relogio-do-dart-no-windows; os testes não dependem disso.)
//
// A mudança de hora de 2026 é no domingo 25/10: às 02:00 de verão o relógio
// volta à 01:00, e a 01:00–02:00 repete-se. Escolher 01:30 nesse dia dá a
// PRIMEIRA vez (ainda de verão); 03:00 já é de inverno.
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_tracking_screen.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_wizard_screen.dart';
import 'package:bora_app/screens/client/tvde/tvde_my_reservations_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// ── stores de mentira ──────────────────────────────────────────────────────

class _Limpezas extends CleaningStore {
  /// O instante que o assistente mandou para a lista de profissionais.
  final List<DateTime> vistos = [];

  /// O instante que o assistente mandou para criar a reserva.
  final List<DateTime> criadas = [];

  @override
  Future<int> getSettingInt(String key, int fallback) async =>
      key == 'cleaning_min_lead_hours' ? 12 : fallback;

  @override
  Future<void> refreshStripeEnabled() async {}

  @override
  void trackBooking(CleaningBooking booking) {}

  @override
  Future<CleaningQuote?> quote({
    required String cleaningType,
    required String pricingMode,
    String? homeSize,
    int? hours,
    String recurrence = 'single',
    String productsBy = 'client',
  }) async =>
      const CleaningQuote(
        baseCents: 3000,
        typeSurchargeCents: 0,
        recurringDiscountCents: 0,
        productsFeeCents: 0,
        totalCents: 3000,
        durationMin: 180,
      );

  @override
  Future<List<AvailableCleaner>> listAvailableCleaners({
    required DateTime scheduledAt,
    required int durationMin,
    double? lat,
    double? lng,
  }) async {
    vistos.add(scheduledAt);
    return const [];
  }

  @override
  Future<CleaningBooking?> createBooking({
    required String cleaningType,
    required String pricingMode,
    String? homeSize,
    int? hours,
    required DateTime scheduledAt,
    required String recurrence,
    required String productsBy,
    required String paymentMethod,
    required String addressStreet,
    required String addressCity,
    required String addressPostal,
    double? lat,
    double? lng,
    String notes = '',
    String? requestedCleanerId,
  }) async {
    criadas.add(scheduledAt);
    return null; // o ecrã pára aqui, sem pagar nem navegar
  }
}

class _Corridas extends TvdeStore {
  _Corridas(this._l);
  final List<TvdeRide> _l;

  /// A hora nova que o ecrã mandou para o servidor.
  final List<DateTime> mudadas = [];

  @override
  List<TvdeRide> get reservations => _l;
  @override
  Future<Map<String, int>> loadReservationLimits() async =>
      {'freeCancelHours': 2, 'maxAdvanceDays': 30, 'minAdvanceMinutes': 30};
  @override
  Future<bool> reservationDestChangeEnabled() async => false;
  @override
  Future<void> loadMyReservations() async {}
  @override
  Future<Map<String, dynamic>> rescheduleReservation(
      String rideId, DateTime novaHora) async {
    mudadas.add(novaHora);
    return {'ok': true, 'motorista_mantem': true};
  }
}

// ── ajudantes ──────────────────────────────────────────────────────────────

/// Relógio de 24 horas: o selector de hora aceita 0–23 sem AM/PM.
Widget _app(Widget home) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: home,
    );

/// Abre o selector de data (aceita o dia proposto) e o de hora (escreve
/// [hh]:[mm] no teclado) e fecha ambos.
Future<void> _escolheDiaProposto(WidgetTester t, String hh, String mm) async {
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  await _escreveHora(t, hh, mm);
}

/// Os dois campos do selector de hora (hora, minuto) — só os do diálogo: por
/// baixo dele o assistente tem os seus (rua, cidade, …).
Finder _camposDaHora() =>
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));

Future<void> _escreveHora(WidgetTester t, String hh, String mm) async {
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await t.pumpAndSettle();
  await t.enterText(_camposDaHora().at(0), hh);
  await t.enterText(_camposDaHora().at(1), mm);
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
}

/// Põe o assistente no passo 2 com o relógio parado em [agora].
Future<_Limpezas> _abreAssistente(WidgetTester t, DateTime agora) async {
  await t.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final store = _Limpezas();
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CleaningStore>.value(value: store),
      ChangeNotifierProvider<CartStore>(create: (_) => CartStore()),
    ],
    child: _app(CleaningWizardScreen(agora: () => agora)),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Continuar')); // passo 1 → passo 2
  await t.pumpAndSettle();
  expect(find.text('Escolher data e hora'), findsOneWidget);
  return store;
}

Future<void> _preencheMorada(WidgetTester t) async {
  final campos = find.byType(TextField);
  await t.enterText(campos.at(0), 'Rua do Teste 12');
  await t.enterText(campos.at(1), 'Guarda');
  await t.pump();
}

void main() {
  group('assistente da limpeza — escolha em hora de Lisboa', () {
    // Sábado 24/10/2026, 10:00 UTC (11:00 em Lisboa, ainda verão). A 12 h de
    // antecedência o mais cedo é 24/10 22:00 UTC; o selector propõe a hora a
    // seguir (23:00 UTC = 00:00 de domingo em Lisboa, dia 25).
    final vesperaDaMudanca = DateTime.utc(2026, 10, 24, 10);

    testWidgets('25/10 às 03:00 (já inverno) grava 03:00 UTC e mostra 03:00',
        (t) async {
      final store = await _abreAssistente(t, vesperaDaMudanca);
      await t.tap(find.text('Escolher data e hora'));
      await t.pumpAndSettle();
      await _escolheDiaProposto(t, '03', '00');

      // O selector propôs o dia 25 (de Lisboa), não o do fuso do telemóvel.
      expect(find.text('25/10/2026 às 03:00'), findsOneWidget);

      await _preencheMorada(t);
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(store.vistos, hasLength(1));
      expect(store.vistos.single.toUtc(), DateTime.utc(2026, 10, 25, 3));
      expect(store.vistos.single.toUtc().toIso8601String(),
          '2026-10-25T03:00:00.000Z');
    });

    testWidgets(
        '25/10 às 01:30 (hora repetida) grava a primeira, 00:30 UTC, '
        'e continua a mostrar 01:30', (t) async {
      final store = await _abreAssistente(t, vesperaDaMudanca);
      await t.tap(find.text('Escolher data e hora'));
      await t.pumpAndSettle();
      await _escolheDiaProposto(t, '01', '30');

      expect(find.text('25/10/2026 às 01:30'), findsOneWidget);

      await _preencheMorada(t);
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(store.vistos.single.toUtc(), DateTime.utc(2026, 10, 25, 0, 30));
    });

    testWidgets('o que se manda ao criar é o mesmo instante que se viu',
        (t) async {
      final store = await _abreAssistente(t, vesperaDaMudanca);
      await t.tap(find.text('Escolher data e hora'));
      await t.pumpAndSettle();
      await _escolheDiaProposto(t, '14', '00');
      await _preencheMorada(t);
      await t.tap(find.text('Continuar')); // passo 3
      await t.pumpAndSettle();
      await t.tap(find.text('Encomenda com obrigação de pagar'));
      await t.pumpAndSettle();

      // 25/10 às 14:00 de Lisboa = 14:00 UTC (já é inverno).
      expect(store.criadas, hasLength(1));
      expect(store.criadas.single.toUtc(), DateTime.utc(2026, 10, 25, 14));
      expect(store.vistos.single.toUtc(), store.criadas.single.toUtc());
    });

    testWidgets(
        'antecedência mínima conta em instantes: 12:00 de Lisboa recusa-se, '
        '13:00 aceita-se', (t) async {
      // Domingo 25/10, 00:30 UTC (01:30 em Lisboa, a primeira vez). Mais
      // cedo possível: 12:30 UTC = 12:30 de Lisboa (já inverno).
      final agora = DateTime.utc(2026, 10, 25, 0, 30);
      final store = await _abreAssistente(t, agora);
      await _preencheMorada(t);

      await t.tap(find.text('Escolher data e hora'));
      await t.pumpAndSettle();
      await _escolheDiaProposto(t, '12', '00');
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(find.textContaining('pelo menos 12 h de antecedência'),
          findsOneWidget);
      expect(store.vistos, isEmpty);
      await t.pump(const Duration(seconds: 5)); // o aviso sai de cima do botão
      await t.pumpAndSettle();

      await t.tap(find.text('25/10/2026 às 12:00'));
      await t.pumpAndSettle();
      await _escolheDiaProposto(t, '13', '00');
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(store.vistos, hasLength(1));
      expect(store.vistos.single.toUtc(), DateTime.utc(2026, 10, 25, 13));
    });
  });

  group('acompanhamento da limpeza — a linha "Quando"', () {
    Future<void> abre(WidgetTester t, String scheduledAtUtc) async {
      await t.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final b = CleaningBooking.fromSupabase({
        'id': 'l1',
        'client_user_id': 'c',
        'scheduled_at': scheduledAtUtc,
        'status': 'accepted',
        'payment_method': 'cash',
        'payment_status': 'unpaid',
        'address_street': 'Rua do Teste 12',
      });
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CleaningStore>(create: (_) => _Limpezas()),
        ],
        child: _app(CleaningTrackingScreen(booking: b)),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('verão: 22:30 UTC é 23:30 em Lisboa', (t) async {
      await abre(t, '2026-07-10T22:30:00Z');
      expect(find.text('10/07/2026 às 23:30'), findsOneWidget);
    });

    testWidgets('depois da mudança de hora: 08:15 UTC é 08:15 em Lisboa',
        (t) async {
      await abre(t, '2026-10-25T08:15:00Z');
      expect(find.text('25/10/2026 às 08:15'), findsOneWidget);
    });

    testWidgets('a hora repetida: 00:30 UTC e 01:30 UTC dizem ambas 01:30',
        (t) async {
      await abre(t, '2026-10-25T00:30:00Z');
      expect(find.text('25/10/2026 às 01:30'), findsOneWidget);
    });
  });

  group('"As minhas reservas" do Motorista', () {
    TvdeRide corrida(DateTime quandoUtc) => TvdeRide.fromMap({
          'id': 'c1',
          'client_id': 'c',
          'status': 'agendada',
          'reservation_status': 'atribuida',
          'payment_method': 'cash',
          'payment_status': 'pending',
          'scheduled_at': quandoUtc.toIso8601String(),
          'dest_label': 'Hospital Sousa Martins, Guarda',
          'origin_label': 'Praça Luís de Camões, Guarda, Portugal',
        });

    Future<_Corridas> abre(WidgetTester t, DateTime quandoUtc) async {
      await t.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final store = _Corridas([corrida(quandoUtc)]);
      await t.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<TvdeStore>.value(value: store)],
        child: _app(const TvdeMyReservationsScreen()),
      ));
      await t.pumpAndSettle();
      return store;
    }

    testWidgets('o cartão mostra a hora de Lisboa (verão)', (t) async {
      await abre(t, DateTime.utc(2026, 7, 10, 22, 30));
      expect(find.textContaining('10 jul · 23:30'), findsOneWidget);
    });

    testWidgets('o cartão mostra a hora de Lisboa (inverno)', (t) async {
      await abre(t, DateTime.utc(2026, 12, 1, 8, 15));
      expect(find.textContaining('1 dez · 08:15'), findsOneWidget);
    });

    testWidgets(
        '"Mudar hora": propõe a hora de Lisboa e manda a hora que se escreveu',
        (t) async {
      // Daqui a 2 dias às 08:15 de Lisboa (sempre no futuro e fora do buraco
      // da mudança de hora).
      final hoje = paredeLisboa(DateTime.now());
      final dia = DateTime.utc(hoje.year, hoje.month, hoje.day + 2);
      final marcada =
          instanteDeLisboa(DateTime.utc(dia.year, dia.month, dia.day, 8, 15));
      final store = await abre(t, marcada);

      await t.tap(find.byKey(const Key('reserva_mudar_hora_c1')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK')); // fica no dia marcado (o de Lisboa)
      await t.pumpAndSettle();
      // O selector abre na hora de Lisboa da reserva, não na do telemóvel.
      await t.tap(find.byIcon(Icons.keyboard_outlined));
      await t.pumpAndSettle();
      final horaProposta = t.widgetList<TextField>(_camposDaHora()).toList();
      expect(horaProposta.first.controller!.text, '08');
      expect(horaProposta.last.controller!.text, '15');
      await t.enterText(_camposDaHora().at(0), '08');
      await t.enterText(_camposDaHora().at(1), '45');
      await t.pump();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();

      expect(find.textContaining('08:45'), findsWidgets); // o aviso mostra-a
      await t.tap(find.text('Mudar'));
      await t.pumpAndSettle();

      expect(store.mudadas, hasLength(1));
      expect(TvdeStore.horaLisboaParaRpc(store.mudadas.single),
          '${dia.year}-${_dois(dia.month)}-${_dois(dia.day)} 08:45');
    });
  });
}

String _dois(int n) => n.toString().padLeft(2, '0');
