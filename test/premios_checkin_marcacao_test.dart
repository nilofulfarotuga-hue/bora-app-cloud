// Prémios do check-in, Bloco A (28/11/2026, caso Divan): o prémio de limpeza/lavagem entra na
// MARCAÇÃO NORMAL. O que se prova aqui (o servidor está de mentira; o desconto real é do servidor,
// provado em docs/propostas/premios-checkin-bloco-a-2026-11-28/provas.sql, 13/13):
//  - o resumo mostra "Tens 2 h de limpeza grátis (prémio do check-in)" ligado por defeito, a linha
//    "Prémio do check-in − €24,00" e "A pagar" com o resto;
//  - a marcação vai com o vale (p_checkin_vale_id); desligado, vai sem ele e com o total;
//  - Profunda: explica que o prémio paga 2 h Standard e paga-se a diferença;
//  - se o prémio cobre tudo: "Não pagas nada", sem escolher pagamento, e vai como cartão
//    (o servidor marca 'premio' e não se cobra nada);
//  - o acompanhamento lê checkin_premio_cents; a lavagem também.
import 'dart:io';

import 'package:bora_app/models/carwash_models.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/screens/client/cleaning/cleaning_wizard_screen.dart';
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/cleaning_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

const _guarda = ll.LatLng(40.5373, -7.2676);

const _premio = PremioServico(valeId: 'vale-30-dias', tipo: 'limpeza', valorCents: 2400, horas: 2);

class _Marcacao {
  _Marcacao(this.metodo, this.vale);
  final String metodo;
  final String? vale;
}

class _Limpezas extends CleaningStore {
  _Limpezas({this.totalCents = 7000, this.cartao = true});
  final int totalCents;
  final bool cartao;
  final List<_Marcacao> marcacoes = [];

  @override
  bool get stripeEnabled => cartao;

  @override
  Future<int> getSettingInt(String key, int fallback) async => key == 'cleaning_min_lead_hours' ? 12 : fallback;

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
  }) async =>
      CleaningQuote(
        baseCents: totalCents,
        typeSurchargeCents: 0,
        recurringDiscountCents: 0,
        productsFeeCents: 0,
        totalCents: totalCents,
        durationMin: 240,
        maxDistanceKm: 32,
      );

  @override
  Future<List<AvailableCleaner>> listAvailableCleaners({
    required DateTime scheduledAt,
    required int durationMin,
    double? lat,
    double? lng,
  }) async =>
      const [];

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
    marcacoes.add(_Marcacao(paymentMethod, checkinValeId));
    return null;
  }
}

Future<bool> _contactoOk(BuildContext _) async => true;
Future<ll.LatLng?> _procura(String _) async => _guarda;

/// Chega ao passo "Confirmar" com a morada na Guarda.
Future<_Limpezas> _chegaAoResumo(WidgetTester t, {int totalCents = 7000, bool cartao = true, PremioServico? premio = _premio}) async {
  await t.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final store = _Limpezas(totalCents: totalCents, cartao: cartao);
  final cart = CartStore()
    ..updateDeliveryAddress(street: 'Rua do Comércio 1', city: 'Guarda', postalCode: '6300-000', location: _guarda);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CleaningStore>.value(value: store),
      ChangeNotifierProvider<CartStore>.value(value: cart),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: CleaningWizardScreen(
        agora: () => DateTime.utc(2026, 11, 28, 10),
        procurarMorada: _procura,
        garantirContacto: _contactoOk,
        premioParaUsar: () async => premio,
      ),
    ),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Continuar'));
  await t.pumpAndSettle();
  await t.tap(find.text('Escolher data e hora'));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  final campos = find.byType(TextField);
  await t.enterText(campos.at(0), 'Rua Marquês de Pombal 10');
  await t.enterText(campos.at(1), 'Guarda');
  await t.enterText(campos.at(2), '6300-000');
  await t.pump(const Duration(seconds: 1));
  await t.pumpAndSettle();
  await t.tap(find.text('Continuar'));
  await t.pumpAndSettle();
  return store;
}

