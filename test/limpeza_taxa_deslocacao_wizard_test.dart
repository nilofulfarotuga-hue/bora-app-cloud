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
  }) async {
    final c = lat == null || lng == null ? null : ll.LatLng(lat, lng);
    coordsDoPreco.add(c);
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
  }) async {
    coordsDaReserva
        .add(lat == null || lng == null ? null : ll.LatLng(lat, lng));
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
}
