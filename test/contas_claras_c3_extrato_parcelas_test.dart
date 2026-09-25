import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [contas-claras · C3 · 21/09/2026] O extrato do estafeta na app mostra as
/// MESMAS parcelas do recibo semanal por email — mesmos nomes, mesma ordem —
/// e vindas do servidor (`driver_settlement_parcelas`, chamada por
/// `weekly_closeout_compile` E por `extrato_prestador`). A app só formata.
///
/// O que se tranca aqui (só fonte; a igualdade ao cêntimo prova-se em SQL, ver
/// `.claude/.ai/provas/contas-claras-20260921/c3-extrato-igual-recibo.sql`):
///  1. o widget lê `parcelas` do servidor e não tem os nomes das parcelas
///     escritos à mão (senão voltavam a nascer gémeos: "Talões que adiantaste"
///     na app vs "Compras que adiantou do bolso" no email);
///  2. a migration do recibo e a do extrato usam a mesma função.
///
/// Cicatriz: a 21/09 o Valdemir recebeu por email "Entregas ×1 57,00" tendo
/// feito 1 entrega e 13 corridas, e a app dizia outra coisa com outros nomes.
void main() {
  final widget =
      File('lib/widgets/extrato_prestador_section.dart').readAsStringSync();
  final mig = File(
          'supabase/migrations/20260921092110_contas_claras_c3_parcelas_do_acerto_2026_09_21.sql')
      .readAsStringSync();

  group('a app só formata as parcelas do servidor', () {
    test('lê `parcelas` da previsão e de cada acerto', () {
      expect(widget, contains("_parcelasLinhas(semanaMap['parcelas']"));
      expect(widget, contains("_parcelasLinhas(a['parcelas']"));
    });

    test('não tem os nomes das parcelas escritos à mão', () {
      for (final nome in const [
        'Talões que adiantaste',
        'Ganhos (entregas + corridas)',
        'Dinheiro recebido em mão',
        'Compras que adiantou do bolso',
        'Tokens convertidos',
      ]) {
        expect(widget, isNot(contains("'$nome'")), reason: nome);
      }
    });
  });

  group('uma verdade só no servidor', () {
    test('o recibo e o extrato chamam driver_settlement_parcelas', () {
      // 1 definição + 1 chamada no recibo + 2 no extrato (acertos e previsão)
      expect(
          RegExp(r'driver_settlement_parcelas\(').allMatches(mig).length,
          greaterThanOrEqualTo(4));
      expect(mig, contains('CREATE OR REPLACE FUNCTION public.weekly_closeout_compile'));
      expect(mig, contains('CREATE OR REPLACE FUNCTION public.extrato_prestador'));
    });

    test('as cinco parcelas, pela ordem do recibo, vivem só na função', () {
      final ordem = [
        "'label','Entregas'",
        "'label','Corridas'",
        "'label','Compras que adiantou do bolso'",
        "'label','Tokens convertidos'",
        "'label','Dinheiro que recebeu em mão (devolve à Bora)'",
      ];
      var pos = -1;
      for (final l in ordem) {
        final i = mig.indexOf(l);
        expect(i, greaterThan(pos), reason: l);
        expect(mig.indexOf(l, i + 1), -1,
            reason: '$l só pode existir uma vez (na função única)');
        pos = i;
      }
    });
  });
}