void main() {
  test('o prémio do servidor lê-se e nunca desconta mais do que o total', () {
    final p = PremioServico.fromJson({'vale_id': 'v1', 'tipo': 'limpeza', 'horas': 2, 'valor_cents': 2400, 'valido_ate': '2026-12-28T00:00:00Z'})!;
    expect(p.valeId, 'v1');
    expect(p.horas, 2);
    expect(p.descontoEm(4800), 2400);
    expect(p.descontoEm(1500), 1500, reason: 'nunca mais do que o total');
    expect(PremioServico.fromJson(null), isNull, reason: 'sem prémio, o servidor devolve null');
  });

  test('a marcação e a lavagem leem o prémio gravado pelo servidor', () {
    final b = CleaningBooking.fromSupabase({
      'id': 'l1', 'client_user_id': 'c', 'scheduled_at': '2026-11-29T10:00:00Z',
      'total_cents': 2400, 'checkin_premio_cents': 2400, 'checkin_vale_id': 'v1',
    });
    expect(b.checkinPremioCents, 2400);
    expect(b.checkinValeId, 'v1');
    expect(CleaningBooking.fromSupabase({'id': 'l0'}).checkinPremioCents, 0, reason: 'reservas antigas: sem prémio');
    final w = CarwashBooking.fromSupabase({'id': 'w1', 'total_cents': 800, 'checkin_premio_cents': 1200});
    expect(w.checkinPremioCents, 1200);
  });

  testWidgets('caso Divan: o prémio aparece ligado, desconta 24 € e a marcação leva o vale', (t) async {
    final store = await _chegaAoResumo(t);
    expect(find.text('Tens 2 h de limpeza grátis (prémio do check-in)'), findsOneWidget);
    expect(find.text('Prémio do check-in'), findsOneWidget);
    expect(find.text('- €24,00'), findsOneWidget);
    expect(find.text('A pagar'), findsOneWidget);
    expect(find.text('€46,00'), findsOneWidget, reason: '70 € − 24 € do prémio');
    expect(find.text('Dinheiro (no local)'), findsOneWidget, reason: 'com resto, escolhe-se como pagar');
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.vale, 'vale-30-dias');
    expect(store.marcacoes.single.metodo, 'cash');
  });

  testWidgets('desligar o prémio: total normal e a marcação vai sem o vale', (t) async {
    final store = await _chegaAoResumo(t);
    await t.tap(find.byKey(const Key('limpeza_premio_usar')));
    await t.pumpAndSettle();
    expect(find.text('- €24,00'), findsNothing);
    expect(find.text('Guardas o prémio para outra vez.'), findsOneWidget);
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.vale, isNull);
  });

  testWidgets('o prémio cobre tudo: não se paga nada e vai como cartão (o servidor marca prémio)', (t) async {
    final store = await _chegaAoResumo(t, totalCents: 2400);
    expect(find.text('Não pagas nada: o prémio cobre esta limpeza.'), findsOneWidget);
    expect(find.text('Dinheiro (no local)'), findsNothing, reason: 'sem nada a pagar não se escolhe pagamento');
    expect(find.text('€0,00'), findsOneWidget);
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.metodo, 'card');
    expect(store.marcacoes.single.vale, 'vale-30-dias');
  });

  testWidgets('sem cartão ligado e o prémio a cobrir tudo: vai em dinheiro a 0 €', (t) async {
    final store = await _chegaAoResumo(t, totalCents: 2400, cartao: false);
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.metodo, 'cash');
  });

  testWidgets('resto de 1 a 49 cêntimos: só em dinheiro', (t) async {
    final store = await _chegaAoResumo(t, totalCents: 2430);
    expect(find.text('Com o prémio sobra tão pouco que só dá para pagar em dinheiro.'), findsOneWidget);
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.metodo, 'cash');
  });

  testWidgets('sem prémio por usar: o ecrã é o de sempre', (t) async {
    final store = await _chegaAoResumo(t, premio: null);
    expect(find.textContaining('prémio do check-in'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
    await t.tap(find.text('Encomenda com obrigação de pagar'));
    await t.pumpAndSettle();
    expect(store.marcacoes.single.vale, isNull);
  });

  test('a lavagem manda o vale e decide o pagamento como a limpeza', () {
    // o ecrã da lavagem precisa da sessão e da localização: aqui confere-se o código que manda o vale.
    final src = StringBuffer()..write(_lerFicheiro('lib/screens/client/carwash/carwash_request_screen.dart'));
    final s = src.toString();
    expect(s, contains("checkinValeId: _descontoPremio > 0 ? _premio?.valeId : null"));
    expect(s, contains('paymentMethod: _metodoEfetivo(store)'));
    expect(s, contains("if (booking.paymentMethod == 'card' || booking.paymentMethod == 'mbway')"),
        reason: 'pago pelo prémio não abre a folha do cartão');
    expect(s, contains("servicoParaUsar('lavagem')"));
  });
}

String _lerFicheiro(String caminho) => File(caminho).readAsStringSync();
