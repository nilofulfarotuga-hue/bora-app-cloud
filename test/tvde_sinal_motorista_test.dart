import 'package:bora_app/utils/tvde_sinal_motorista.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Missão TVDE 05/09, parte 2 — Bloco 2C] A função `tvde_ride_driver_card`
/// já devolvia `location_updated_at` e ninguém a lia.
///
/// **O que isso custava ao cliente:** um motorista com o GPS morto aparecia
/// exactamente como um motorista parado — carro imóvel no mapa, sem
/// explicação. A pessoa ficava a olhar sem saber se o carro tinha avariado,
/// se o motorista tinha desistido, ou se era a app que estava presa.
///
/// O relógio é injectado de propósito: sem isso o teste dependia da hora da
/// máquina e passava ou falhava conforme o dia.
void main() {
  final agora = DateTime.utc(2026, 9, 5, 14, 0, 0);
  DateTime haSegundos(int s) => agora.subtract(Duration(seconds: s));

  group('os três estados do sinal', () {
    test('posição de há 10 segundos está fresca — o carro anima', () {
      final e = estadoDoSinal(haSegundos(10), agora: agora);
      expect(e, EstadoSinalMotorista.fresco);
      expect(devoAnimarCarro(e), isTrue);
    });

    test('posição com MAIS de 45 segundos marca sinal velho', () {
      // É o limite que a ordem pede: `tvde_driver_stale_seconds` = 45.
      expect(estadoDoSinal(haSegundos(46), agora: agora),
          EstadoSinalMotorista.velho);
      expect(estadoDoSinal(haSegundos(120), agora: agora),
          EstadoSinalMotorista.velho);
    });

    test('exactamente 45 segundos já conta como velho', () {
      expect(estadoDoSinal(haSegundos(45), agora: agora),
          EstadoSinalMotorista.velho);
    });

    test('44 segundos ainda é fresco — a fronteira não escorrega', () {
      expect(estadoDoSinal(haSegundos(44), agora: agora),
          EstadoSinalMotorista.fresco);
    });

    test('com sinal velho o carro PÁRA de animar', () {
      // Sem isto, o carro continuava a deslizar por cima da rota com uma
      // posição de três minutos — a fingir um movimento que não existe.
      expect(devoAnimarCarro(estadoDoSinal(haSegundos(60), agora: agora)),
          isFalse);
    });

    test('passados 180 segundos o sinal dá-se por perdido', () {
      expect(estadoDoSinal(haSegundos(180), agora: agora),
          EstadoSinalMotorista.perdido);
      expect(estadoDoSinal(haSegundos(600), agora: agora),
          EstadoSinalMotorista.perdido);
    });

    test('sem posição nenhuma não se inventa estado', () {
      expect(estadoDoSinal(null, agora: agora),
          EstadoSinalMotorista.semPosicao);
      expect(devoAnimarCarro(EstadoSinalMotorista.semPosicao), isFalse);
    });
  });

  group('o relógio do telemóvel pode estar errado', () {
    test('posição no futuro não dá idade negativa', () {
      // Telemóvel adiantado em relação ao servidor. "Última posição há -3 min"
      // é pior do que não dizer nada.
      final futuro = agora.add(const Duration(seconds: 90));
      expect(segundosDesdeFix(futuro, agora: agora), 0);
      expect(estadoDoSinal(futuro, agora: agora), EstadoSinalMotorista.fresco);
    });

    test('a hora vem em UTC ou local, e dá o mesmo', () {
      final local = haSegundos(60).toLocal();
      expect(estadoDoSinal(local, agora: agora), EstadoSinalMotorista.velho);
    });
  });

  group('valores vindos do painel admin não podem partir o ecrã', () {
    test('os limites são afináveis', () {
      expect(estadoDoSinal(haSegundos(20), agora: agora, staleSeconds: 10),
          EstadoSinalMotorista.velho);
      expect(estadoDoSinal(haSegundos(50), agora: agora, staleSeconds: 90),
          EstadoSinalMotorista.fresco);
    });

    test('"perdido" abaixo de "velho" não faz o estado velho desaparecer', () {
      // Se alguém puser lost=10 e stale=45 no painel, sem correcção o cliente
      // saltava de "tudo bem" directamente para "a ligar-se", e o estado
      // "velho" — o que explica o carro parado — nunca aparecia. A função
      // empurra o `lost` para logo acima do `stale`, e o "velho" sobrevive.
      final e = estadoDoSinal(haSegundos(45),
          agora: agora, staleSeconds: 45, lostSeconds: 10);
      expect(e, EstadoSinalMotorista.velho);
      // E "perdido" continua a existir a seguir, não desaparece também.
      expect(
          estadoDoSinal(haSegundos(46),
              agora: agora, staleSeconds: 45, lostSeconds: 10),
          EstadoSinalMotorista.perdido);
    });

    test('stale a zero é corrigido para 1 — nunca marca tudo como velho', () {
      expect(estadoDoSinal(haSegundos(0), agora: agora, staleSeconds: 0),
          EstadoSinalMotorista.fresco);
    });
  });

  group('a idade em segundos, que é o que o ecrã mostra ao cliente', () {
    // O ecrã escolhe entre "há X s" e "há X min" a partir deste número, e
    // monta a frase com `.tr` sobre as chaves do dicionário. A conversão para
    // texto NÃO vive aqui de propósito: um helper que devolvesse português
    // cru mostrava português a um cliente em inglês (ver nota no ficheiro).
    test('conta os segundos desde a última posição', () {
      expect(segundosDesdeFix(haSegundos(50), agora: agora), 50);
      expect(segundosDesdeFix(haSegundos(185), agora: agora), 185);
    });

    test('sem posição não há idade nenhuma para mostrar', () {
      expect(segundosDesdeFix(null, agora: agora), isNull);
    });
  });
}
