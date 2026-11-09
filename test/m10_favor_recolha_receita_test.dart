// M10 b2-nif (09/11/2026) — Favores, regras de 08/10 do livro
// (livro-areas-favores-paragem-casa):
//  - "botão tipo 'peguei a receita' para avançar": a recolha em casa diz o que
//    o estafeta recolhe (receita, cartão, dinheiro);
//  - farmácia: o pedido só segue com a foto da receita (antes era só um aviso
//    com "Continuar sem foto"), exceto se o estafeta vai buscar a receita em
//    papel a casa. Os valores (6 € + 2 € da paragem) não mudam.
import 'dart:io';

import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/errand_form_screen.dart';
import 'package:bora_app/widgets/errand_execution_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _favorComParagem(String motivo) => OrderModel(
      id: 'f1',
      total: 8,
      serviceType: OrderServiceType.errand,
      status: OrderStatus.driverAccepted,
      paymentMethod: PaymentMethod.card,
      customerName: 'Cristina Silva',
      errandDescription: 'Ir à farmácia buscar o medicamento',
      errandLocation: 'Farmácia Tavares, Guarda',
      errandHomeStop: true,
      errandHomeStopReason: motivo,
      errandHasPurchase: false,
    );

void main() {
  group('Recolha em casa: o botão diz o que se recolhe', () {
    test('um texto por motivo', () {
      expect(rotuloConfirmarRecolha('receita'), 'Peguei a receita');
      expect(rotuloConfirmarRecolha('cartao'), 'Peguei o cartão');
      expect(rotuloConfirmarRecolha('dinheiro'), 'Peguei o dinheiro');
      expect(rotuloConfirmarRecolha('outro'), 'Já passei em casa da cliente');
      expect(rotuloConfirmarRecolha(null), 'Já passei em casa da cliente');
    });

    for (final (motivo, texto) in [
      ('receita', 'Peguei a receita'),
      ('cartao', 'Peguei o cartão'),
      ('dinheiro', 'Peguei o dinheiro'),
    ]) {
      testWidgets('folha do Favor, motivo "$motivo": "$texto"', (t) async {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ErrandExecutionSheet(order: _favorComParagem(motivo)),
          ),
        ));
        await t.pump();
        expect(find.text('1. Recolha em casa do cliente'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, texto), findsOneWidget);
        expect(find.text('Confirmar recolha'), findsNothing);
      });
    }
  });

  group('Farmácia: a foto da receita é obrigatória', () {
    test('sem foto não segue; com foto ou receita em papel a casa segue', () {
      expect(
          favorFarmaciaSemReceita(
              pareceFarmacia: true,
              temFotoReceita: false,
              vaiBuscarReceitaACasa: false),
          isTrue);
      expect(
          favorFarmaciaSemReceita(
              pareceFarmacia: true,
              temFotoReceita: true,
              vaiBuscarReceitaACasa: false),
          isFalse);
      expect(
          favorFarmaciaSemReceita(
              pareceFarmacia: true,
              temFotoReceita: false,
              vaiBuscarReceitaACasa: true),
          isFalse,
          reason: 'o estafeta vai buscar a receita em papel a casa');
      expect(
          favorFarmaciaSemReceita(
              pareceFarmacia: false,
              temFotoReceita: false,
              vaiBuscarReceitaACasa: false),
          isFalse,
          reason: 'Favor que não é de farmácia não muda');
    });

    test('a mensagem é clara e tem inglês', () {
      expect(kFavorFaltaReceitaTexto, contains('só consegue comprar o medicamento com a receita'));
      expect(kFavorFaltaReceitaTexto, contains('Código de acesso e dispensa'));
      for (final k in [
        kFavorFaltaReceitaTexto,
        'Falta a foto da receita',
        'Juntar foto da receita',
      ]) {
        expect(kStringsEn.containsKey(k), isTrue, reason: k);
      }
    });

    test('o formulário já não deixa "Continuar sem foto" e usa a regra', () {
      final f = File('lib/screens/errand_form_screen.dart').readAsStringSync();
      expect(f, isNot(contains("'Continuar sem foto'.tr")));
      expect(f, contains('if (favorFarmaciaSemReceita('));
      expect(f, contains("vaiBuscarReceitaACasa: _homeActive && _homeStopReason == 'receita'"));
      expect(f, contains('setState(() => _step = _ErrandStep.what);'));
    });
  });
}
