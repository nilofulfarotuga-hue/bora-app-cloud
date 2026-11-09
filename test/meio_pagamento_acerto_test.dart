// Missão pendencias-2026-11-09, Bloco B — o comprovativo diz o meio certo.
// O meio escolhido no painel tem de ir em payment_reference (é daí que o
// gatilho _settlement_receipt_enqueue o copia e a Edge settlement-receipt o lê).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/widgets/admin/meio_pagamento_acerto.dart';

Future<void> _abrir(
  WidgetTester tester,
  void Function(EscolhaMeioPagamento?) fim, {
  String? numeroMbway,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => fim(await confirmarDinheiroComMeio(
              context,
              titulo: 'Marcar como pago',
              nome: 'Boom! Burger',
              valor: '€13,60',
              numeroMbway: numeroMbway,
            )),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('referenciaComMeio', () {
    test('cada meio escreve o rótulo que a Edge reconhece', () {
      expect(referenciaComMeio(MeioPagamentoAcerto.transferencia),
          'Transferência bancária');
      expect(referenciaComMeio(MeioPagamentoAcerto.mbway, numeroMbway: ' 912345678 '),
          'MB Way 912345678');
      expect(referenciaComMeio(MeioPagamentoAcerto.mbway), 'MB Way');
      expect(referenciaComMeio(MeioPagamentoAcerto.stripe), 'Stripe');
      expect(referenciaComMeio(MeioPagamentoAcerto.dinheiro, observacao: 'em mãos'),
          'Dinheiro · em mãos');
    });

    test('"Não informar" não inventa meio', () {
      expect(referenciaComMeio(MeioPagamentoAcerto.naoInformar), isNull);
      expect(referenciaComMeio(MeioPagamentoAcerto.naoInformar, observacao: '  '),
          isNull);
      expect(
          referenciaComMeio(MeioPagamentoAcerto.naoInformar, observacao: 'nota'),
          'nota');
      // o número só conta com MB Way
      expect(
          referenciaComMeio(MeioPagamentoAcerto.transferencia,
              numeroMbway: '912345678'),
          'Transferência bancária');
    });
  });

  group('confirmarDinheiroComMeio', () {
    testWidgets('começa em "Não informar" e devolve sem referência',
        (tester) async {
      EscolhaMeioPagamento? r;
      var chamou = false;
      await _abrir(tester, (e) {
        chamou = true;
        r = e;
      });
      expect(find.text('Boom! Burger'), findsOneWidget);
      expect(find.text('€13,60'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(chamou, isTrue);
      expect(r!.meio, MeioPagamentoAcerto.naoInformar);
      expect(r!.referencia(), isNull);
      expect(r!.codigo, isNull);
    });

    testWidgets('transferência escolhida vai na referência', (tester) async {
      EscolhaMeioPagamento? r;
      await _abrir(tester, (e) => r = e);
      await tester.tap(find.byKey(const ValueKey('meio_transferencia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(r!.referencia(), 'Transferência bancária');
      expect(r!.codigo, 'transferencia');
    });

    testWidgets('MB Way traz o número sugerido e deixa mudá-lo', (tester) async {
      EscolhaMeioPagamento? r;
      await _abrir(tester, (e) => r = e, numeroMbway: '912345678');
      expect(find.byKey(const ValueKey('meio_numero_mbway')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('meio_mbway')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('meio_numero_mbway')), findsOneWidget);
      expect(find.text('912345678'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('meio_numero_mbway')), '963000111');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(r!.referencia(), 'MB Way 963000111');
      expect(r!.codigo, 'mbway');
    });

    testWidgets('cancelar devolve null (nada é marcado)', (tester) async {
      EscolhaMeioPagamento? r = const EscolhaMeioPagamento(MeioPagamentoAcerto.stripe);
      await _abrir(tester, (e) => r = e);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(r, isNull);
    });
  });

  group('os ecrãs do painel que marcam pago/recebido mandam o meio', () {
    String ler(String f) => File('lib/screens/admin/$f').readAsStringSync();

    test('Acertos da semana → admin_set_settlement_state com p_payment_reference',
        () {
      final s = ler('admin_acertos_semana_screen.dart');
      expect(s, contains('confirmarDinheiroComMeio('));
      expect(s, contains("'p_payment_reference': escolha.referencia()"));
    });

    test('Parceiro e estafeta (admin_settlements_screen)', () {
      final s = ler('admin_settlements_screen.dart');
      expect('payRef = escolha.referencia(observacao: ctrl.text);'
          .allMatches(s)
          .length, 2);
      expect(s, isNot(contains('via MBWay')));
    });

    test('Extrato do dono: as 3 funções de acerto levam a referência com meio',
        () {
      final s = ler('admin_extrato_dono_screen.dart');
      expect(s, contains("'p_metodo': escolha.codigo"));
      expect("'p_referencia': referencia".allMatches(s).length, 1);
      expect("'p_payment_reference': referencia".allMatches(s).length, 2);
    });

    test('Acerto unificado, lavagem e limpeza já não mandam "mbway" fixo', () {
      final u = ler('admin_acerto_unificado_screen.dart');
      expect(u, contains("'p_referencia': escolha.referencia()"));
      final w = ler('admin_carwash_screen.dart');
      expect(w, contains("'p_method': escolha.codigo"));
      expect(w, isNot(contains("'p_method': 'mbway'")));
      final c = ler('admin_cleaner_settlements_screen.dart');
      expect(c, contains("'p_payment_reference': escolha.referencia() ?? externalId"));
      expect(c, isNot(contains("'p_payment_method': 'mbway'")));
    });
  });
}
