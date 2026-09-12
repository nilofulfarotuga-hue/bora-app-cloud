import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/papeis_de_trabalho.dart';

/// A caixa "O que queres aceitar?" era um rádio de duas opções fixas. Quem
/// acumula quatro papéis via duas linhas e não tinha onde ligar a limpeza nem
/// a lavagem — a categoria estava no ar e o prestador não a via.
PapelDeTrabalho p(String papel, {bool aceita = true}) =>
    PapelDeTrabalho(papel: papel, aceita: aceita);

void main() {
  group('a caixa só aparece a quem tem escolha para fazer', () {
    test('quem tem um papel só não vê caixa nenhuma', () {
      expect(mostrarCaixaDePapeis([p('driver')]), isFalse);
    });

    test('quem tem dois vê', () {
      expect(mostrarCaixaDePapeis([p('driver'), p('cleaner')]), isTrue);
    });

    test('quem tem os quatro vê', () {
      expect(
        mostrarCaixaDePapeis(
            [p('driver'), p('delivery'), p('cleaner'), p('washer')]),
        isTrue,
      );
    });

    test('sem papéis, nada', () {
      expect(mostrarCaixaDePapeis(const <PapelDeTrabalho>[]), isFalse);
    });
  });

  group('não se desliga o último ligado', () {
    test('com dois ligados, pode desligar-se um', () {
      expect(podeDesligar([p('driver'), p('cleaner')]), isTrue);
    });

    test('com um só ligado, não', () {
      // Ficaria online sem receber nada — lê-se como avaria. Para parar de
      // todo existe o "estou online".
      expect(
        podeDesligar([p('driver'), p('cleaner', aceita: false)]),
        isFalse,
      );
    });

    test('com nenhum ligado (estado que não devia existir), também não', () {
      expect(
        podeDesligar([p('driver', aceita: false), p('cleaner', aceita: false)]),
        isFalse,
      );
    });

    test('o aviso diz o que fazer em vez de só recusar', () {
      expect(avisoUltimoPapel, contains('online'));
    });
  });

  group('os nomes que a pessoa lê', () {
    test('cada papel tem título e descrição em português', () {
      for (final papel in const ['driver', 'delivery', 'cleaner', 'washer']) {
        final x = p(papel);
        expect(x.titulo, isNotEmpty, reason: papel);
        expect(x.descricao, isNotEmpty, reason: papel);
        expect(x.titulo, isNot(equals(papel)),
            reason: '$papel ficou com o nome cru da base');
      }
    });

    test('a limpeza e a lavagem têm nome próprio, não são "outro"', () {
      expect(p('cleaner').titulo, 'Limpeza');
      expect(p('washer').titulo, 'Lavagem de carros');
    });

    test('as entregas são trabalho próprio, separado das corridas', () {
      // Antes de 2026-08-28 as entregas eram um MODO do papel de motorista, e
      // por isso quem só queria entregar tinha de se inscrever como motorista
      // de TVDE — que exige certificado do IMT e nada tem a ver com levar
      // comida. Os dois títulos não se podem confundir.
      expect(p('delivery').titulo, 'Entregas');
      expect(p('driver').titulo, 'Corridas de passageiros');
      expect(p('driver').titulo, isNot(startsWith('Entregas')),
          reason: 'o papel de corridas não pode dizer que faz entregas');
    });

    test('os quatro trabalhos existem e são distintos', () {
      final titulos = const ['driver', 'delivery', 'cleaner', 'washer']
          .map((x) => p(x).titulo)
          .toSet();
      expect(titulos.length, 4, reason: 'dois papéis com o mesmo nome');
    });

    test('um papel sem tradução NUNCA mostra o nome técnico', () {
      // Foi assim que apareceu "delivery", em inglês e minúsculas, no ecrã
      // do Danilo: o papel entrou na base antes de alguém lhe dar nome.
      expect(p('futuro').titulo, isNot('futuro'));
      expect(p('futuro').titulo, 'Outro trabalho');
      expect(p('futuro').temNomeProprio, isFalse);
    });

    test('TODOS os papéis conhecidos têm nome de gente', () {
      // Esta é a guarda: papel novo na base sem tradução rebenta aqui, e não
      // no telemóvel do Danilo.
      for (final papel in PapelDeTrabalho.conhecidos) {
        expect(p(papel).temNomeProprio, isTrue,
            reason: '$papel chegou ao ecrã sem nome em português');
      }
    });

    test('as palavras são as que o Danilo confirmou no ecrã real', () {
      // Aprovadas por ele a 2026-08-28, depois de actualizar a app. Mudar
      // isto sem ordem dele é desfazer o que ele já validou.
      expect(p('driver').titulo, 'Corridas de passageiros');
      expect(p('driver').descricao, 'Levar pessoas de um lado ao outro.');
      expect(p('delivery').titulo, 'Entregas');
      expect(p('delivery').descricao, 'Levar comida, compras e encomendas.');
    });
  });

  group('copyWith e igualdade', () {
    test('mudar o interruptor não mexe no papel', () {
      final antes = p('cleaner');
      final depois = antes.copyWith(aceita: false);
      expect(depois.papel, 'cleaner');
      expect(depois.aceita, isFalse);
      expect(antes.aceita, isTrue, reason: 'o original não pode mudar');
    });

    test('dois iguais são iguais', () {
      expect(p('driver'), equals(p('driver')));
      expect(p('driver'), isNot(equals(p('driver', aceita: false))));
    });
  });
}
