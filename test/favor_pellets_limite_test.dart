// B1b (fechar-pendencias-2026-10-20) — no máximo 2 sacos de pellets por Favor.
// Os pellets só entram num Favor pela descrição escrita (não há produto nem
// contador): a app lê a quantidade do texto e não deixa seguir acima de 2.
import 'package:bora_app/utils/favor_passos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o limite é 2', () => expect(kMaxSacosPelletsPorFavor, 2));

  group('sem pellets na descrição', () {
    for (final t in [
      'Vai à Farmácia Holon e compra Ben-u-ron 1g',
      '3 sacos de batatas do Continente',
      '',
      null,
    ]) {
      test('"$t" → null', () {
        expect(sacosDePelletsPedidos(t), isNull);
        expect(pelletsAcimaDoLimite(t), isFalse);
      });
    }
  });

  group('pellets dentro do limite', () {
    final casos = <String, int>{
      // o pedido real de 27/09 (33243355): sem quantidade
      'vai ao continente ou pingo doce e pega pellets para lareira elétrica por favor': 0,
      '1 saco de pellets': 1,
      'um saco de pellets do Leroy': 1,
      '2 sacos de pellets': 2,
      'Dois sacos de Pellets': 2,
      '2 sacos de 15 kg de pellets': 2,
      '15 kg de pellets': 0,
      'pellets: 2 sacos': 2,
      'pellets x2': 2,
      'peletes, duas sacas': 2,
      '3 sacos de batatas e 1 saco de pellets': 1,
    };
    casos.forEach((t, n) {
      test('"$t" → $n', () {
        expect(sacosDePelletsPedidos(t), n);
        expect(pelletsAcimaDoLimite(t), isFalse);
      });
    });
  });

  group('pellets acima do limite → não deixa seguir', () {
    final casos = <String, int>{
      '3 sacos de pellets': 3,
      'Três sacos de pellets por favor': 3,
      '10 sacos de pellets': 10,
      '3x pellets': 3,
      '5 pellets': 5,
      'pellets: 4 sacos': 4,
      'pellets (3)': 3,
      'pellets para a lareira, 4 sacos': 4,
      '4 sacos grandes de pellets': 4,
      '3 sacos de 15kg de pellets': 3,
      'compra pellets, 6 embalagens': 6,
      // revisão B, ronda 1
      'meia dúzia de sacos de pellets': 6,
      'uma dúzia de sacos de pellets': 12,
    };
    casos.forEach((t, n) {
      test('"$t" → $n', () {
        expect(sacosDePelletsPedidos(t), n);
        expect(pelletsAcimaDoLimite(t), isTrue);
      });
    });
  });

  group('revisão B, ronda 1: palete e limite vindo do painel', () {
    for (final t in [
      'uma palete de pellets',
      'Paletes de pellets para a lareira',
      'pellets: 1 pallet',
    ]) {
      test('"$t" → palete, acima de qualquer limite', () {
        expect(sacosDePelletsPedidos(t), kPaletePellets);
        expect(pelletsAcimaDoLimite(t), isTrue);
        expect(pelletsAcimaDoLimite(t, max: 50), isTrue);
      });
    }

    test('o limite do painel manda (3 sacos com máximo 3 passa, 4 não)', () {
      expect(pelletsAcimaDoLimite('3 sacos de pellets', max: 3), isFalse);
      expect(pelletsAcimaDoLimite('4 sacos de pellets', max: 3), isTrue);
      expect(pelletsAcimaDoLimite('2 sacos de pellets', max: 1), isTrue);
    });

    test('"palete" sem pellets não é com o Favor dos pellets', () {
      expect(sacosDePelletsPedidos('leva a palete de água'), isNull);
    });
  });
}
