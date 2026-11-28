// Limpeza longe da Guarda (missão limpeza-longe-e-equipa-2026-11-19, Bloco A).
//
// O que se prova aqui, no ecrã de marcar limpeza:
//  - as coordenadas que vão para o preço, para a lista de profissionais e
//    para a reserva são as da MORADA DA LIMPEZA, não as do carrinho;
//  - o preço com morada mostra a linha "Taxa de deslocação (X km de estrada)"
//    com os km que o servidor devolveu, e o total já com ela;
//  - a menos de 10 km (taxa 0) não aparece linha nenhuma;
//  - fora da área: "Ainda não fazemos limpezas a mais de 32 km da Guarda"
//    (número do servidor) e não se passa ao passo de pagar.
//
// O servidor está de mentira: devolve o que a `cleaning_quote_at` devolveu em
// produção a 19/11/2026 (Celorico T4+ Standard = 70 € + 29 € = 99 €).
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_wizard_screen.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

const _celorico = ll.LatLng(40.6363, -7.3929);
const _pinhel = ll.LatLng(40.7740, -7.0630);
const _guarda = ll.LatLng(40.5373, -7.2676);

class _Limpezas extends CleaningStore {
  final List<ll.LatLng?> coordsDoPreco = [];
  final List<ll.LatLng?> coordsDaLista = [];
  final List<ll.LatLng?> coordsDaReserva = [];
  final List<int> equipasPedidas = [];
  final List<int> equipasCriadas = [];

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
    double? lat,
    double? lng,
    int teamSize = 1,
  }) async {
    final c = lat == null || lng == null ? null : ll.LatLng(lat, lng);
    coordsDoPreco.add(c);
    equipasPedidas.add(teamSize);
    // Equipa em Celorico, Standard, por hora (o que a cleaning_quote_team
    // devolve): 4 h × 12 € = 48 € de trabalho + 29 € de deslocação cada.
    if (teamSize > 1 && pricingMode == 'hourly') {
      final work = 1200 * (hours ?? 4);
      final travel = c == _celorico ? 2900 : 0;
      final share = work + travel;
      return CleaningQuote(
        baseCents: work,
        typeSurchargeCents: 0,
        recurringDiscountCents: 0,
        productsFeeCents: 0,
        totalCents: share * teamSize,
        durationMin: (hours ?? 4) * 60,
        travelFeeCents: travel,
        travelDistanceKm: c == _celorico ? 28.6 : null,
        maxDistanceKm: 32,
        teamSize: teamSize,
        shares: [
          for (var i = 1; i <= teamSize; i++)
            TeamShare(
                slot: i,
                shareCents: share,
                cleanerEarningsCents: share - (work * 15 ~/ 100)),
        ],
      );
    }
    const base = 7000; // T4+ Standard
    if (c == _celorico) {
      return const CleaningQuote(
        baseCents: base,
        typeSurchargeCents: 0,
        recurringDiscountCents: 0,
        productsFeeCents: 0,
        totalCents: base + 2900,
        durationMin: 300,
        travelFeeCents: 2900,
        travelDistanceKm: 28.6,
        maxDistanceKm: 32,
      );
    }
    if (c == _pinhel) {
      return const CleaningQuote(
        baseCents: base,
        typeSurchargeCents: 0,
        recurringDiscountCents: 0,
        productsFeeCents: 0,
        totalCents: base,
        durationMin: 300,
        travelDistanceKm: 46.1,
        outOfArea: true,
        maxDistanceKm: 32,
      );
    }
    return CleaningQuote(
      baseCents: base,
      typeSurchargeCents: 0,
      recurringDiscountCents: 0,
      productsFeeCents: 0,
      totalCents: base,
      durationMin: 300,
      travelDistanceKm: c == null ? null : 1.2,
      maxDistanceKm: 32,
    );
  }

  @override
  Future<List<AvailableCleaner>> listAvailableCleaners({
    required DateTime scheduledAt,
    required int durationMin,
    double? lat,
    double? lng,
  }) async {
    coordsDaLista.add(lat == null || lng == null ? null : ll.LatLng(lat, lng));
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
    int teamSize = 1,
    String? checkinValeId,
  }) async {
    coordsDaReserva
        .add(lat == null || lng == null ? null : ll.LatLng(lat, lng));
    equipasCriadas.add(teamSize);
    return null;
  }
}

Widget _app(Widget home) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: home,
    );

