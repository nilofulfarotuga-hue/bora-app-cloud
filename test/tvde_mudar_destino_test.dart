import 'package:bora_app/models/tvde_dest_change.dart';
import 'package:bora_app/models/tvde_fare_view.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/screens/client/tvde/tvde_dest_change_sheet.dart';
import 'package:bora_app/widgets/tvde/tvde_dest_change_driver_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MUDAR DESTINO (30/09/2026, regra fechada pelo Danilo).
///
/// O preço é SEMPRE do servidor (provado em SQL, `.claude/.ai/provas/
/// tvde-mudar-destino-2026-09-30/`). Aqui trava-se o que a app faz com ele:
///  - a folha mostra destino, km, preço novo e a diferença ANTES de aceitar,
///    e sem "Aceitar" devolve null (nada muda — Lei 45/2018 art. 15.º n.º 4);
///  - o aviso do motorista põe em GRANDE o que ELE ganha a mais;
///  - pacote e plano: a diferença soma-se ao que o motorista cobra.

/// Resposta do servidor para o Exemplo 1 do Danilo (4 km → 10 km).
Map<String, dynamic> _quote({
  double done = 3,
  double rem = 7,
  double total = 10,
  double before = 4,
  int priceBefore = 500,
  int priceNew = 900,
  int diff = 400,
  bool min = false,
  bool longer = true,
  String pm = 'cash',
}) =>
    {
      'km_done': done,
      'km_remaining': rem,
      'km_new_total': total,
      'km_before': before,
      'price_before_cents': priceBefore,
      'price_new_cents': priceNew,
      'price_after_cents': priceBefore + diff,
      'table_diff_cents': priceNew - priceBefore,
      'client_diff_cents': diff,
      'min_applied': min,
      'min_cents': 200,
      'driver_diff_cents': 320,
      'longer': longer,
      'needs_payment': diff > 0 && pm != 'cash',
      'payment_method': pm,
      'formula': {
        'tarifa_base_cents': 500,
        'km_incluidos': 6,
        'preco_km_extra_cents': 100,
      },
    };

TvdeRide _ride({
  String pm = 'cash',
  int estFare = 900,
  int changeCount = 1,
  int changeFee = 400,
  int changeDriver = 320,
  int changeCash = 400,
  String? creditId,
  bool usedPlan = false,
}) =>
    TvdeRide.fromMap({
      'id': 'r1',
      'client_id': 'c1',
      'status': 'em_andamento',
      'origin_lat': 40.5,
      'origin_lng': -7.26,
      'dest_lat': 40.6,
      'dest_lng': -7.3,
      'dest_label': 'Hospital da Guarda',
      'est_distance_km': 10.0,
      'est_fare_cents': estFare,
      'driver_earn_cents': 720,
      'payment_method': pm,
      'used_subscription_ride': usedPlan,
      if (creditId != null) 'roundtrip_credit_id': creditId,
      'dest_change_count': changeCount,
      'dest_change_fee_cents': changeFee,
      'dest_change_driver_cents': changeDriver,
      'dest_change_cash_cents': changeCash,
    });

