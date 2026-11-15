// app-15-11 (ordem do Danilo de 15/11/2026 10:14): a lista de entregas do
// estafeta tem seletor de período (hoje, esta semana, semana passada, mês),
// abre/fecha e mostra o total ganho do período em número grande. O valor do
// cliente só aparece em pequeno e só em pagamentos a dinheiro.
import 'dart:io';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Domingo, 15/11/2026, 11:00 em Lisboa (inverno: UTC+0).
final DateTime _agora = DateTime.utc(2026, 11, 15, 11);

OrderModel _entrega(String id, DateTime quando, double ganho,
        {String pagamento = 'card', double preco = 12}) =>
    OrderModel.fromSupabase({
      'id': id,
      'status': 'delivered',
      'service_type': 'restaurant',
      'payment_method': pagamento,
      'price': preco,
      'driver_earnings': ganho,
      'items': const [],
      'created_at': quando.toIso8601String(),
    });

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

void main() {
  group('entregaNoPeriodo (relógio de Lisboa, semana a começar à segunda)', () {
    test('hoje', () {
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 15, 0, 5),
          PeriodoEntregas.hoje, _agora), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 14, 23, 55),
          PeriodoEntregas.hoje, _agora), isFalse);
    });

    test('esta semana vai de segunda 9/11 até hoje', () {
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 9, 0, 1),
          PeriodoEntregas.estaSemana, _agora), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 8, 23, 59),
          PeriodoEntregas.estaSemana, _agora), isFalse);
    });

    test('semana passada é de 2/11 a 8/11', () {
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 2, 8),
          PeriodoEntregas.semanaPassada, _agora), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 8, 22),
          PeriodoEntregas.semanaPassada, _agora), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 9, 8),
          PeriodoEntregas.semanaPassada, _agora), isFalse);
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 1, 22),
          PeriodoEntregas.semanaPassada, _agora), isFalse);
    });

    test('este mês começa a 1/11', () {
      expect(entregaNoPeriodo(DateTime.utc(2026, 11, 1, 0, 30),
          PeriodoEntregas.esteMes, _agora), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 10, 31, 23, 30),
          PeriodoEntregas.esteMes, _agora), isFalse);
    });

    test('no verão, 23:30 UTC de dia 30/06 já é 1/07 em Lisboa', () {
      final agoraVerao = DateTime.utc(2026, 7, 1, 10);
      expect(entregaNoPeriodo(DateTime.utc(2026, 6, 30, 23, 30),
          PeriodoEntregas.hoje, agoraVerao), isTrue);
      expect(entregaNoPeriodo(DateTime.utc(2026, 6, 30, 23, 30),
          PeriodoEntregas.esteMes, agoraVerao), isTrue);
    });
  });

  group('separador Pedidos — período, total e abrir/fechar', () {
    final historico = [
      _entrega('hoje-1', DateTime.utc(2026, 11, 15, 9), 4.5),
      _entrega('semana-1', DateTime.utc(2026, 11, 10, 12), 5.0,
          pagamento: 'cash', preco: 18.4),
      _entrega('passada-1', DateTime.utc(2026, 11, 4, 12), 6.25),
      _entrega('mes-1', DateTime.utc(2026, 11, 1, 12), 3.0),
      _entrega('outubro-1', DateTime.utc(2026, 10, 20, 12), 9.0),
    ];

    Widget app() => MaterialApp(
          home: PedidosEstafetaCorpo(
            emCurso: 0,
            ofertas: 0,
            historico: historico,
            aoAbrirInicio: () {},
            agora: () => _agora,
          ),
        );

    Finder linhas() => find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('pedido_feito_'));
    String total(WidgetTester t) => t
        .widget<Text>(find.byKey(const Key('pedidos_estafeta_total_valor')))
        .data!;
    String contagem(WidgetTester t) => t
        .widget<Text>(find.byKey(const Key('pedidos_estafeta_total_contagem')))
        .data!;

    testWidgets('abre em Esta semana, com o total grande do período',
        (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      for (final r in ['Hoje', 'Esta semana', 'Semana passada', 'Este mês']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      expect(linhas(), findsNWidgets(2));
      expect(total(t), contains('9,50'));
      expect(contagem(t), '2 entregas');
      expect(
          t
              .widget<Text>(find.byKey(const Key('pedidos_estafeta_total_valor')))
              .style!
              .fontSize,
          greaterThanOrEqualTo(24),
          reason: 'o ganho do estafeta em número grande');
    });

    testWidgets('trocar de período muda a lista e o total', (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());

      await t.tap(find.byKey(const ValueKey('pedidos_estafeta_periodo_hoje')));
      await t.pump();
      expect(linhas(), findsOneWidget);
      expect(total(t), contains('4,50'));
      expect(contagem(t), '1 entrega');

      await t.tap(find
          .byKey(const ValueKey('pedidos_estafeta_periodo_semanaPassada')));
      await t.pump();
      expect(find.byKey(const ValueKey('pedido_feito_passada-1')),
          findsOneWidget);
      expect(total(t), contains('6,25'));

      await t
          .tap(find.byKey(const ValueKey('pedidos_estafeta_periodo_esteMes')));
      await t.pump();
      expect(linhas(), findsNWidgets(4), reason: 'outubro fica de fora');
      expect(total(t), contains('18,75'));
    });

    testWidgets('o cabeçalho do total abre e fecha a lista', (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      expect(linhas(), findsNWidgets(2));
      await t.tap(find.byKey(const Key('pedidos_estafeta_total')));
      await t.pump();
      expect(linhas(), findsNothing);
      expect(total(t), contains('9,50'), reason: 'o total fica à vista');
      await t.tap(find.byKey(const Key('pedidos_estafeta_total')));
      await t.pump();
      expect(linhas(), findsNWidgets(2));
    });

    testWidgets('valor do cliente só em pagamentos a dinheiro', (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      expect(find.textContaining('dinheiro'), findsOneWidget);
      expect(find.textContaining('18,40'), findsOneWidget);
      expect(find.textContaining('12,00'), findsNothing,
          reason: 'o pedido pago com cartão não mostra o valor do cliente');
    });

    testWidgets('período sem entregas diz-o', (t) async {
      await t.pumpWidget(MaterialApp(
        home: PedidosEstafetaCorpo(
          emCurso: 0,
          ofertas: 0,
          historico: [_entrega('velha', DateTime.utc(2026, 9, 1, 12), 3)],
          aoAbrirInicio: () {},
          agora: () => _agora,
        ),
      ));
      expect(find.text('Sem entregas neste período.'), findsOneWidget);
    });
  });

  group('Início do estafeta sem repetições (fonte)', () {
    test('dentro da barra saem o chip Online, o veículo e as entregas feitas',
        () {
      final home = _ler('lib/screens/driver_home_screen.dart');
      expect(home, contains('if (!widget.dentroDaBarra)\n                  Container('));
      expect(home, contains('if (!widget.dentroDaBarra)\n            Card('));
      expect(home, contains('if (!widget.dentroDaBarra &&\n'));
      expect(home, contains('aoTocar: widget.aoAbrirGanhos'));
    });

    test('sem rótulos técnicos nem duas palavras para recusar', () {
      final home = _ler('lib/screens/driver_home_screen.dart');
      expect(home, isNot(contains('Status atual')));
      expect(home, isNot(contains('(BR §5.2)')));
      expect(home, isNot(contains('"Rejeitar"')));
      expect(home, contains("'\$balance tokens'"));
    });
  });
}
