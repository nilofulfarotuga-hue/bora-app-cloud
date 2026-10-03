import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

import 'package:bora_app/services/legal_fields_service.dart';
import 'package:bora_app/widgets/legal_fields_section.dart';

/// D3 (ronda-fecho-2026-09-22) — DSA art. 30 + DAC7.
///
/// O que estes testes fecham: um prestador só pode ser ativado com nome legal,
/// NIF, morada, IBAN, data de nascimento e autocertificação. O servidor
/// bloqueia o "aprovar" sem eles, por isso o formulário tem de os exigir
/// TODOS — e, quando falta um, tem de dizer qual (PADRAO_BORA §1.2: nunca
/// falhar calado). Se algum destes testes ficar vermelho, ou entra lixo na
/// base (NIF de recurso, IBAN estrangeiro, menor de idade) ou o botão volta
/// a poder não fazer nada sem explicar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NIF — 9 dígitos + dígito de controlo (mod 11)', () {
    test('aceita um NIF válido (322151171)', () {
      expect(LegalFieldsValidators.isValidNif('322151171'), isTrue);
      expect(LegalFieldsValidators.nif('322151171'), isNull);
    });

    test('aceita espaços pelo meio — normaliza antes de validar', () {
      expect(LegalFieldsValidators.isValidNif('322 151 171'), isTrue);
    });

    test('rejeita 123456789 (passa no mod 11 mas é número de recurso)', () {
      expect(LegalFieldsValidators.isValidNif('123456789'), isFalse);
      expect(LegalFieldsValidators.nif('123456789'), contains('inválido'));
    });

    test('rejeita dígitos todos iguais (111111111, 000000000)', () {
      expect(LegalFieldsValidators.isValidNif('111111111'), isFalse);
      expect(LegalFieldsValidators.isValidNif('000000000'), isFalse);
    });

    test('rejeita dígito de controlo errado (322151170)', () {
      expect(LegalFieldsValidators.isValidNif('322151170'), isFalse);
    });

    test('rejeita menos ou mais de 9 dígitos e letras', () {
      expect(LegalFieldsValidators.isValidNif('32215117'), isFalse);
      expect(LegalFieldsValidators.isValidNif('3221511711'), isFalse);
      expect(LegalFieldsValidators.isValidNif('32215117A'), isFalse);
      expect(LegalFieldsValidators.isValidNif(''), isFalse);
    });

    test('vazio pede o NIF em palavras', () {
      expect(LegalFieldsValidators.nif(''), 'Indica o NIF.');
      expect(LegalFieldsValidators.nif(null), 'Indica o NIF.');
    });
  });

  group('IBAN — PT + 23 dígitos', () {
    test('aceita IBAN português com espaços e minúsculas', () {
      expect(
          LegalFieldsValidators.isValidIban('PT50 0002 0123 1234 5678 9015 4'),
          isTrue);
      expect(LegalFieldsValidators.isValidIban('pt50000201231234567890154'),
          isTrue);
      expect(LegalFieldsValidators.iban('PT50 0002 0123 1234 5678 9015 4'),
          isNull);
    });

    test('rejeita comprimento errado', () {
      expect(LegalFieldsValidators.isValidIban('PT5000020123123456789015'),
          isFalse,
          reason: '22 dígitos');
      expect(LegalFieldsValidators.isValidIban('PT500002012312345678901545'),
          isFalse,
          reason: '24 dígitos');
    });

    test('rejeita IBAN de outro país e letras no meio', () {
      expect(LegalFieldsValidators.isValidIban('ES5000020123123456789015'),
          isFalse);
      expect(LegalFieldsValidators.isValidIban('PT50000201231234567890A54'),
          isFalse);
    });

    test('vazio pede o IBAN; errado diz o formato', () {
      expect(LegalFieldsValidators.iban(''), 'Indica o IBAN.');
      expect(LegalFieldsValidators.iban('PT50'), contains('23 dígitos'));
    });
  });

  group('data de nascimento — mínimo 18 anos', () {
    final hoje = DateTime(2026, 9, 23);

    test('quem faz 18 anos hoje passa', () {
      expect(LegalFieldsValidators.isAdult(DateTime(2008, 9, 23), now: hoje),
          isTrue);
      expect(LegalFieldsValidators.birthDate(DateTime(2008, 9, 23), now: hoje),
          isNull);
    });

    test('quem faz 18 anos amanhã não passa', () {
      expect(LegalFieldsValidators.isAdult(DateTime(2008, 9, 24), now: hoje),
          isFalse);
      expect(LegalFieldsValidators.birthDate(DateTime(2008, 9, 24), now: hoje),
          'Tens de ter pelo menos 18 anos.');
    });

    test('menor de idade claro é rejeitado; adulto claro passa', () {
      expect(LegalFieldsValidators.isAdult(DateTime(2015, 1, 1), now: hoje),
          isFalse);
      expect(LegalFieldsValidators.isAdult(DateTime(1990, 5, 1), now: hoje),
          isTrue);
    });

    test('sem data pede a data', () {
      expect(LegalFieldsValidators.birthDate(null, now: hoje),
          'Indica a data de nascimento.');
    });
  });

  group('autocertificação (DSA art. 30 n.º 1 e))', () {
    test('sem a caixa marcada não passa', () {
      expect(LegalFieldsValidators.selfCertify(false), isNotNull);
      expect(LegalFieldsValidators.selfCertify(null), isNotNull);
      expect(LegalFieldsValidators.selfCertify(true), isNull);
    });

    test('o texto é o da lei — veracidade, conta própria, DAC7', () {
      expect(kDsaSelfCertificationText, contains('verdadeiros e atuais'));
      expect(kDsaSelfCertificationText, contains('por conta própria'));
      expect(kDsaSelfCertificationText, contains('Autoridade Tributária'));
      expect(kDsaSelfCertificationText, contains('(DAC7)'));
    });
  });

  group('LegalFieldsController.firstMissingLabel — diz o que falta, por ordem',
      () {
    final hoje = DateTime(2026, 9, 23);

    LegalFieldsController completo() {
      final c = LegalFieldsController();
      c.legalName.text = 'Danilo Fulfaro da Silva';
      c.nif.text = '322151171';
      c.address.text = 'Rua do Torreão 14, 6300-610 Guarda';
      c.iban.text = 'PT50 0002 0123 1234 5678 9015 4';
      c.birthDate.value = DateTime(1990, 5, 1);
      c.selfCertified.value = true;
      return c;
    }

    test('tudo vazio: o primeiro em falta é o nome', () {
      final c = LegalFieldsController();
      addTearDown(c.dispose);
      expect(c.firstMissingField(now: hoje), LegalField.legalName);
      expect(c.firstMissingLabel(now: hoje), contains('nome completo'));
    });

    test('vai apontando o seguinte à medida que se preenche', () {
      final c = LegalFieldsController();
      addTearDown(c.dispose);
      c.legalName.text = 'Maria Silva';
      expect(c.firstMissingField(now: hoje), LegalField.nif);
      c.nif.text = '322151171';
      expect(c.firstMissingField(now: hoje), LegalField.address);
      c.address.text = 'Rua do Torreão 14, 6300-610 Guarda';
      expect(c.firstMissingField(now: hoje), LegalField.iban);
      c.iban.text = 'PT50000201231234567890154';
      expect(c.firstMissingField(now: hoje), LegalField.birthDate);
      c.birthDate.value = DateTime(1990, 5, 1);
      expect(c.firstMissingField(now: hoje), LegalField.selfCertify);
      expect(c.firstMissingLabel(now: hoje), contains('declaração'));
      c.selfCertified.value = true;
      expect(c.firstMissingField(now: hoje), isNull);
      expect(c.firstMissingLabel(now: hoje), isNull);
      expect(c.isComplete, isTrue);
    });

    test('NIF de recurso conta como em falta', () {
      final c = completo();
      addTearDown(c.dispose);
      c.nif.text = '123456789';
      expect(c.firstMissingField(now: hoje), LegalField.nif);
    });

    test('menor de idade conta como em falta', () {
      final c = completo();
      addTearDown(c.dispose);
      c.birthDate.value = DateTime(2015, 1, 1);
      expect(c.firstMissingField(now: hoje), LegalField.birthDate);
      expect(c.firstMissingLabel(now: hoje), contains('18'));
    });

    test('a data vai para a RPC como yyyy-MM-dd', () {
      final c = completo();
      addTearDown(c.dispose);
      c.birthDate.value = DateTime(1990, 5, 1);
      expect(c.birthDateIso, '1990-05-01');
      c.birthDate.value = null;
      expect(c.birthDateIso, isNull);
    });

    test('controladores partilhados não são descartados pela secção', () {
      // Os ecrãs com rascunho passam os controladores deles (NIF/IBAN/morada);
      // quem os criou é quem os descarta — a secção só descarta os dela.
      final nif = TextEditingController(text: '322151171');
      final c = LegalFieldsController(nif: nif);
      c.dispose();
      expect(() => nif.text = '111', returnsNormally);
      nif.dispose();
    });
  });

  group('LegalFieldsSection — o formulário exige a declaração', () {
    Future<LegalFieldsController> pump(WidgetTester tester) async {
      final c = LegalFieldsController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LegalFieldsSection(controller: c),
          ),
        ),
      ));
      return c;
    }

    Future<void> preencherTudoMenosDeclaracao(
        WidgetTester tester, LegalFieldsController c) async {
      await tester.enterText(
          find.byKey(c.fieldKeys[LegalField.legalName]!), 'Maria Silva');
      await tester.enterText(
          find.byKey(c.fieldKeys[LegalField.nif]!), '322151171');
      await tester.enterText(find.byKey(c.fieldKeys[LegalField.address]!),
          'Rua do Torreão 14, 6300-610 Guarda');
      await tester.enterText(find.byKey(c.fieldKeys[LegalField.iban]!),
          'PT50 0002 0123 1234 5678 9015 4');
      c.birthDate.value = DateTime(1990, 5, 1);
      await tester.pump();
    }

    testWidgets('mostra os seis campos e a declaração da lei', (tester) async {
      await pump(tester);
      expect(find.text('Nome completo (como no documento) *'), findsOneWidget);
      expect(find.text('NIF *'), findsOneWidget);
      expect(find.text('IBAN (PT + 23 dígitos) *'), findsOneWidget);
      expect(find.text('Data de nascimento *'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.text(kDsaSelfCertificationText), findsOneWidget);
    });

    testWidgets('com tudo preenchido menos a caixa, não passa e diz porquê',
        (tester) async {
      final c = await pump(tester);
      await preencherTudoMenosDeclaracao(tester, c);

      final futuro = c.validateAndReveal();
      await tester.pumpAndSettle();
      final falta = await futuro;

      expect(falta, isNotNull);
      expect(falta, contains('declaração'));
      // O erro aparece INLINE, debaixo da caixa — não só na SnackBar.
      expect(find.text('Tens de confirmar a declaração para continuar.'),
          findsOneWidget);
    });

    testWidgets('marcar a caixa desbloqueia', (tester) async {
      final c = await pump(tester);
      await preencherTudoMenosDeclaracao(tester, c);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(c.selfCertified.value, isTrue);

      final futuro = c.validateAndReveal();
      await tester.pumpAndSettle();
      expect(await futuro, isNull);
      expect(find.text('Tens de confirmar a declaração para continuar.'),
          findsNothing);
    });

    testWidgets('formulário vazio: realça o nome, dá-lhe o foco e diz o rótulo',
        (tester) async {
      final c = await pump(tester);

      final futuro = c.validateAndReveal();
      await tester.pumpAndSettle();
      final falta = await futuro;

      expect(falta, contains('nome completo'));
      expect(c.focusNodes[LegalField.legalName]!.hasFocus, isTrue);
      expect(find.text('Indica o nome completo, como está no documento.'),
          findsOneWidget);
    });

    testWidgets('NIF de recurso mostra o erro debaixo do campo',
        (tester) async {
      final c = await pump(tester);
      await preencherTudoMenosDeclaracao(tester, c);
      await tester.enterText(
          find.byKey(c.fieldKeys[LegalField.nif]!), '123456789');

      final futuro = c.validateAndReveal();
      await tester.pumpAndSettle();
      final falta = await futuro;

      expect(falta, contains('NIF'));
      expect(
          find.text('NIF inválido — confirma os 9 dígitos.'), findsOneWidget);
    });

    testWidgets(
        'showAddress=false não desenha a morada mas continua a exigi-la',
        (tester) async {
      final address = TextEditingController();
      addTearDown(address.dispose);
      final c = LegalFieldsController(address: address);
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LegalFieldsSection(controller: c, showAddress: false),
          ),
        ),
      ));
      expect(find.byKey(c.fieldKeys[LegalField.address]!), findsNothing);
      c.legalName.text = 'Maria Silva';
      c.nif.text = '322151171';
      expect(c.firstMissingField(), LegalField.address);
      address.text = 'Rua do Torreão 14, 6300-610 Guarda';
      expect(c.firstMissingField(), LegalField.iban);
    });
  });

  group('LegalFieldsService.messageFor — erros em português, sem jargão', () {
    test('erros do servidor (RAISE EXCEPTION) ficam legíveis', () {
      expect(
          LegalFieldsService.messageFor(
              const PostgrestException(message: 'nif_invalido')),
          contains('NIF'));
      expect(
          LegalFieldsService.messageFor(
              const PostgrestException(message: 'iban_invalido')),
          contains('IBAN'));
      expect(
          LegalFieldsService.messageFor(
              const PostgrestException(message: 'menor_de_idade')),
          contains('18 anos'));
    });

    test('sessão expirada (42501) e função por publicar (PGRST202)', () {
      expect(
          LegalFieldsService.messageFor(const PostgrestException(
              message: 'unauthenticated', code: '42501')),
          contains('sessão'));
      expect(
          LegalFieldsService.messageFor(const PostgrestException(
              message: 'Could not find the function', code: 'PGRST202')),
          contains('ainda não está disponível'));
      expect(LegalFieldsService.messageFor(const AuthException('JWT expired')),
          contains('sessão'));
    });

    test('tempo esgotado e desconhecido têm frase própria', () {
      expect(LegalFieldsService.messageFor(TimeoutException('x')),
          contains('demorou'));
      expect(LegalFieldsService.messageFor(StateError('boom')),
          contains('Não foi possível'));
    });

    test('a excepção mostra a própria mensagem no toString', () {
      const e = LegalFieldsException('Indica o NIF.', code: 'nif');
      expect(e.toString(), 'Indica o NIF.');
      expect(LegalFieldsService.messageFor(e), 'Indica o NIF.');
    });
  });
}