/// A procura da morada escrita, de mentira: devolve as coordenadas da terra.
Future<ll.LatLng?> _procura(String morada) async {
  final m = morada.toLowerCase();
  if (m.contains('celorico')) return _celorico;
  if (m.contains('pinhel')) return _pinhel;
  if (m.contains('guarda')) return _guarda;
  return null;
}

/// Carrinho com a morada de ENTREGAS na Guarda (a cicatriz: era daqui que
/// vinham as coordenadas da limpeza).
CartStore _carrinhoNaGuarda() {
  final cart = CartStore();
  cart.updateDeliveryAddress(
    street: 'Rua do Comércio 1',
    city: 'Guarda',
    postalCode: '6300-000',
    location: _guarda,
  );
  return cart;
}

Future<_Limpezas> _chegaAoPasso2(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final store = _Limpezas();
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CleaningStore>.value(value: store),
      ChangeNotifierProvider<CartStore>.value(value: _carrinhoNaGuarda()),
    ],
    child: _app(CleaningWizardScreen(
      agora: () => DateTime.utc(2026, 11, 19, 10),
      procurarMorada: _procura,
      garantirContacto: _contactoOk,
    )),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Continuar'));
  await t.pumpAndSettle();
  // Data: o dia proposto às 14:00.
  await t.tap(find.text('Escolher data e hora'));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  return store;
}

Future<void> _escreveMorada(
    WidgetTester t, String rua, String cidade, String postal) async {
  final campos = find.byType(TextField);
  await t.enterText(campos.at(0), rua);
  await t.enterText(campos.at(1), cidade);
  await t.enterText(campos.at(2), postal);
  await t.pump(const Duration(seconds: 1));
  await t.pumpAndSettle();
}

/// O telemóvel do cliente é outro teste (telefone_internacional_test.dart);
/// aqui a porta "Falta só isto" deixa sempre passar.
Future<bool> _contactoOk(BuildContext _) async => true;