Future<Object?> _abrirFolha(WidgetTester tester, TvdeDestChangeQuote q,
    {String method = 'cash'}) async {
  Object? devolvido = 'nada';
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            devolvido = await showModalBottomSheet<TvdeDestChangeDecision>(
              context: context,
              isScrollControlled: true,
              builder: (_) => TvdeDestChangeSheet(
                  quote: q, destLabel: 'Hospital da Guarda', method: method),
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return devolvido;
}

void main() {
  group('cotação (JSON do servidor)', () {
    test('lê os números sem inventar nenhum', () {
      final q = TvdeDestChangeQuote.fromMap(_quote());
      expect(q.kmNewTotal, 10);
      expect(q.priceBeforeCents, 500);
      expect(q.priceAfterCents, 900);
      expect(q.clientDiffCents, 400);
      expect(q.isFree, isFalse);
      expect(q.hasFormula, isTrue);
      expect(TvdeDestChangeQuote.eur(q.clientDiffCents), '€4,00');
    });

    test('destino mais perto: grátis e sem devolução', () {
      final q = TvdeDestChangeQuote.fromMap(_quote(
          total: 5, before: 8, priceBefore: 700, priceNew: 500, diff: 0, longer: false));
      expect(q.isFree, isTrue);
      expect(q.priceAfterCents, 700);
    });

    test('números em texto também servem (PostgREST numeric)', () {
      final q = TvdeDestChangeQuote.fromMap({
        ..._quote(),
        'km_new_total': '8.40',
        'client_diff_cents': '200',
        'min_applied': 'true',
      });
      expect(q.kmNewTotal, 8.4);
      expect(q.clientDiffCents, 200);
      expect(q.minApplied, isTrue);
    });
  });

  group('folha "Mudar destino" (cliente)', () {
    testWidgets('mostra destino, km, preço novo e a diferença antes de aceitar',
        (tester) async {
      await _abrirFolha(tester, TvdeDestChangeQuote.fromMap(_quote()));
      expect(find.byKey(const Key('tvde_dest_change_label')), findsOneWidget);
      expect(find.text('Hospital da Guarda'), findsOneWidget);
      expect(find.text('3,0 km já feitos + 7,0 km até ao destino novo = 10,0 km'),
          findsOneWidget);
      expect(find.text('€5,00'), findsOneWidget); // preço combinado
      expect(find.text('€9,00'), findsOneWidget); // preço novo
      expect(find.text('Pagas mais €4,00'), findsOneWidget);
      // Fórmula sempre à vista (art. 15.º n.º 4).
      expect(find.byKey(const Key('tvde_dest_change_formula')), findsOneWidget);
      expect(find.byKey(const Key('tvde_dest_change_accept')), findsOneWidget);
      expect(find.byKey(const Key('tvde_dest_change_cancel')), findsOneWidget);
    });

    testWidgets('mínimo de €2 explicado quando a tabela dava menos',
        (tester) async {
      // Exemplo 4: 8 km → 8,4 km, tabela +€1, paga o mínimo €2.
      await _abrirFolha(
          tester,
          TvdeDestChangeQuote.fromMap(_quote(
              done: 2, rem: 6.4, total: 8.4, before: 8,
              priceBefore: 700, priceNew: 800, diff: 200, min: true)));
      expect(find.text('Pagas mais €2,00'), findsOneWidget);
      expect(find.textContaining('mínimo de €2,00'), findsOneWidget);
    });

    testWidgets('mais perto: "Não pagas mais nada" e preço igual',
        (tester) async {
      await _abrirFolha(
          tester,
          TvdeDestChangeQuote.fromMap(_quote(
              total: 5, before: 8, priceBefore: 700, priceNew: 500, diff: 0, longer: false)));
      expect(find.text('Não pagas mais nada'), findsOneWidget);
      expect(find.text('O preço fica igual e não há devolução.'), findsOneWidget);
    });

    testWidgets('Cancelar devolve null — sem aceitar nada muda', (tester) async {
      Object? res = 'x';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                res = await showModalBottomSheet<TvdeDestChangeDecision>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TvdeDestChangeSheet(
                      quote: TvdeDestChangeQuote.fromMap(_quote()),
                      destLabel: 'X',
                      method: 'cash'),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tvde_dest_change_cancel')));
      await tester.pumpAndSettle();
      expect(res, isNull);
    });

    testWidgets('Aceitar em dinheiro devolve a decisão', (tester) async {
      Object? res;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                res = await showModalBottomSheet<TvdeDestChangeDecision>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TvdeDestChangeSheet(
                      quote: TvdeDestChangeQuote.fromMap(_quote()),
                      destLabel: 'X',
                      method: 'cash'),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Pagas €4,00 a mais ao motorista, em dinheiro, no fim da viagem.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('tvde_dest_change_accept')));
      await tester.pumpAndSettle();
      expect(res, isA<TvdeDestChangeDecision>());
    });

    testWidgets('MB Way exige o número antes de aceitar', (tester) async {
      Object? res = 'ainda aberto';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                res = await showModalBottomSheet<TvdeDestChangeDecision>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TvdeDestChangeSheet(
                      quote: TvdeDestChangeQuote.fromMap(_quote(pm: 'mbway')),
                      destLabel: 'X',
                      method: 'mbway'),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tvde_dest_change_mbway_phone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tvde_dest_change_accept')));
      await tester.pumpAndSettle();
      expect(res, 'ainda aberto');
      expect(find.text('Indica um número com 9 dígitos.'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('tvde_dest_change_mbway_phone')), '912345678');
      await tester.tap(find.byKey(const Key('tvde_dest_change_accept')));
      await tester.pumpAndSettle();
      expect(res, isA<TvdeDestChangeDecision>());
      expect((res as TvdeDestChangeDecision).phone, '912345678');
    });
  });

  group('aviso ao motorista', () {
    Future<void> montar(WidgetTester tester, TvdeRide ride) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(body: TvdeDestChangeDriverNotice(ride: ride))));

    testWidgets('número grande = o que ELE ganha a mais', (tester) async {
      await montar(tester, _ride());
      expect(find.text('Novo destino: Hospital da Guarda'), findsOneWidget);
      final ganho = tester.widget<Text>(
          find.byKey(const Key('tvde_dest_change_driver_gain')));
      expect(ganho.data, '+€3.20');
      expect(ganho.style!.fontSize, greaterThan(14));
      // Dinheiro, corrida normal: a diferença já está no total a cobrar.
      expect(find.byKey(const Key('tvde_dest_change_driver_collect')),
          findsOneWidget);
    });

    testWidgets('pago na app: não manda cobrar nada', (tester) async {
      await montar(tester, _ride(pm: 'card', changeCash: 0));
      expect(find.byKey(const Key('tvde_dest_change_driver_collect')),
          findsNothing);
    });

    testWidgets('sem mudança: não mostra nada', (tester) async {
      await montar(tester, _ride(changeCount: 0, changeFee: 0, changeDriver: 0));
      expect(find.byKey(const Key('tvde_dest_change_driver_notice')),
          findsNothing);
    });

    test('snack diz o ganho DESTA mudança', () {
      expect(TvdeDestChangeDriverNotice.snackFor(_ride(), 100),
          'Novo destino: Hospital da Guarda · ganhas mais €1.00');
      expect(TvdeDestChangeDriverNotice.snackFor(_ride(), 0),
          'Novo destino: Hospital da Guarda · o teu ganho fica igual');
    });
  });

  group('preço a cobrar (TvdeFareView) com mudança de destino', () {
    test('corrida normal: a diferença já vem no est_fare_cents', () {
      final f = TvdeFareView.of(_ride(estFare: 900), packageCents: 800);
      expect(f.clientTotalCents, 900);
      expect(f.driverCollectCents, 900);
    });

    test('ida do pacote em dinheiro: pacote + diferença', () {
      final f = TvdeFareView.of(
          _ride(creditId: 'v1', estFare: 0, changeFee: 200, changeCash: 200),
          packageCents: 800);
      expect(f.clientTotalCents, 1000);
      expect(f.driverCollectCents, 1000);
    });

    test('corrida do plano: só a diferença', () {
      final f = TvdeFareView.of(
          _ride(usedPlan: true, estFare: 0, changeFee: 200, changeCash: 200),
          packageCents: 800);
      expect(f.clientTotalCents, 200);
      expect(f.coveredByPlan, isTrue);
    });
  });
}
