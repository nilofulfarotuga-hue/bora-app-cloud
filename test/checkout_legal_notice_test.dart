import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/widgets/checkout_legal_notice.dart';

/// [ronda-fecho-2026-09-22 · D2] Decreto-Lei 24/2014 no checkout.
///
/// O que estes testes trancam:
///  1. cada tipo de compra mostra a SUA frase sobre a livre resolução, com o
///     link "Termos" a seguir, e o link abre a página dos termos;
///  2. o aviso é texto pequeno, cinzento, centrado e sem caixa;
///  3. o rótulo "Encomenda com obrigação de pagar" cabe a 360 px, em duas
///     linhas centradas, com a fonte Inter real — nunca a encolher a letra;
///  4. os sete ecrãs de checkout do cliente usam o aviso e o botão final diz
///     "Encomenda com obrigação de pagar" (art. 5.º, n.º 2), cada um com o
///     tipo certo — e o reagendamento de marcação, que não cobra, fica igual.
const Map<CheckoutLegalKind, String> _frases = {
  CheckoutLegalKind.comida:
      'Ao confirmar, fazes uma encomenda com obrigação de pagar. Tens 14 dias de livre resolução, exceto para alimentos, bebidas e outros bens perecíveis entregues, produtos abertos ou personalizados e serviços já prestados (DL 24/2014).',
  CheckoutLegalKind.servico:
      'Ao confirmar, fazes um pedido de serviço com obrigação de pagar. Tens 14 dias de livre resolução até o serviço começar; depois de iniciado com o teu acordo, não há direito de resolução (DL 24/2014).',
  CheckoutLegalKind.marcacao:
      'Ao confirmar, fazes uma marcação com obrigação de pagar para uma data certa. Não há direito de livre resolução em serviços com data marcada; aplicam-se as regras de cancelamento indicadas acima (DL 24/2014, art. 17.º).',
  CheckoutLegalKind.entrega:
      'Ao confirmar, pedes uma corrida com obrigação de pagar. O serviço começa de imediato com o teu acordo, pelo que não há direito de livre resolução (DL 24/2014).',
};

Future<void> _pump(
  WidgetTester tester,
  CheckoutLegalKind kind, {
  Future<void> Function(Uri)? openUrl,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360 - 32, // largura útil de um telemóvel de 360 px
          child: CheckoutLegalNotice(kind: kind, openUrl: openUrl),
        ),
      ),
    ),
  ));
}

