import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/widgets/legal_fields_section.dart';

/// DATA DE NASCIMENTO SÓ PARA PESSOA SINGULAR (27/10/2026, missão
/// boom-burger-2026-10-27, decisão do Claude.ai às 22:05).
///
/// O servidor (`_conformidade_em_falta`) só pede a data de nascimento quando o
/// NIF é de pessoa singular (1, 2, 3, 45, 8); com NIF de empresa (5, 6, 7, 9) é
/// opcional. O formulário dos dados fiscais pedia-a sempre, por isso uma loja
/// em nome de uma sociedade não conseguia gravar sem inventar uma data.
///
/// NIF de teste com dígito de controlo certo: 500000000 (empresa),
/// 100000002, 250000008 e 450000001 (pessoa singular).

void main() {
  group('NIF de empresa ou de pessoa singular', () {
    test('5, 6, 7 e 9 são empresa', () {
      for (final n in ['500000000', '600000000', '700000000', '987654322']) {
        expect(LegalFieldsValidators.isNifEmpresa(n), isTrue, reason: n);
      }
    });

    test('1, 2, 3, 45 e 8 são pessoa singular', () {
      for (final n in ['100000002', '250000008', '300000000', '450000001', '800000000']) {
        expect(LegalFieldsValidators.isNifEmpresa(n), isFalse, reason: n);
      }
    });

    test('espaços não contam e um NIF incompleto não é empresa', () {
      expect(LegalFieldsValidators.isNifEmpresa('500 000 000'), isTrue);
      expect(LegalFieldsValidators.isNifEmpresa('50000'), isFalse);
      expect(LegalFieldsValidators.isNifEmpresa(''), isFalse);
    });
  });

  group('a data de nascimento', () {
    final hoje = DateTime(2026, 10, 27);

    test('é opcional com NIF de empresa', () {
      expect(LegalFieldsValidators.birthDate(null, now: hoje, nif: '500000000'),
          isNull);
    });

    test('é obrigatória com NIF de pessoa singular ou sem NIF', () {
      expect(LegalFieldsValidators.birthDate(null, now: hoje, nif: '100000002'),
          'Indica a data de nascimento.');
      expect(LegalFieldsValidators.birthDate(null, now: hoje),
          'Indica a data de nascimento.');
    });

    test('se vier preenchida continua a ter de ser de maior de idade', () {
      expect(
          LegalFieldsValidators.birthDate(DateTime(2015, 1, 1),
              now: hoje, nif: '500000000'),
          'Tens de ter pelo menos 18 anos.');
    });
  });

  group('o formulário', () {
    LegalFieldsController preenchido(String nif) {
      final c = LegalFieldsController()
        ..legalName.text = 'Sociedade Teste Lda'
        ..nif.text = nif
        ..address.text = 'Rua de Teste 1, 6300-000 Guarda'
        ..iban.text = 'PT50000000000000000000000';
      c.selfCertified.value = true;
      return c;
    }

    test('com NIF de empresa e sem data fica completo', () {
      final c = preenchido('500000000');
      addTearDown(c.dispose);
      expect(c.errorOf(LegalField.birthDate), isNull);
      expect(c.firstMissingField(), isNull);
      expect(c.isComplete, isTrue);
    });

    test('com NIF de pessoa singular e sem data falta a data', () {
      final c = preenchido('100000002');
      addTearDown(c.dispose);
      expect(c.firstMissingField(), LegalField.birthDate);
    });

    testWidgets('o rótulo diz que é opcional para empresas', (tester) async {
      final c = LegalFieldsController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LegalFieldsSection(controller: c)),
        ),
      ));
      expect(find.text('Data de nascimento *'), findsOneWidget);
      await tester.enterText(find.byKey(c.fieldKeys[LegalField.nif]!), '500000000');
      await tester.pump();
      expect(find.text('Data de nascimento (opcional para empresas)'), findsOneWidget);
      await tester.enterText(find.byKey(c.fieldKeys[LegalField.nif]!), '100000002');
      await tester.pump();
      expect(find.text('Data de nascimento *'), findsOneWidget);
    });
  });
}
