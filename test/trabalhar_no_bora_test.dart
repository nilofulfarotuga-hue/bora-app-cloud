import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/roles_service.dart';

/// A PORTA "Quero trabalhar no Bora".
///
/// Até 2026-08-29 a candidatura da Limpeza estava a quatro níveis de
/// profundidade (só se lá chegava a partir do painel de quem JÁ era faxineiro)
/// e a da Lavagem não existia de todo. Estes testes guardam a porta: as quatro
/// actividades têm de aparecer, com o estado certo, e nenhuma pode desaparecer
/// sem rebentar aqui.
RolesSummary resumo({
  String? driver,
  String? cleaner,
  String? washer,
  Map<String, dynamic>? perfilDriver,
  Map<String, dynamic>? perfilCleaner,
  Map<String, dynamic>? perfilWasher,
}) =>
    RolesSummary(
      hasDriver: driver != null,
      driverStatus: driver,
      hasCleaner: cleaner != null,
      cleanerStatus: cleaner,
      hasWasher: washer != null,
      washerStatus: washer,
      driverProfile: perfilDriver,
      cleanerProfile: perfilCleaner,
      washerProfile: perfilWasher,
    );

void main() {
  group('a porta mostra sempre as quatro actividades', () {
    test('quem não é nada vê as quatro, todas por candidatar', () {
      final a = atividadesDisponiveis(RolesSummary.empty());
      expect(a.length, 4);
      expect(a.map((x) => x.papel).toList(),
          ['delivery', 'driver', 'cleaner', 'washer']);
      expect(a.every((x) => x.estado == CrossRoleCardState.invite), isTrue);
      expect(a.every((x) => x.rotuloDeEstado == 'Candidatar-me'), isTrue);
    });

    test('a lavagem está lá — foi a que nunca teve porta nenhuma', () {
      final a = atividadesDisponiveis(RolesSummary.empty());
      final lavagem = a.firstWhere((x) => x.papel == 'washer');
      expect(lavagem.titulo, 'Lavagem de carros');
      expect(lavagem.descricao, isNotEmpty);
    });

    test('nenhuma actividade mostra o nome técnico do papel', () {
      // Foi assim que apareceu "delivery", em inglês, no ecrã do Danilo.
      for (final x in atividadesDisponiveis(RolesSummary.empty())) {
        expect(x.titulo, isNot(equals(x.papel)), reason: x.papel);
        expect(x.titulo, isNotEmpty);
        expect(x.descricao, isNotEmpty);
      }
    });
  });

  group('o estado de cada linha vem do estado real da candidatura', () {
    test('aprovada lê-se "Já fazes"', () {
      final a = atividadesDisponiveis(resumo(cleaner: 'approved'));
      final limpeza = a.firstWhere((x) => x.papel == 'cleaner');
      expect(limpeza.jaFaz, isTrue);
      expect(limpeza.rotuloDeEstado, 'Já fazes');
    });

    test('pendente lê-se "Em análise" e não deixa recandidatar', () {
      final a = atividadesDisponiveis(resumo(washer: 'pending'));
      final lavagem = a.firstWhere((x) => x.papel == 'washer');
      expect(lavagem.emAnalise, isTrue);
      expect(lavagem.jaFaz, isFalse);
      expect(lavagem.rotuloDeEstado, 'Em análise');
    });

    test('recusada volta a convidar — recandidatar-se é permitido', () {
      final a = atividadesDisponiveis(resumo(cleaner: 'rejected'));
      expect(a.firstWhere((x) => x.papel == 'cleaner').estado,
          CrossRoleCardState.invite);
    });

    test('entregas e corridas partilham a candidatura de estafeta', () {
      // Vivem os dois na tabela `drivers`: quem já é estafeta não se
      // recandidata para passar a fazer corridas — liga o interruptor.
      final a = atividadesDisponiveis(resumo(driver: 'approved'));
      expect(a.firstWhere((x) => x.papel == 'delivery').jaFaz, isTrue);
      expect(a.firstWhere((x) => x.papel == 'driver').jaFaz, isTrue);
    });

    test('ser estafeta não faz de ninguém faxineiro nem lavador', () {
      final a = atividadesDisponiveis(resumo(driver: 'approved'));
      expect(a.firstWhere((x) => x.papel == 'cleaner').jaFaz, isFalse);
      expect(a.firstWhere((x) => x.papel == 'washer').jaFaz, isFalse);
    });
  });

  group('os dados só se preenchem uma vez', () {
    const perfil = {'name': 'Ana', 'phone': '910000000', 'nif': '123456789'};

    test('sem papel nenhum, não há nada para pré-preencher', () {
      expect(RolesSummary.empty().dadosJaConhecidos, isNull);
      expect(RolesSummary.empty().temAlgumPapel, isFalse);
    });

    test('o perfil de estafeta serve a candidatura seguinte', () {
      final r = resumo(driver: 'approved', perfilDriver: perfil);
      expect(r.dadosJaConhecidos, perfil);
      expect(r.temAlgumPapel, isTrue);
    });

    test('quem só é faxineiro leva os dados da limpeza', () {
      final r = resumo(cleaner: 'approved', perfilCleaner: perfil);
      expect(r.dadosJaConhecidos, perfil);
    });

    test('quem só é lavador leva os dados da lavagem', () {
      final r = resumo(washer: 'approved', perfilWasher: perfil);
      expect(r.dadosJaConhecidos, perfil);
    });
  });

  group('o resumo lê o que a base devolve, sem inventar', () {
    test('a lavagem chega do JSON da RPC', () {
      final r = RolesSummary.fromJson({
        'has_driver': false,
        'has_cleaner': false,
        'has_washer': true,
        'washer_status': 'pending',
        'washer_profile': {'name': 'Zé'},
      });
      expect(r.hasWasher, isTrue);
      expect(r.washerPending, isTrue);
      expect(r.washerApproved, isFalse);
      expect(r.washerProfile?['name'], 'Zé');
    });

    test('JSON antigo (sem lavagem) não rebenta', () {
      // Um telemóvel com a app velha a falar com a base nova, ou o contrário.
      final r = RolesSummary.fromJson({
        'has_driver': true,
        'driver_status': 'approved',
        'has_cleaner': false,
      });
      expect(r.hasWasher, isFalse);
      expect(r.washerStatus, isNull);
      expect(atividadesDisponiveis(r).length, 4);
    });
  });
}
