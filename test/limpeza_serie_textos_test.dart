// Série de limpeza — textos do lado da app (01/11/2026, missão
// app-fechar-2026-11-01, bloco B5; achados S1–S4 de
// docs/propostas/revisao-casa-peso-convidado-2026-11-01.md).
//
// Cicatriz (31/10, série semanal da Mayra): o cliente cancelou UMA limpeza e
// a série morreu sem ele o pedir. O servidor já não a mata; a app tem de
// dizer o mesmo:
//   S1 — a marcação recorrente mostra "Semanal · próxima: <dia/mês hh:mm>"
//        (hora de Lisboa) e, com a série parada, "Série parada" em vez do
//        botão;
//   S2 — o diálogo "Cancelar limpeza" diz que é SÓ esta e tem o segundo botão
//        "Parar a série toda";
//   S3 — na lista, o cartão leva o selo da série e as ativas vêm pela ordem
//        em que acontecem;
//   S4 — "Cliente habitual" quando o cliente pediu a profissional.
// Sem rede: o store é de mentira (as leituras ao Supabase são substituídas).
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/screens/admin/admin_cleaning_bookings_screen.dart'
    show rotuloDevolucaoLimpeza;
import 'package:bora_app/screens/client/cleaning/cleaning_bookings_screen.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_tracking_screen.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Datas longe no futuro e em hora de inverno (Lisboa = UTC): o texto não
// depende do dia em que o teste corre nem do fuso do computador.
const _quando = '2030-01-07T10:00:00Z'; // segunda 07/01/2030, 10:00 Lisboa
final _proximaServidor = DateTime.utc(2030, 1, 14, 10); // 14/01 10:00

CleaningBooking _reserva({
  String id = 'b1',
  String recurrence = 'weekly',
  String? grupo = 'g1',
  String status = 'scheduled',
  String quando = _quando,
  String? pedida,
}) =>
    CleaningBooking.fromSupabase({
      'id': id,
      'client_user_id': 'c1',
      'recurrence': recurrence,
      'recurrence_group_id': grupo,
      'requested_cleaner_id': pedida,
      'cleaning_type': 'standard',
      'pricing_mode': 'fixed',
      'home_size': 't2',
      'scheduled_at': quando,
      'status': status,
      'payment_method': 'cash',
      'payment_status': 'cash_pending',
      'address_street': 'Rua do Teste 12',
      'address_city': 'Guarda',
      'total_cents': 4500,
    });

class _Limpezas extends CleaningStore {
  _Limpezas({
    this.parada = false,
    this.proxima,
    this.previsao = SeriePrevisao.vazia,
    List<CleaningBooking> lista = const [],
  }) : _lista = lista;

  final bool parada;
  final DateTime? proxima;
  final SeriePrevisao previsao;
  final List<CleaningBooking> _lista;

  final List<String> canceladas = [];
  final List<String> seriesParadas = [];
  final List<String> lidas = [];
  final Map<String, SerieEstado> _estado = {};

  @override
  List<CleaningBooking> get bookings => _lista;
  @override
  Future<int> getSettingInt(String key, int fallback) async => fallback;
  @override
  Future<void> refreshStripeEnabled() async {}
  @override
  void trackBooking(CleaningBooking booking) {}
  @override
  Future<void> loadMyBookings() async {}
  @override
  Future<void> refreshTracked() async {}

  @override
  SerieEstado? serieEmCache(String groupId) => _estado[groupId];

  @override
  Future<SerieEstado> estadoDaSerie(String groupId) async {
    lidas.add(groupId);
    final e = _estado[groupId]?.parada == true
        ? _estado[groupId]!
        : SerieEstado(parada: parada, proxima: proxima);
    _estado[groupId] = e;
    notifyListeners();
    return e;
  }

  @override
  Future<CleaningBooking?> cancelBooking(String bookingId,
      {String reason = ''}) async {
    canceladas.add(bookingId);
    return null;
  }

  @override
  Future<void> cancelSeries(String groupId) async {
    seriesParadas.add(groupId);
    _estado[groupId] = const SerieEstado(parada: true);
    notifyListeners();
  }

  @override
  Future<SeriePrevisao> previsaoSerie(String groupId) async => previsao;
}

/// Store só com a rede cortada: corre o cancelSeries VERDADEIRO e regista os
/// pedidos de estorno (zerar B2, 02/11/2026; desde M10 b2, 09/11, não pode
/// haver nenhum: o servidor devolve à Carteira Bora).
class _SerieSemRede extends CleaningStore {
  final List<String> paradas = [];
  final List<String> estornos = [];

  @override
  Future<void> pararSerieNoServidor(String groupId) async => paradas.add(groupId);
  @override
  Future<void> reversePayment(String bookingId) async => estornos.add(bookingId);
  @override
  Future<void> loadMyBookings() async {}
}

