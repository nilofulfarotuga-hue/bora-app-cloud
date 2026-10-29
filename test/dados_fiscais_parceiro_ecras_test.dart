import 'package:bora_app/models/dados_fiscais_parceiro.dart';
import 'package:bora_app/screens/partner_dados_fiscais_screen.dart';
import 'package:bora_app/widgets/admin/admin_dados_fiscais_card.dart';
import 'package:bora_app/widgets/legal_fields_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Missão boom-burger-2026-10-27, F3 — os ecrãs dos dados fiscais, sem rede
/// (leitura e gravação substituídas por funções falsas).
///
///  1. Parceiro (PT-PT): o cartão do topo diz o que falta ou "Dados fiscais
///     completos"; o formulário vem preenchido com o que o servidor tem; a
///     morada só se pede quando falta; "Guardar" sem a declaração diz o que
///     falta e não grava; com tudo, grava e volta a ler.
///  2. Admin (PT-BR): o cartão mostra NIF e IBAN, os chips do que falta, exige
///     motivo e envia só o campo mudado.
void main() {
  Widget app(Widget w) => MaterialApp(home: Scaffold(body: w));

  DadosFiscaisParceiro dados({
    List<String> emFalta = const ['iban', 'autocertificacao'],
    String? address = 'Rua do Comércio 10, 6300-000 Guarda',
    String? iban,
  }) =>
      DadosFiscaisParceiro(
        restaurantId: 'rest-boom',
        loja: 'Boom! Burger',
        legalName: 'Ana Maria Silva',
        nif: '509999999',
        address: address,
        iban: iban,
        birthDate: DateTime(1990, 5, 1),
        empresa: true,
        emFalta: emFalta,
      );

  group('parceiro — cartão do topo', () {
    testWidgets('com falta: lista os rótulos', (tester) async {
      await tester.pumpWidget(app(const DadosFiscaisEstadoCard(
          emFalta: ['nif', 'iban', 'autocertificacao'])));
      expect(find.text('Para a loja poder abrir ao público, falta:'),
          findsOneWidget);
      expect(find.text('• NIF'), findsOneWidget);
      expect(find.text('• IBAN'), findsOneWidget);
      expect(find.text('• Autocertificação'), findsOneWidget);
      expect(find.text('Dados fiscais completos'), findsNothing);
    });

    testWidgets('sem falta: "Dados fiscais completos"', (tester) async {
      await tester.pumpWidget(app(const DadosFiscaisEstadoCard(emFalta: [])));
      expect(find.text('Dados fiscais completos'), findsOneWidget);
      expect(find.text('A loja pode abrir ao público.'), findsOneWidget);
      expect(find.textContaining('falta:'), findsNothing);
    });
  });

  group('parceiro — ecrã', () {
    testWidgets('preenche com o que o servidor tem e esconde a morada que já existe',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PartnerDadosFiscaisScreen(
          restaurantId: 'rest-boom',
          carregar: () async => dados(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Dados fiscais'), findsOneWidget); // AppBar
      expect(find.text('• IBAN'), findsOneWidget);
      expect(find.text('• Autocertificação'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Ana Maria Silva'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '509999999'), findsOneWidget);
      expect(find.text('01/05/1990'), findsOneWidget);
      // Morada já existe: não há campo, só a linha de leitura.
      expect(find.textContaining('Morada completa'), findsNothing);
      expect(find.text('Morada fiscal (a da loja): Rua do Comércio 10, 6300-000 Guarda'),
          findsOneWidget);
    });

    testWidgets('morada em falta → pede o campo', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PartnerDadosFiscaisScreen(
          restaurantId: 'rest-boom',
          carregar: () async => dados(emFalta: const ['morada'], address: null),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morada completa'), findsOneWidget);
      expect(find.text('• Morada'), findsOneWidget);
    });

    testWidgets('"Guardar" sem IBAN nem declaração diz o que falta e não grava; '
        'com tudo grava e volta a ler', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var leituras = 0;
      LegalFieldsController? gravado;
      await tester.pumpWidget(MaterialApp(
        home: PartnerDadosFiscaisScreen(
          restaurantId: 'rest-boom',
          carregar: () async {
            leituras++;
            return leituras == 1
                ? dados()
                : dados(emFalta: const [], iban: 'PT50000201231234567890154');
          },
          gravar: (c) async => gravado = c,
        ),
      ));
      await tester.pumpAndSettle();
      expect(leituras, 1);

      await tester.tap(find.text('Guardar dados fiscais'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Falta: IBAN'), findsOneWidget);
      expect(gravado, isNull);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'IBAN (PT + 23 dígitos) *'),
          'PT50000201231234567890154');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar dados fiscais'));
      await tester.pumpAndSettle();

      expect(gravado, isNotNull);
      expect(gravado!.iban.text, 'PT50000201231234567890154');
      expect(gravado!.selfCertified.value, isTrue);
      expect(leituras, 2, reason: 'depois de gravar volta a ler o servidor');
      expect(find.text('Dados fiscais guardados.'), findsOneWidget);
      expect(find.text('Dados fiscais completos'), findsOneWidget);
    });

    testWidgets('erro de leitura → mensagem e "Tentar de novo"', (tester) async {
      var n = 0;
      await tester.pumpWidget(MaterialApp(
        home: PartnerDadosFiscaisScreen(
          restaurantId: 'rest-boom',
          carregar: () async {
            n++;
            if (n == 1) throw Exception('sem rede');
            return dados(emFalta: const []);
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não foi possível ler os dados fiscais'),
          findsOneWidget);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Dados fiscais completos'), findsOneWidget);
    });
  });

  group('admin — cartão "Dados fiscais (DAC7)"', () {
    Future<void> montar(WidgetTester tester,
        {required GravarDadosFiscaisAdmin gravar,
        DadosFiscaisParceiro? d}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminDadosFiscaisCard(
              restaurantId: 'rest-boom',
              carregar: () async =>
                  d ??
                  dados(
                      emFalta: const ['iban'],
                      iban: null),
              gravar: gravar,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra NIF, chips do que falta e a nota de empresa',
        (tester) async {
      await montar(tester, gravar: (_, __) async => {});
      expect(find.text('Dados fiscais (DAC7)'), findsOneWidget);
      expect(find.text('Falta para abrir ao público:'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'IBAN'), findsOneWidget);
      expect(find.widgetWithText(TextField, '509999999'), findsOneWidget);
      expect(find.textContaining('Empresa (NIF começa por 5, 6, 7 ou 9)'),
          findsOneWidget);
    });

    testWidgets('sem mudanças não grava; sem motivo não grava; '
        'com IBAN e motivo envia só o IBAN', (tester) async {
      final chamadas = <(AlteracaoDadosFiscais, String)>[];
      await montar(tester, gravar: (alt, motivo) async {
        chamadas.add((alt, motivo));
        return {'ok': true, 'campos': ['iban'], 'em_falta': <String>[]};
      });

      await tester.tap(find.text('Salvar dados fiscais'));
      await tester.pumpAndSettle();
      expect(find.text('Nada mudou — não há o que salvar.'), findsOneWidget);
      expect(chamadas, isEmpty);

      await tester.enterText(
          find.widgetWithText(TextField, 'IBAN (PT + 23 dígitos)'),
          'PT50 0002 0123 1234 5678 9015 4');
      await tester.tap(find.text('Salvar dados fiscais'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escreva o motivo'), findsOneWidget);
      expect(chamadas, isEmpty);

      await tester.enterText(
          find.widgetWithText(TextField, 'Motivo da alteração (obrigatório)'),
          'IBAN enviado por WhatsApp');
      await tester.tap(find.text('Salvar dados fiscais'));
      await tester.pumpAndSettle();
      expect(chamadas, hasLength(1));
      expect(chamadas.single.$1.campos, ['iban']);
      expect(chamadas.single.$1.iban, 'PT50000201231234567890154');
      expect(chamadas.single.$2, 'IBAN enviado por WhatsApp');
      expect(find.textContaining('Dados fiscais salvos. Completos'),
          findsOneWidget);
    });

    testWidgets('erro do servidor aparece em PT-BR', (tester) async {
      await montar(tester,
          gravar: (_, __) async =>
              throw const PostgrestException(message: 'iban_invalido'));
      await tester.enterText(
          find.widgetWithText(TextField, 'IBAN (PT + 23 dígitos)'),
          'PT50000201231234567890154');
      await tester.enterText(
          find.widgetWithText(TextField, 'Motivo da alteração (obrigatório)'),
          'teste');
      await tester.tap(find.text('Salvar dados fiscais'));
      await tester.pumpAndSettle();
      expect(find.text('O servidor recusou o IBAN: PT seguido de 23 dígitos.'),
          findsOneWidget);
    });

    testWidgets('dados completos → "Dados fiscais completos"', (tester) async {
      await montar(tester,
          gravar: (_, __) async => {},
          d: dados(emFalta: const [], iban: 'PT50000201231234567890154'));
      expect(find.text('Dados fiscais completos'), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    });
  });
}