TextSpan? _spanTermos(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  TextSpan? found;
  text.textSpan!.visitChildren((span) {
    if (span is TextSpan && span.text == 'Termos') {
      found = span;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  group('CheckoutLegalNotice — a frase de cada tipo', () {
    test('todo o tipo tem a sua frase provada aqui', () {
      expect(_frases.keys, containsAll(CheckoutLegalKind.values));
    });

    for (final entry in _frases.entries) {
      testWidgets('${entry.key.name}: mostra a frase inteira e o link Termos',
          (tester) async {
        await _pump(tester, entry.key);
        expect(checkoutLegalText(entry.key), entry.value);
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.textContaining('Termos'), findsOneWidget);
        expect(_spanTermos(tester), isNotNull,
            reason: '"Termos" tem de ser um pedaço próprio, com toque');
        expect(tester.takeException(), isNull,
            reason: 'não pode estourar a 360 px');
      });
    }

    test('todas dizem "obrigação de pagar" e citam o DL 24/2014, em PT-PT', () {
      for (final frase in _frases.values) {
        expect(frase, startsWith('Ao confirmar, '));
        expect(frase, contains('obrigação de pagar'));
        expect(frase, contains('DL 24/2014'));
        expect(frase.toLowerCase(), isNot(contains('você')));
      }
    });

    test('só a comida exclui perecíveis; só a marcação cita o art. 17.º', () {
      expect(_frases[CheckoutLegalKind.comida], contains('perecíveis'));
      expect(_frases[CheckoutLegalKind.marcacao], contains('art. 17.º'));
      for (final k in CheckoutLegalKind.values) {
        if (k != CheckoutLegalKind.comida) {
          expect(_frases[k], isNot(contains('perecíveis')));
        }
        if (k != CheckoutLegalKind.marcacao) {
          expect(_frases[k], isNot(contains('art. 17.º')));
        }
      }
    });
  });

  group('CheckoutLegalNotice — o link Termos', () {
    testWidgets('abre boraguarda.com/termos', (tester) async {
      final abertos = <Uri>[];
      await _pump(tester, CheckoutLegalKind.comida,
          openUrl: (uri) async => abertos.add(uri));

      final termos = _spanTermos(tester)!;
      expect(termos.recognizer, isA<TapGestureRecognizer>());
      (termos.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();

      expect(abertos, [Uri.parse('https://boraguarda.com/termos')]);
      expect(kCheckoutTermsUrl, 'https://boraguarda.com/termos');
    });

    testWidgets('parece um link: sublinhado', (tester) async {
      await _pump(tester, CheckoutLegalKind.servico);
      expect(_spanTermos(tester)!.style?.decoration, TextDecoration.underline);
    });
  });

  group('CheckoutLegalNotice — aspecto', () {
    testWidgets('texto pequeno, cinzento, centrado e sem caixa',
        (tester) async {
      await _pump(tester, CheckoutLegalKind.entrega);
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textAlign, TextAlign.center);
      final style = text.textSpan!.style!;
      expect(style.fontSize, 12);
      expect(style.height, 1.3);
      expect(style.color, Colors.grey.shade700);
      expect(
        find.descendant(
            of: find.byType(CheckoutLegalNotice),
            matching: find.byType(Container)),
        findsNothing,
        reason: 'é texto solto, não um cartão',
      );
    });
  });

  group('a 360 px o rótulo cabe no botão em duas linhas (Inter real)', () {
    const rotulo = 'Encomenda com obrigação de pagar';

    Future<void> pumpAt360(WidgetTester tester, Widget button) async {
      final bytes =
          File('assets/fonts/Inter-VariableFont.ttf').readAsBytesSync();
      final loader = FontLoader('Inter')
        ..addFont(Future.value(bytes.buffer.asByteData()));
      await loader.load();

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [button],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'não pode estourar');
      final paragrafo = tester.renderObject<RenderParagraph>(find.text(rotulo));
      expect(paragrafo.didExceedMaxLines, isFalse,
          reason: 'o rótulo legal tem de se ler inteiro, sem reticências');
    }

    testWidgets('FilledButton.icon com cadeado (reserva e sinal da marcação)',
        (tester) async {
      await pumpAt360(
        tester,
        FilledButton.icon(
          onPressed: () {},
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: const Icon(Icons.lock),
          label: const Text(
            rotulo,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      );
    });

    testWidgets('FilledButton sem ícone (lavagem auto)', (tester) async {
      await pumpAt360(
        tester,
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton(
            onPressed: () {},
            child: const Text(
              rotulo,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    });
  });

  group('os ecrãs de checkout usam o aviso e o rótulo legal', () {
    const ecras = <String, List<CheckoutLegalKind>>{
      'lib/screens/payment_method_screen.dart': [
        CheckoutLegalKind.comida,
        CheckoutLegalKind.servico,
      ],
      'lib/screens/client/tvde/tvde_request_ride_screen.dart': [
        CheckoutLegalKind.entrega,
        CheckoutLegalKind.marcacao,
      ],
      'lib/screens/client/reservation/reservation_checkout_screen.dart': [
        CheckoutLegalKind.marcacao,
      ],
      'lib/screens/client/reservation/reservation_payment_method_sheet.dart': [
        CheckoutLegalKind.marcacao,
      ],
      'lib/screens/client/services/booking_flow_screen.dart': [
        CheckoutLegalKind.marcacao,
      ],
      'lib/screens/client/cleaning/cleaning_wizard_screen.dart': [
        CheckoutLegalKind.servico,
      ],
      'lib/screens/client/carwash/carwash_request_screen.dart': [
        CheckoutLegalKind.servico,
      ],
    };

    for (final entry in ecras.entries) {
      test(entry.key, () {
        final src = File(entry.key).readAsStringSync();
        expect(src, contains("'Encomenda com obrigação de pagar'"),
            reason: 'o botão final tem de dizer isto (DL 24/2014, art. 5.º)');
        expect(src, contains('CheckoutLegalNotice('),
            reason: 'o aviso tem de estar acima do botão');
        for (final kind in entry.value) {
          expect(src, contains('CheckoutLegalKind.${kind.name}'));
        }
      });
    }

    test('o reagendamento de marcação (não cobra) fica como estava', () {
      final src = File('lib/screens/client/services/booking_flow_screen.dart')
          .readAsStringSync();
      expect(src, contains("'Confirmar Reagendamento'"));
    });
  });
}
