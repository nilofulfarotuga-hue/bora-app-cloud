// O AMIGO — motor, boca e rosto (missão m11-amigo-rosto, 09/11/2026).
import 'package:bora_app/widgets/amigo/amigo_boca.dart';
import 'package:bora_app/widgets/amigo/amigo_motor.dart';
import 'package:bora_app/widgets/amigo/amigo_rosto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emoção do servidor', () {
    test('os 6 nomes do pedido e os extra', () {
      expect(amigoEmocaoDe('alegre'), AmigoEmocao.alegre);
      expect(amigoEmocaoDe('triste'), AmigoEmocao.triste);
      expect(amigoEmocaoDe('surpreso'), AmigoEmocao.surpreso);
      expect(amigoEmocaoDe('pensativo'), AmigoEmocao.pensativo);
      expect(amigoEmocaoDe('confuso'), AmigoEmocao.confuso);
      expect(amigoEmocaoDe('a_falar'), AmigoEmocao.aFalar);
      expect(amigoEmocaoDe(' Alegre '), AmigoEmocao.alegre);
      expect(amigoEmocaoDe(null), isNull);
      expect(amigoEmocaoDe('zangado'), isNull);
      for (final e in AmigoEmocao.values) {
        expect(amigoEmocaoDe(amigoEmocaoNome(e)), e);
      }
    });

    test('variante do painel: por defeito com camisa', () {
      expect(amigoVarianteDe('rosto'), AmigoVariante.rosto);
      expect(amigoVarianteDe('"rosto"'), AmigoVariante.rosto);
      expect(amigoVarianteDe('rosto_camisa'), AmigoVariante.rostoCamisa);
      expect(amigoVarianteDe(null), AmigoVariante.rostoCamisa);
      expect(amigoVarianteDe('qualquer'), AmigoVariante.rostoCamisa);
    });
  });

  group('boca (visemas do português de Portugal)', () {
    test('palavras viram formas de boca', () {
      expect(amigoFonemas('pão').map((f) => f.$1).toList(), ['M', 'O']);
      expect(amigoFonemas('Amigo').map((f) => f.$1).toList(), ['A', 'M', 'I', 'C', 'O']);
      expect(amigoFonemas('fala').map((f) => f.$1).toList(), ['F', 'A', 'L', 'A']);
      // "e" final quase mudo em PT-PT
      expect(amigoFonemas('sete').last, ('C', .5));
      expect(amigoFonemas('chá').first.$1, 'S');
      expect(amigoFonemas('25').isNotEmpty, isTrue, reason: 'números dizem-se');
      expect(amigoFonemas('!!!'), isEmpty);
    });

    test('a fala estima tempos e fecha a boca no fim', () {
      final f = AmigoFala('Olá, eu sou o Amigo.');
      expect(f.palavras.length, 5);
      for (var i = 1; i < f.palavras.length; i++) {
        expect(f.palavras[i].t, greaterThan(f.palavras[i - 1].t));
      }
      expect(f.duracaoEstimada, inInclusiveRange(1200, 3500));
      // antes de começar: boca fechada
      expect(f.formaEm(0).o, 0);
      f.comecou(1000);
      // a meio da primeira palavra a boca abre
      final meio = 1000 + f.palavras.first.d / 2;
      expect(f.formaEm(meio).o, greaterThan(0.1));
      // muito depois do fim: repouso
      expect(f.formaEm(1000 + f.duracaoEstimada + 2000).o, 0);
    });

    test('o evento de palavra do motor de voz acerta o relógio', () {
      final f = AmigoFala('Quero um hambúrguer agora mesmo.');
      f.comecou(0);
      // o motor diz que a 3.ª palavra ("hambúrguer", letra 9) começou aos 2000 ms
      f.palavraComecou(9, 2000);
      expect(f.palavraEm(2001), 2);
      expect(f.posicao(2000), closeTo(f.palavras[2].t, 0.001));
      expect(f.desvios.single, isNot(0));
      // a 4.ª palavra chega mais cedo do que o estimado → acelera
      final antes = f.posicao(2100);
      f.palavraComecou(f.palavras[3].inicio, 2150);
      expect(f.palavraEm(2151), 3);
      expect(f.posicao(2150), greaterThan(antes));
    });

    test('velocidade maior encurta a fala', () {
      final normal = AmigoFala('Tens fome? Diz-me o que te apetece.');
      final rapida = AmigoFala('Tens fome? Diz-me o que te apetece.', velocidade: 1.5);
      expect(rapida.duracaoEstimada, lessThan(normal.duracaoEstimada));
    });
  });

  group('motor (está vivo)', () {
    test('pestaneja com tempo natural e abre outra vez', () {
      final m = AmigoMotor(semente: 7);
      var fechos = 0;
      var fechadoDesde = -1.0;
      final duracoes = <double>[];
      for (var i = 0; i < 60 * 12; i++) {
        m.update(1 / 60);
        if (m.pf < 0.05 && fechadoDesde < 0) {
          fechadoDesde = m.t;
          fechos++;
        }
        if (m.pf > 0.95 && fechadoDesde >= 0) {
          duracoes.add(m.t - fechadoDesde);
          fechadoDesde = -1;
        }
      }
      // 12 s: entre 2 e 7 piscadelas (de 2,4 a 5,2 s, às vezes duplas)
      expect(fechos, inInclusiveRange(2, 7));
      for (final d in duracoes) {
        expect(d, lessThan(0.2), reason: 'olho fechado no máximo ~0,1 s');
      }
    });

    test('parado não pestaneja nem mexe o olhar', () {
      final m = AmigoMotor(semente: 7, parado: true);
      for (var i = 0; i < 60 * 8; i++) {
        m.update(1 / 60);
        expect(m.pf, 1);
      }
      expect(m.v(AmigoP.lookX), closeTo(0, 1e-9));
    });

    test('muda de cara suavemente (sem salto seco) e chega ao alvo', () {
      final m = AmigoMotor(semente: 1, parado: true);
      m.setEmocao(AmigoEmocao.surpreso);
      final alvo = amigoAlvos(AmigoEmocao.surpreso)[AmigoP.openL.index];
      m.update(1 / 60);
      final depois1 = m.v(AmigoP.openL);
      expect(depois1, greaterThan(1));
      expect(depois1, lessThan(1 + (alvo - 1) * 0.5),
          reason: 'numa imagem só não pode andar mais de metade do caminho');
      for (var i = 0; i < 60; i++) {
        m.update(1 / 60);
      }
      expect(m.v(AmigoP.openL), closeTo(alvo, 0.02));
    });

    test('antecipação: a mola encolhe e estica ao mudar de cara', () {
      final m = AmigoMotor(semente: 1, parado: true);
      m.setEmocao(AmigoEmocao.alegre);
      var mexeu = 0.0;
      for (var i = 0; i < 30; i++) {
        m.update(1 / 60);
        if (m.sq.abs() > mexeu) mexeu = m.sq.abs();
      }
      expect(mexeu, greaterThan(0.005));
      for (var i = 0; i < 200; i++) {
        m.update(1 / 60);
      }
      expect(m.sq.abs(), lessThan(0.002), reason: 'a mola assenta');
    });

    test('reduzir movimento: sem mola nem saltos do olhar', () {
      final m = AmigoMotor(semente: 3, reduzirMovimento: true);
      m.setEmocao(AmigoEmocao.surpreso);
      for (var i = 0; i < 120; i++) {
        m.update(1 / 60);
        expect(m.sq.abs(), lessThan(0.001));
      }
      expect(m.respiracao, 0);
    });

    test('acordar: olhos fechados no início e depois abertos', () {
      final m = AmigoMotor(semente: 2);
      m.acordar();
      m.update(1 / 60);
      expect(m.pf, 0);
      for (var i = 0; i < 40; i++) {
        m.update(1 / 60);
      }
      expect(m.pf, greaterThan(0.9));
    });

    test('a falar: a boca segue a forma da fala', () {
      final m = AmigoMotor(semente: 2, parado: true);
      m.fala = const AmigoBocaForma(1, 1.05, 0, vol: .6);
      for (var i = 0; i < 20; i++) {
        m.update(1 / 60);
      }
      expect(m.v(AmigoP.mo), greaterThan(20));
      m.fala = kAmigoVisemas['M'];
      for (var i = 0; i < 20; i++) {
        m.update(1 / 60);
      }
      expect(m.v(AmigoP.mo), lessThan(3), reason: 'm/b/p fecham a boca');
    });

    test('símbolo aparece por cima: ! ? …', () {
      final m = AmigoMotor(semente: 2, parado: true)..saltarPara(AmigoEmocao.confuso);
      expect(m.simbolo, '?');
      expect(amigoSimbolo(AmigoEmocao.surpreso), '!');
      expect(amigoSimbolo(AmigoEmocao.pensativo), '…');
      expect(amigoSimbolo(AmigoEmocao.alegre), '');
    });
  });

  group('AmigoRosto (widget)', () {
    testWidgets('anima sozinho, aceita a boca da fala e o tamanho pequeno', (tester) async {
      var chamadas = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const AmigoRosto(tamanho: 40),
            AmigoRosto(
              tamanho: 240,
              emocao: AmigoEmocao.alegre,
              variante: AmigoVariante.rostoCamisa,
              boca: () {
                chamadas++;
                return const AmigoBocaForma(.6, 1, 0, vol: .5);
              },
            ),
          ]),
        ),
      ));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(chamadas, greaterThan(60), reason: 'a boca é lida a cada imagem');
      expect(find.bySemanticsLabel('Amigo, alegre'), findsOneWidget);
      final tam = tester.getSize(find.byType(AmigoRosto).first);
      expect(tam.width, 40);
      expect(AmigoRosto.alturaPara(240, AmigoVariante.rostoCamisa),
          greaterThan(AmigoRosto.alturaPara(240, AmigoVariante.rosto)));
    });

    testWidgets('troca de expressão sem rebentar e "reduzir movimento"', (tester) async {
      Widget app(AmigoEmocao e) => MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(body: AmigoRosto(tamanho: 200, emocao: e)),
            ),
          );
      await tester.pumpWidget(app(AmigoEmocao.neutro));
      for (final e in AmigoEmocao.values) {
        await tester.pumpWidget(app(e));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