void main() {
  testWidgets(
      'Celorico: coordenadas da morada da limpeza, linha da taxa com km de '
      'estrada e total 99 €', (t) async {
    final store = await _chegaAoPasso2(t);
    await _escreveMorada(t, 'Rua da Vivenda 3', 'Celorico da Beira', '6360-000');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();

    // O preço e a lista foram com as coordenadas de Celorico, não da Guarda.
    expect(store.coordsDoPreco.last, _celorico);
    expect(store.coordsDaLista.single, _celorico);
    expect(find.text('Taxa de deslocação (28,6 km de estrada)'), findsOneWidget);
    expect(find.text('+ €29,00'), findsOneWidget);
    expect(find.text('€99,00'), findsOneWidget);

    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.coordsDaReserva.single, _celorico);
  });

  testWidgets('Guarda centro: sem linha de taxa', (t) async {
    final store = await _chegaAoPasso2(t);
    await _escreveMorada(t, 'Rua Marquês de Pombal 10', 'Guarda', '6300-000');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(store.coordsDaLista.single, _guarda);
    expect(find.textContaining('Taxa de deslocação'), findsNothing);
    expect(find.text('€70,00'), findsNWidgets(2)); // base e total
  });

  testWidgets(
      'Pinhel: mensagem com o máximo do servidor e não passa ao pagamento',
      (t) async {
    final store = await _chegaAoPasso2(t);
    await _escreveMorada(t, 'Rua Central 2', 'Pinhel', '6400-000');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    expect(
        find.text('Ainda não fazemos limpezas a mais de 32 km da Guarda.'),
        findsWidgets);
    expect(store.coordsDaLista, isEmpty);
    expect(find.text('Encomenda com obrigação de pagar'), findsNothing);
  });

  test('reserva lê a taxa e os km de estrada gravados pelo servidor', () {
    final b = CleaningBooking.fromSupabase({
      'id': 'l1',
      'client_user_id': 'c',
      'scheduled_at': '2026-11-20T10:00:00Z',
      'total_cents': 9900,
      'travel_fee_cents': 2900,
      'travel_distance_km': 28.6,
      'lat': 40.6363,
      'lng': -7.3929,
    });
    expect(b.travelFeeCents, 2900);
    expect(b.travelDistanceKm, 28.6);
    expect(b.lat, 40.6363);
    expect(CleaningLabels.travelFeeLabel(b.travelDistanceKm),
        'Taxa de deslocação (28,6 km de estrada)');
    expect(CleaningLabels.outOfAreaMessage(32),
        'Ainda não fazemos limpezas a mais de 32 km da Guarda.');
    // Reserva antiga, sem as colunas novas: taxa 0, sem linha.
    final antiga = CleaningBooking.fromSupabase({'id': 'l0'});
    expect(antiga.travelFeeCents, 0);
    expect(antiga.travelDistanceKm, isNull);
  });

  testWidgets(
      'Equipa: Celorico, Standard, 4 h, 2 profissionais → 154 €, '
      '2 × 29 € de deslocação e 77 € em dinheiro a cada uma', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final store = _Limpezas();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CleaningStore>.value(value: store),
        ChangeNotifierProvider<CartStore>.value(value: _carrinhoNaGuarda()),
      ],
      child: _app(CleaningWizardScreen(
        agora: () => DateTime.utc(2026, 11, 19, 10),
        procurarMorada: _procura,
        garantirContacto: _contactoOk,
      )),
    ));
    await t.pumpAndSettle();
    // Por hora, 4 h, 2 profissionais.
    await t.tap(find.text('Por hora'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.add_circle_outline));
    await t.pumpAndSettle();
    expect(find.text('4 h'), findsOneWidget);
    expect(find.text('Quantas profissionais?'), findsOneWidget);
    await t.tap(find.text('2'));
    await t.pumpAndSettle();
    expect(store.equipasPedidas.last, 2);

    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Escolher data e hora'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await _escreveMorada(t, 'Rua da Vivenda 3', 'Celorico da Beira', '6360-000');
    await t.tap(find.text('Continuar'));
    await t.pumpAndSettle();

    expect(find.text('2 profissionais × 4 h'), findsOneWidget);
    expect(find.text('2 × €48,00'), findsOneWidget);
    expect(find.text('+ 2 × €29,00'), findsOneWidget);
    expect(find.text('€154,00'), findsOneWidget);
    expect(find.text('Em dinheiro: entregas €77,00 a cada profissional.'),
        findsOneWidget);

    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.equipasCriadas.single, 2);
    expect(store.coordsDaReserva.single, _celorico);
  });

  testWidgets('T4+ por tamanho: o aviso da casa grande passa a 2 profissionais',
      (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final store = _Limpezas();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CleaningStore>.value(value: store),
        ChangeNotifierProvider<CartStore>.value(value: _carrinhoNaGuarda()),
      ],
      child: _app(CleaningWizardScreen(
        agora: () => DateTime.utc(2026, 11, 19, 10),
        procurarMorada: _procura,
        garantirContacto: _contactoOk,
      )),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('limpeza_sugere_equipa')), findsNothing);
    await t.tap(find.text(CleaningLabels.sizes['t4plus']!));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('limpeza_sugere_equipa')));
    await t.pumpAndSettle();
    // T4+ = 300 min → 2,5 h por profissional → 3 h cada, 2 profissionais.
    expect(find.text('3 h'), findsOneWidget);
    expect(store.equipasPedidas.last, 2);
  });

  test('reserva de equipa: a vaga 1 tem o total, cada uma a sua parte', () {
    final principal = CleaningBooking.fromSupabase({
      'id': 'p1',
      'pricing_mode': 'hourly',
      'hours': 4,
      'base_cents': 4800,
      'total_cents': 15400,
      'travel_fee_cents': 2900,
      'team_group_id': 'g1',
      'team_size': 2,
      'team_slot': 1,
      'team_total_cents': 15400,
      'share_cents': 7700,
      'cleaner_earnings_cents': 6980,
      'bora_fee_cents': 720,
    });
    final irma = CleaningBooking.fromSupabase({
      'id': 'p2',
      'total_cents': 0,
      'team_group_id': 'g1',
      'team_size': 2,
      'team_slot': 2,
      'team_total_cents': 15400,
      'share_cents': 7700,
      'cleaner_earnings_cents': 6980,
    });
    expect(principal.isTeam, isTrue);
    expect(principal.isTeamSister, isFalse);
    expect(irma.isTeamSister, isTrue);
    expect(principal.clientTotalCents, 15400);
    expect(principal.myShareCents, 7700); // em dinheiro, só a parte dela
    expect(irma.myShareCents, 7700);
    expect(principal.teamProductsCents, 0);
    // Bora 7,20 + 7,20 = 14,40; cada profissional 69,80.
    expect(principal.cleanerEarningsCents, 6980);
    // Fora de equipa nada muda.
    final so = CleaningBooking.fromSupabase({'id': 's', 'total_cents': 9900});
    expect(so.isTeam, isFalse);
    expect(so.myShareCents, 9900);
  });
}
