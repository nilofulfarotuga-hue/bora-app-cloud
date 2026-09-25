import 'package:bora_app/services/tvde_eta_display.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Missão TVDE 05/09] A regra do Danilo sobre o tempo que o PASSAGEIRO vê.
///
/// Ordem textual dele: o tempo mostrado deve ser 20 por cento menor que o real
/// — no exemplo dele, 10 minutos passam a mostrar 8.
///
/// O tecto de 2 minutos não é detalhe: sem ele, uma viagem de 30 minutos
/// mostrava 24, e isso é mentir grosso. Com tecto mostra 28.
///
/// Estes testes existem porque o número é afinável em `platform_settings` sem
/// build: se alguém puser uma percentagem disparatada no painel admin, o ecrã
/// do cliente NÃO pode passar a mostrar 0 min, negativos, ou mais tempo do que
/// o real.
void main() {
  group('ETA mostrado ao cliente — a regra dos 20 por cento', () {
    test('o exemplo do Danilo: 10 minutos mostram 8', () {
      expect(tvdeEtaShownMinutes(10), 8);
    });

    test('o tecto de 2 min trava o corte em viagens longas: 30 mostra 28', () {
      // Sem tecto seriam 24 (20% de 30 = 6). O tecto existe exactamente para
      // não mentir grosso a quem vai numa viagem comprida.
      expect(tvdeEtaShownMinutes(30), 28);
      expect(tvdeEtaShownMinutes(60), 58);
    });

    test('viagens curtas cortam pela percentagem, não pelo tecto', () {
      // 20% de 3 min = 0,6 min → menor que o tecto de 2, logo manda a percentagem.
      expect(tvdeEtaShownMinutes(3), 2);
    });

    test('nunca desce abaixo do mínimo de 1 minuto', () {
      expect(tvdeEtaShownMinutes(1), 1);
      expect(tvdeEtaShownMinutes(0), 1);
      expect(tvdeEtaShownMinutes(-5), 1);
    });

    test('o mostrado nunca é maior que o real', () {
      for (var real = 1; real <= 120; real++) {
        expect(tvdeEtaShownMinutes(real), lessThanOrEqualTo(real),
            reason: 'real=$real min produziu um mostrado maior que o real');
      }
    });

    test('o mostrado nunca é zero nem negativo, em nenhum valor', () {
      for (var real = -10; real <= 120; real++) {
        expect(tvdeEtaShownMinutes(real), greaterThanOrEqualTo(1),
            reason: 'real=$real min produziu um ETA de zero ou negativo');
      }
    });
  });

  group('valores vindos do painel admin — não podem partir o ecrã', () {
    test('percentagem a zero: mostra o tempo real, sem desconto', () {
      expect(tvdeEtaShownMinutes(10, discountPct: 0), 10);
    });

    test('percentagem negativa é tratada como zero, não aumenta o ETA', () {
      expect(tvdeEtaShownMinutes(10, discountPct: -50), 10);
    });

    test('percentagem acima de 100 fica travada nos 100 e respeita o chão', () {
      expect(tvdeEtaShownMinutes(10, discountPct: 500, discountMaxMin: 999), 1);
    });

    test('tecto a zero desliga o desconto', () {
      expect(tvdeEtaShownMinutes(10, discountMaxMin: 0), 10);
    });

    test('chão a zero é corrigido para 1 — nunca aparece "0 min"', () {
      expect(tvdeEtaShownMinutes(1, floorMin: 0), 1);
      expect(tvdeEtaShownMinutes(2, discountPct: 100, floorMin: 0),
          greaterThanOrEqualTo(1));
    });

    test('desligar o desconto no painel devolve o tempo real ao cliente', () {
      // É a saída de emergência do Danilo se decidir seguir o mercado: pôr a
      // percentagem a zero no admin faz o cliente ver o tempo verdadeiro,
      // sem esperar por build.
      for (var real = 1; real <= 60; real++) {
        expect(tvdeEtaShownMinutes(real, discountPct: 0), real);
      }
    });
  });
}
