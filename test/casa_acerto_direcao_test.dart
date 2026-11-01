// CASA — C8 da revisão de 01/11/2026: o extrato do profissional estava ao
// contrário. As direções do servidor (casa_acertos_semanais.direction) são
// `bora_to_handyman`, `handyman_to_bora` e `zero` — as duas primeiras contêm
// "bora", e o teste antigo (`!direcao.contains('bora')`) nunca dava "a receber".
// E o `a_receber_cents` da semana é negativo quando o profissional recebeu em
// dinheiro: o ecrã mostrava "A receber no acerto: -3,00 €".
//
// Sem rede: só o JSON do contrato e o ecrã [CasaGanhosConteudo].
import 'package:bora_app/screens/handyman/handyman_ganhos_screen.dart';
import 'package:bora_app/stores/handyman_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CasaAcerto _acerto(String direcao, {int cents = 1250, String id = 'a1'}) =>
    CasaAcerto.fromJson({
      'id': id,
      'week_start_at': '2026-10-19T23:00:00Z',
      'week_end_at': '2026-10-26T23:00:00Z',
      'total_jobs': 2,
      'net_payout_cents': cents,
      'direction': direcao,
      'status': 'pending',
    });

Future<void> _montar(WidgetTester tester, CasaGanhos g) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CasaGanhosConteudo(ganhos: g)),
  ));
}

/// Os dois textos (rótulo e valor) da linha do acerto da semana.
List<String> _linhaDaSemana(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byKey(const Key('casa_ganhos_acerto_semana')),
      matching: find.byType(Text),
    ))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  group('as 3 direções do acerto semanal', () {
    test('bora_to_handyman: o Bora paga ao profissional', () {
      final a = _acerto('bora_to_handyman');
      expect(a.aReceber, isTrue);
      expect(a.aPagar, isFalse);
      expect(a.semAcerto, isFalse);
      expect(casaDirecaoAcertoTexto(a), 'o Bora paga-te');
    });

    test(
        'handyman_to_bora: o profissional paga ao Bora (antes dava ao contrário)',
        () {
      final a = _acerto('handyman_to_bora');
      expect(a.aReceber, isFalse);
      expect(a.aPagar, isTrue);
      expect(a.semAcerto, isFalse);
      expect(casaDirecaoAcertoTexto(a), 'tu pagas ao Bora');
    });

    test('zero: nada a acertar (nem "pagas" nem "recebes")', () {
      final a = _acerto('zero', cents: 0);
      expect(a.aReceber, isFalse);
      expect(a.aPagar, isFalse);
      expect(a.semAcerto, isTrue);
      expect(casaDirecaoAcertoTexto(a), 'nada a acertar');
    });

    test('direção desconhecida nunca vira "a receber"', () {
      expect(_acerto('').aReceber, isFalse);
      expect(_acerto('bora').aReceber, isFalse);
      expect(_acerto('to_handyman').aReceber, isFalse);
    });
  });

  group('a linha do acerto desta semana (a_receber_cents)', () {
    test('negativo: "A pagar ao Bora: 3,00 €", sem sinal menos', () {
      final a = casaAcertoDaSemana(-300);
      expect(a.aPagar, isTrue);
      expect(a.rotulo, 'A pagar ao Bora');
      expect(a.valor, '3,00 €');
      expect(a.frase, 'A pagar ao Bora: 3,00 €');
    });

    test('positivo e zero: "A receber no acerto"', () {
      expect(casaAcertoDaSemana(4550).frase, 'A receber no acerto: 45,50 €');
      expect(casaAcertoDaSemana(0).frase, 'A receber no acerto: 0,00 €');
      expect(casaAcertoDaSemana(0).aPagar, isFalse);
    });
  });

  group('o ecrã dos ganhos', () {
    testWidgets('a_receber_cents = -300 mostra "A pagar ao Bora: 3,00 €"',
        (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        CasaGanhos.fromJson(const {
          'semana': {
            'trabalhos': 1,
            'ganho_cents': 1700,
            'recebido_em_mao_cents': 2000,
            'comissao_cents': 300,
            'a_receber_cents': -300,
          },
        }),
      );
      expect(_linhaDaSemana(tester), ['A pagar ao Bora', '3,00 €']);
      expect(find.bySemanticsLabel('A pagar ao Bora: 3,00 €'), findsOneWidget);
      expect(find.textContaining('-3,00'), findsNothing,
          reason: 'nunca se mostra o sinal menos');
      expect(find.text('A receber no acerto'), findsNothing);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });

    testWidgets('a_receber_cents positivo: "A receber no acerto"',
        (tester) async {
      await _montar(
        tester,
        CasaGanhos.fromJson(const {
          'semana': {'a_receber_cents': 2550},
        }),
      );
      expect(_linhaDaSemana(tester), ['A receber no acerto', '25,50 €']);
      expect(find.text('A pagar ao Bora'), findsNothing);
    });

    testWidgets('cada acerto fechado diz quem paga a quem', (tester) async {
      await _montar(
        tester,
        CasaGanhos(acertos: [
          _acerto('bora_to_handyman', id: 'a1', cents: 4000),
          _acerto('handyman_to_bora', id: 'a2', cents: 300),
          _acerto('zero', id: 'a3', cents: 0),
        ]),
      );
      expect(find.textContaining('o Bora paga-te'), findsOneWidget);
      expect(find.textContaining('tu pagas ao Bora'), findsOneWidget);
      expect(find.textContaining('nada a acertar'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('casa_acerto_valor_a2')))
              .data,
          '3,00 €');
      expect(tester.takeException(), isNull);
    });
  });
}
