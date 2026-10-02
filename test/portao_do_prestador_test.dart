import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/roles_service.dart';

/// O PORTÃO POR PAPEL (02/10/2026).
///
/// A primeira profissional de limpeza real ficou com `cleaners` aprovado e
/// presa em "em análise": o portão de entrada só olhava para `drivers`, onde
/// ela tinha uma linha pendente criada por arrasto. Estes testes guardam a
/// regra: entra quem tiver QUALQUER papel aprovado, e um papel pendente nunca
/// bloqueia outro já aprovado.
RolesSummary resumo({String? driver, String? cleaner, String? washer}) =>
    RolesSummary(
      hasDriver: driver != null,
      driverStatus: driver,
      hasCleaner: cleaner != null,
      cleanerStatus: cleaner,
      hasWasher: washer != null,
      washerStatus: washer,
      driverProfile: null,
      cleanerProfile: null,
      washerProfile: null,
    );

void main() {
  group('GUARDA: a ficha de estafeta só nasce da candidatura', () {
    test('o DriverStore não cria linhas em drivers por conta própria', () {
      // Criava (`_upsertDriverRow`): bastava uma profissional de limpeza
      // abrir o ecrã do estafeta para ganhar uma candidatura pendente sem
      // veículo nem documentos — provado em produção a 02/10/2026.
      final fonte = File('lib/stores/driver_store.dart').readAsStringSync();
      expect(fonte.contains(".from('drivers').upsert("), isFalse);
      expect(fonte.contains(".from('drivers').insert("), isFalse);
    });
  });

  group('um papel pendente nunca bloqueia outro já aprovado', () {
    test('o caso da Mayra: limpeza aprovada + estafeta pendente → limpeza', () {
      expect(
        entradaDoPrestador(resumo(driver: 'pending', cleaner: 'approved')),
        EntradaDoPrestador.limpeza,
      );
    });

    test('limpeza aprovada + estafeta recusado → limpeza', () {
      expect(
        entradaDoPrestador(resumo(driver: 'rejected', cleaner: 'approved')),
        EntradaDoPrestador.limpeza,
      );
    });

    test('lavagem aprovada + estafeta pendente → lavagem', () {
      expect(
        entradaDoPrestador(resumo(driver: 'pending', washer: 'approved')),
        EntradaDoPrestador.lavagem,
      );
    });

    test('estafeta aprovado + limpeza pendente → estafeta', () {
      expect(
        entradaDoPrestador(resumo(driver: 'approved', cleaner: 'pending')),
        EntradaDoPrestador.estafeta,
      );
    });
  });

  group('quem só faz limpeza não precisa de ficha de estafeta', () {
    test('só limpeza aprovada, sem linha em drivers → limpeza', () {
      expect(
        entradaDoPrestador(resumo(cleaner: 'approved')),
        EntradaDoPrestador.limpeza,
      );
    });

    test('só lavagem aprovada, sem linha em drivers → lavagem', () {
      expect(
        entradaDoPrestador(resumo(washer: 'approved')),
        EntradaDoPrestador.lavagem,
      );
    });
  });

  group('o que já funcionava continua igual', () {
    test('só estafeta aprovado → estafeta', () {
      expect(
        entradaDoPrestador(resumo(driver: 'approved')),
        EntradaDoPrestador.estafeta,
      );
    });

    test('estafeta e limpeza aprovados → estafeta (que tem o botão de troca)',
        () {
      expect(
        entradaDoPrestador(resumo(driver: 'approved', cleaner: 'approved')),
        EntradaDoPrestador.estafeta,
      );
    });
  });

  group('sem nenhum papel aprovado ninguém entra', () {
    test('quem não é nada', () {
      expect(
        entradaDoPrestador(RolesSummary.empty()),
        EntradaDoPrestador.nenhuma,
      );
    });

    test('tudo pendente', () {
      expect(
        entradaDoPrestador(
            resumo(driver: 'pending', cleaner: 'pending', washer: 'pending')),
        EntradaDoPrestador.nenhuma,
      );
    });

    test('limpeza suspensa não conta como aprovada', () {
      expect(
        entradaDoPrestador(resumo(cleaner: 'suspended')),
        EntradaDoPrestador.nenhuma,
      );
    });
  });
}