// A forma exata que o cleaning_series_preview devolveu na prova em rollback
// (02/11/2026): cartão e MB Way pagos (3200 cada), MB Way por pagar.
final _previsaoDoServidor = <String, dynamic>{
  'n': 4,
  'devolve_cents': 6400,
  'limpezas': [
    {'id': 'a', 'payment_method': 'card', 'pago': true, 'taxa_cents': 0, 'devolve_cents': 3200},
    {'id': 'b', 'payment_method': 'mbway', 'pago': true, 'taxa_cents': 0, 'devolve_cents': 3200},
    {'id': 'c', 'payment_method': 'mbway', 'pago': false, 'taxa_cents': 0, 'devolve_cents': 0},
    {'id': 'd', 'payment_method': 'cash', 'pago': false, 'taxa_cents': 0, 'devolve_cents': 0},
  ],
};

Future<_Limpezas> _abreAcompanhamento(
  WidgetTester t,
  CleaningBooking b, {
  bool parada = false,
  DateTime? proxima,
  SeriePrevisao previsao = SeriePrevisao.vazia,
  List<CleaningBooking> lista = const [],
}) async {
  await t.binding.setSurfaceSize(const Size(500, 2000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final store = _Limpezas(
      parada: parada, proxima: proxima, previsao: previsao, lista: lista);
  await t.pumpWidget(ChangeNotifierProvider<CleaningStore>.value(
    value: store,
    child: MaterialApp(home: CleaningTrackingScreen(booking: b)),
  ));
  await t.pumpAndSettle();
  return store;
}

Finder _noDialogo(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  group('S1 — linha da série no acompanhamento', () {
    testWidgets('recorrente: "Semanal · próxima: 14/01 10:00" e o botão',
        (t) async {
      final store =
          await _abreAcompanhamento(t, _reserva(), proxima: _proximaServidor);
      expect(store.lidas, ['g1']);
      expect(find.text('Semanal · próxima: 14/01 10:00'), findsOneWidget);
      expect(find.byKey(const Key('limpeza_parar_serie')), findsOneWidget);
      expect(find.text('Série parada'), findsNothing);
    });

    testWidgets('quinzenal tem o mesmo selo', (t) async {
      await _abreAcompanhamento(t, _reserva(recurrence: 'biweekly'),
          proxima: DateTime.utc(2030, 1, 21, 10));
      expect(find.text('Quinzenal · próxima: 21/01 10:00'), findsOneWidget);
    });

    testWidgets('a próxima é a irmã já marcada, não a que ainda se vai gerar',
        (t) async {
      final irma = _reserva(id: 'b2', quando: '2030-01-14T10:00:00Z');
      await _abreAcompanhamento(t, _reserva(),
          proxima: DateTime.utc(2030, 1, 21, 10), lista: [_reserva(), irma]);
      expect(find.text('Semanal · próxima: 14/01 10:00'), findsOneWidget);
    });

    testWidgets('série parada: "Série parada" em vez do botão', (t) async {
      await _abreAcompanhamento(t, _reserva(), parada: true);
      expect(find.text('Série parada'), findsOneWidget);
      expect(find.byKey(const Key('limpeza_parar_serie')), findsNothing);
      expect(find.textContaining('próxima:'), findsNothing);
    });

    testWidgets('limpeza única: sem linha da série e sem leitura', (t) async {
      final store = await _abreAcompanhamento(
          t, _reserva(recurrence: 'single', grupo: null));
      expect(store.lidas, isEmpty);
      expect(find.byKey(const Key('limpeza_serie_linha')), findsNothing);
      expect(find.byKey(const Key('limpeza_parar_serie')), findsNothing);
    });

    testWidgets('a série continua numa limpeza já cancelada', (t) async {
      await _abreAcompanhamento(t, _reserva(status: 'cancelled_client'),
          proxima: _proximaServidor);
      expect(find.text('Semanal · próxima: 14/01 10:00'), findsOneWidget);
      expect(find.byKey(const Key('limpeza_parar_serie')), findsOneWidget);
    });
  });

  group('S2 — "Cancelar limpeza" numa série', () {
    testWidgets('diz "só esta" e cancelar não pára a série', (t) async {
      final store =
          await _abreAcompanhamento(t, _reserva(), proxima: _proximaServidor);
      await t.tap(find.text('Cancelar limpeza'));
      await t.pumpAndSettle();

      expect(
          _noDialogo(find.text(
              'Cancelas só esta limpeza. A série continua na próxima data.')),
          findsOneWidget);
      expect(_noDialogo(find.text('Parar a série toda')), findsOneWidget);

      await t.tap(_noDialogo(find.text('Cancelar limpeza')));
      await t.pumpAndSettle();
      expect(store.canceladas, ['b1']);
      expect(store.seriesParadas, isEmpty);
    });

    testWidgets('"Parar a série toda" pede confirmação e pára a série',
        (t) async {
      final store =
          await _abreAcompanhamento(t, _reserva(), proxima: _proximaServidor);
      await t.tap(find.text('Cancelar limpeza'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('limpeza_cancelar_parar_serie')));
      await t.pumpAndSettle();

      // Confirmação com o que o servidor faz (mais de 24 h → cancelada).
      expect(find.text('Parar a recorrência?'), findsOneWidget);
      expect(
          find.textContaining('são canceladas; as das próximas 24 h mantêm-se'),
          findsOneWidget);
      await t.tap(find.text('Parar série'));
      await t.pumpAndSettle();

      expect(store.seriesParadas, ['g1']);
      expect(store.canceladas, isEmpty,
          reason: 'quem pára a série não cancela por fora a limpeza');
      expect(find.text('Série parada'), findsOneWidget);
      expect(find.byKey(const Key('limpeza_parar_serie')), findsNothing);
    });

    testWidgets('limpeza única: o diálogo não fala de série', (t) async {
      await _abreAcompanhamento(t, _reserva(recurrence: 'single', grupo: null));
      await t.tap(find.text('Cancelar limpeza'));
      await t.pumpAndSettle();
      expect(find.textContaining('Cancelas só esta limpeza'), findsNothing);
      expect(
          find.byKey(const Key('limpeza_cancelar_parar_serie')), findsNothing);
    });

    testWidgets('série já parada: o diálogo não oferece parar outra vez',
        (t) async {
      await _abreAcompanhamento(t, _reserva(), parada: true);
      await t.tap(find.text('Cancelar limpeza'));
      await t.pumpAndSettle();
      expect(find.textContaining('Cancelas só esta limpeza'), findsNothing);
      expect(
          find.byKey(const Key('limpeza_cancelar_parar_serie')), findsNothing);
    });
  });

  group('S3 — lista "As minhas limpezas"', () {
    testWidgets('selo da série no cartão e ativas da mais próxima à mais longe',
        (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final depois = _reserva(id: 'b2', quando: '2030-01-14T10:00:00Z');
      final antes = _reserva(id: 'b1');
      final unica = _reserva(
          id: 'b3',
          recurrence: 'single',
          grupo: null,
          quando: '2030-01-10T10:00:00Z');
      // A base devolve da mais recente para a mais antiga.
      final store = _Limpezas(
          proxima: DateTime.utc(2030, 1, 21, 10),
          lista: [depois, unica, antes]);
      await t.pumpWidget(ChangeNotifierProvider<CleaningStore>.value(
        value: store,
        child: const MaterialApp(home: CleaningBookingsScreen()),
      ));
      await t.pumpAndSettle();

      expect(store.activeBookings.map((b) => b.id), ['b1', 'b3', 'b2']);
      // b1 (07/01): a próxima é a irmã b2 (14/01); b2: a do servidor (21/01).
      expect(
          find.descendant(
              of: find.byKey(const Key('limpeza_selo_serie_b1')),
              matching: find.text('Semanal · próxima: 14/01 10:00')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('limpeza_selo_serie_b2')),
              matching: find.text('Semanal · próxima: 21/01 10:00')),
          findsOneWidget);
      expect(find.byKey(const Key('limpeza_selo_serie_b3')), findsNothing,
          reason: 'limpeza única não tem selo de série');
      // Hora de Lisboa no cartão.
      expect(find.textContaining('07/01 às 10:00'), findsOneWidget);

      final y1 =
          t.getTopLeft(find.byKey(const Key('limpeza_selo_serie_b1'))).dy;
      final y2 =
          t.getTopLeft(find.byKey(const Key('limpeza_selo_serie_b2'))).dy;
      expect(y1, lessThan(y2), reason: 'a mais próxima vem primeiro');
    });

    testWidgets('série parada: o cartão diz "Série parada"', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final store = _Limpezas(parada: true, lista: [_reserva()]);
      await t.pumpWidget(ChangeNotifierProvider<CleaningStore>.value(
        value: store,
        child: const MaterialApp(home: CleaningBookingsScreen()),
      ));
      await t.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byKey(const Key('limpeza_selo_serie_b1')),
              matching: find.text('Série parada')),
          findsOneWidget);
    });
  });

  group('modelo', () {
    test('lê requested_cleaner_id e diz "cliente habitual" só da própria', () {
      final b = _reserva(pedida: 'pro-1');
      expect(b.requestedCleanerId, 'pro-1');
      expect(b.pedidaPor('pro-1'), isTrue);
      expect(b.pedidaPor('pro-2'), isFalse);
      expect(b.pedidaPor(null), isFalse);
      expect(_reserva().pedidaPor('pro-1'), isFalse);
    });

    test('próxima da série: canceladas não contam; data passada não se mostra',
        () {
      final b = _reserva();
      final cancelada = _reserva(
          id: 'b2', quando: '2030-01-14T10:00:00Z', status: 'cancelled_client');
      final outraSerie =
          _reserva(id: 'b9', grupo: 'g9', quando: '2030-01-09T10:00:00Z');
      expect(
          b.proximaDaSerie(
              [b, cancelada, outraSerie], DateTime.utc(2030, 1, 21, 10)),
          DateTime.utc(2030, 1, 21, 10));
      expect(
          b.proximaDaSerie(const [], DateTime.utc(2030, 1, 21, 10),
              agora: DateTime.utc(2030, 2, 1)),
          isNull);
      expect(
          _reserva(recurrence: 'single', grupo: null)
              .proximaDaSerie(const [], DateTime.utc(2030, 1, 21, 10)),
          isNull);
    });

    test('dia e hora de Lisboa, verão e inverno', () {
      expect(CleaningLabels.diaHoraLisboa(DateTime.utc(2030, 1, 14, 10)),
          '14/01 10:00');
      expect(CleaningLabels.diaHoraLisboa(DateTime.utc(2030, 7, 14, 9, 5)),
          '14/07 10:05');
    });
  });

  group('B2 (02/11) — "Parar a série" devolve as limpezas pagas', () {
    test('lê a previsão do servidor tal como vem', () {
      final p = SeriePrevisao.fromJson(_previsaoDoServidor);
      expect(p.devolveCents, 6400);
      expect(p.limpezas.map((l) => l.id), ['a', 'b', 'c', 'd']);
      expect(p.limpezas.where((l) => l.pago).length, 2);
      expect(SeriePrevisao.fromJson(const {}).devolveCents, 0);
    });

    test(
        'M10 b2 (09/11): não pede estorno ao cartão/MB Way — o servidor '
        'devolve à Carteira Bora (pedir os dois devolvia duas vezes)', () async {
      final store = _SerieSemRede();
      await store.cancelSeries('g1');
      expect(store.paradas, ['g1']);
      expect(store.estornos, isEmpty);
      expect(store.serieEmCache('g1')?.parada, isTrue);
    });

    testWidgets('o diálogo diz quanto volta e o aviso confirma o pedido',
        (t) async {
      final store = await _abreAcompanhamento(t, _reserva(),
          proxima: _proximaServidor,
          previsao: SeriePrevisao.fromJson(_previsaoDoServidor));
      await t.tap(find.byKey(const Key('limpeza_parar_serie')));
      await t.pumpAndSettle();

      expect(
          find.text('Devolvemos €64,00 à tua Carteira Bora, podes usar já.'),
          findsOneWidget);
      expect(find.textContaining('cartão ou MB Way'), findsNothing);
      await t.tap(find.text('Parar série'));
      await t.pumpAndSettle();

      expect(store.seriesParadas, ['g1']);
      expect(
          find.text(
              'Recorrência cancelada. Devolvemos €64,00 à tua Carteira Bora, podes usar já.'),
          findsOneWidget);
    });

    testWidgets('sem nada pago, não promete devolução', (t) async {
      await _abreAcompanhamento(t, _reserva(), proxima: _proximaServidor);
      await t.tap(find.byKey(const Key('limpeza_parar_serie')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('limpeza_parar_serie_devolve')), findsNothing);
      await t.tap(find.text('Parar série'));
      await t.pumpAndSettle();
      expect(find.text('Recorrência cancelada.'), findsOneWidget);
    });
  });

  group('M10 b2 (09/11) — painel: para onde voltou o dinheiro da limpeza', () {
    test('série parada e estornada: "Voltou à Carteira Bora"', () {
      expect(
          rotuloDevolucaoLimpeza(
              cancelReason: 'serie_terminada',
              paymentStatus: 'estornado',
              taxaCents: 0),
          'Voltou à Carteira Bora');
    });

    test('cancelamento de uma só continua "Deve voltar ao cliente"', () {
      expect(
          rotuloDevolucaoLimpeza(
              cancelReason: 'mudei de planos',
              paymentStatus: 'estornado',
              taxaCents: 0),
          'Deve voltar ao cliente');
      expect(
          rotuloDevolucaoLimpeza(
              cancelReason: null, paymentStatus: 'released', taxaCents: 1600),
          'Deve voltar ao cliente');
    });

    test('série parada a dinheiro (nada pago): sem linha', () {
      expect(
          rotuloDevolucaoLimpeza(
              cancelReason: 'serie_terminada',
              paymentStatus: 'unpaid',
              taxaCents: 0),
          isNull);
    });
  });
}
