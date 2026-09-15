import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/atividades_prestador.dart';

/// A regra do Danilo: os papéis ACUMULAM-SE, nunca se substituem. A mesma
/// pessoa pode ser estafeta, motorista, faxineiro e lavador ao mesmo tempo.
void main() {
  group('papeisPara', () {
    test('Entregas e Viagens dão UM papel driver, não dois', () {
      // Por dentro é a mesma pessoa e a mesma tabela; separam-se só na
      // escolha porque para o candidato são coisas diferentes. Se isto
      // devolvesse dois, criavam-se linhas repetidas em user_roles e a
      // candidatura era submetida a dobrar.
      expect(papeisPara([Atividade.entregas, Atividade.viagens]),
          equals({'driver'}));
    });

    test('as quatro actividades dão três papéis', () {
      expect(
        papeisPara(Atividade.values),
        equals({'driver', 'cleaner', 'washer'}),
      );
    });

    test('nenhuma actividade dá nenhum papel', () {
      expect(papeisPara(const <Atividade>[]), isEmpty);
    });
  });

  group('papeisEmFalta — não pedir outra vez o que já foi dado', () {
    test('quem já é motorista e escolhe lavagem só trata do washer', () {
      expect(
        papeisEmFalta([Atividade.lavagem], ['driver']),
        equals({'washer'}),
      );
    });

    test('quem já é motorista e escolhe entregas não tem nada a tratar', () {
      expect(papeisEmFalta([Atividade.entregas], ['driver']), isEmpty);
    });

    test('quem não tem nada e escolhe tudo trata dos três', () {
      expect(
        papeisEmFalta(Atividade.values, const <String>[]),
        equals({'driver', 'cleaner', 'washer'}),
      );
    });

    test('o papel de cliente não conta como papel de trabalho', () {
      // Toda a gente é cliente; isso não pode fazer parecer que já se
      // trabalha em alguma coisa.
      expect(
        papeisEmFalta([Atividade.limpeza], ['client']),
        equals({'cleaner'}),
      );
    });
  });

  group('escolhaValida', () {
    test('sem escolher nada não se submete', () {
      expect(escolhaValida(const <Atividade>[], const <String>[]), isFalse);
    });

    test('escolher só o que já se tem não se submete', () {
      expect(escolhaValida([Atividade.entregas], ['driver']), isFalse);
    });

    test('escolher algo novo submete-se', () {
      expect(escolhaValida([Atividade.limpeza], ['driver']), isTrue);
    });

    test('mistura de novo e velho submete-se, pelo novo', () {
      expect(
        escolhaValida([Atividade.entregas, Atividade.lavagem], ['driver']),
        isTrue,
      );
    });
  });

  group('avisoJaTemTudo', () {
    test('cala-se quando não há escolha nenhuma', () {
      expect(avisoJaTemTudo(const <Atividade>[], const <String>[]), isNull);
    });

    test('cala-se quando há mesmo coisa nova para tratar', () {
      expect(avisoJaTemTudo([Atividade.limpeza], ['driver']), isNull);
    });

    test('explica, no singular, quando já se exerce a única escolhida', () {
      final aviso = avisoJaTemTudo([Atividade.entregas], ['driver']);
      expect(aviso, isNotNull);
      expect(aviso, contains('entregas'));
      expect(aviso, contains('perfil'));
    });

    test('explica, no plural, quando já se exerce tudo o que escolheu', () {
      final aviso =
          avisoJaTemTudo([Atividade.entregas, Atividade.viagens], ['driver']);
      expect(aviso, contains('todas estas actividades'));
    });
  });

  group('os slugs são os nomes reais na base — não renomear', () {
    test('cada actividade aponta para o papel certo', () {
      expect(Atividade.entregas.slug, 'driver');
      expect(Atividade.viagens.slug, 'driver');
      expect(Atividade.limpeza.slug, 'cleaner');
      expect(Atividade.lavagem.slug, 'washer');
    });

    test('toda a actividade tem título e descrição para o candidato ler', () {
      for (final a in Atividade.values) {
        expect(a.titulo.trim(), isNotEmpty, reason: a.name);
        expect(a.descricao.trim(), isNotEmpty, reason: a.name);
      }
    });
  });
}
