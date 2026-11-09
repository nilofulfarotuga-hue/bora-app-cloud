// O AMIGO — o motor da animação (missão m11-amigo-rosto, 09/11/2026).
//
// Porta para Dart do `update()` do protótipo do Dipsy (amigo.js): cada parte
// da cara vai para o alvo da expressão à sua velocidade (olhos rápidos,
// cabeça lenta), pestaneja com tempo natural (fecha 55 ms, fechado 25 ms,
// abre 80 ms; 2,4–5,2 s; 15 % duplo), o olhar dá pequenos saltos de 0,8 a
// 2,6 s, respira (ciclo de 3,8 s) e há uma mola de "encolhe e estica" que dá
// a antecipação quando muda de cara. Sem Flutter aqui: é testado à parte.

import 'dart:math' as math;

import 'amigo_boca.dart';
import 'amigo_emocao.dart';

double _lim(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// Estado do pestanejar.
class _Pisca {
  double prox = 1.2;
  double ini = 0;
  bool ativo = false;
  bool duplo = false;
}

class AmigoMotor {
  AmigoMotor({
    int? semente,
    this.parado = false,
    this.reduzirMovimento = false,
  }) : _rnd = math.Random(semente ?? 20261108) {
    p = amigoAlvos(AmigoEmocao.neutro);
    alvo = List.of(p);
  }

  final math.Random _rnd;

  /// Para capturas e testes: sem pestanejar, sem saltos do olhar, sem
  /// respiração — a expressão fica parada no alvo.
  bool parado;

  /// "Reduzir movimento" do sistema: anima menos (sem saltos do olhar, sem
  /// mola, sem aceno), mas continua a pestanejar e a mudar de cara.
  bool reduzirMovimento;

  /// Valores atuais e alvos, indexados por [AmigoP.index].
  late List<double> p;
  late List<double> alvo;

  AmigoEmocao emocao = AmigoEmocao.neutro;

  /// Tempo (s) desde que o motor nasceu.
  double t = 0;

  final _Pisca _pisca = _Pisca();
  double _olharX = 0;
  double _olharY = 0;
  double _olharProx = 0.6;

  /// Mola do encolhe-estica (antecipação).
  double sq = 0;
  double _sqV = 0;

  /// A boca da fala neste instante (null = calado).
  AmigoBocaForma? fala;

  /// Força da voz agora (0..1), para os gestos.
  double energia = 0;

  /// Quando mudou de expressão (s), para o aceno do braço.
  double mudouEm = -9;

  /// Abertura do pestanejar (1 aberto, 0 fechado) do último quadro.
  double pf = 1;

  /// Símbolo por cima da cabeça e a sua opacidade (0..1).
  String simbolo = '';
  double simboloA = 0;

  /// "Acordar": olhos fechados até este instante (s), depois abre com mola.
  double _acordarAte = -1;

  double v(AmigoP k) => p[k.index];

  void setEmocao(AmigoEmocao e) {
    if (e != emocao) {
      if (!reduzirMovimento) {
        _sqV += switch (e) {
          AmigoEmocao.surpreso => -1.6,
          AmigoEmocao.triste => 0.5,
          AmigoEmocao.alegre => -1.2,
          _ => -0.7,
        };
      }
      mudouEm = t;
      if (!parado && _rnd.nextDouble() < 0.55 && !_pisca.ativo) {
        _pisca.prox = t + 0.04;
      }
    }
    emocao = e;
    alvo = amigoAlvos(e);
  }

  /// Muda de cara sem transição (capturas, testes, painel).
  void saltarPara(AmigoEmocao e) {
    emocao = e;
    alvo = amigoAlvos(e);
    p = List.of(alvo);
    simbolo = amigoSimbolo(e);
    simboloA = simbolo.isEmpty ? 0 : 1;
    sq = 0;
    _sqV = 0;
  }

  /// Pequena animação de entrada: olhos fechados meio segundo e depois abre
  /// com um salto (o Amigo "acorda").
  void acordar() {
    _acordarAte = t + 0.45;
    p[AmigoP.headY.index] = 10;
  }

  void update(double dt) {
    dt = _lim(dt, 0, 0.1);
    t += dt;
    final a = alvo;
    final falar = fala != null;

    // ── olhar: saltos rápidos de 0,8 a 2,6 s
    var lx = a[AmigoP.lookX.index];
    var ly = a[AmigoP.lookY.index];
    if (!parado && !reduzirMovimento) {
      if (t > _olharProx) {
        final amp = (emocao == AmigoEmocao.pensativo || emocao == AmigoEmocao.triste)
            ? 0.18
            : (falar ? 0.25 : 0.55);
        _olharX = (_rnd.nextDouble() - .5) * amp;
        _olharY = (_rnd.nextDouble() - .5) * amp * 0.6;
        _olharProx = t + 0.8 + _rnd.nextDouble() * 1.8;
      }
      lx += _olharX;
      ly += _olharY;
    }

    // ── pestanejar: fecha 55 ms, fechado 25 ms, abre 80 ms; 15 % duplo
    var abre = 1.0;
    final pi = _pisca;
    if (!parado) {
      if (!pi.ativo && t >= pi.prox) {
        pi.ativo = true;
        pi.ini = t;
      }
      if (pi.ativo) {
        final e = (t - pi.ini) * 1000;
        if (e < 55) {
          abre = 1 - e / 55;
        } else if (e < 80) {
          abre = 0;
        } else if (e < 160) {
          abre = (e - 80) / 80;
        } else {
          pi.ativo = false;
          if (!pi.duplo && _rnd.nextDouble() < 0.15) {
            pi.duplo = true;
            pi.prox = t + 0.09;
          } else {
            pi.duplo = false;
            pi.prox = t + 2.4 + _rnd.nextDouble() * 2.8;
          }
        }
        abre = abre * abre * (3 - 2 * abre);
      }
    }
    if (t < _acordarAte) {
      abre = 0;
    } else if (_acordarAte > 0 && t - _acordarAte < dt + 0.0001) {
      if (!reduzirMovimento) _sqV -= 1.4;
    }
    pf = abre;

    // ── boca: expressão + fala
    var mo = a[AmigoP.mo.index];
    var mw = a[AmigoP.mw.index];
    var rd = a[AmigoP.round.index];
    var sm = a[AmigoP.sm.index];
    var mx = a[AmigoP.mx.index];
    var mAs = a[AmigoP.mAsym.index];
    final f = fala;
    if (f != null) {
      mo = 1 + f.o * 25 + a[AmigoP.mo.index] * 0.15;
      mw = (a[AmigoP.mw.index] + (1 - a[AmigoP.mw.index]) * 0.55) * f.w;
      rd = math.max(f.r, a[AmigoP.round.index] * 0.4);
      sm = a[AmigoP.sm.index] * 0.55;
      mx = a[AmigoP.mx.index] * 0.3;
      mAs = a[AmigoP.mAsym.index] * 0.4;
    }

    // ── suavizar (cada parte à sua velocidade)
    void seg(AmigoP k, double alvoV, double vel) {
      final i = k.index;
      p[i] += (alvoV - p[i]) * (1 - math.exp(-dt * vel));
    }

    seg(AmigoP.lookX, lx, 26);
    seg(AmigoP.lookY, ly, 26);
    for (final k in const [
      AmigoP.openL,
      AmigoP.openR,
      AmigoP.bottom,
      AmigoP.lidSlant,
      AmigoP.eyeW,
      AmigoP.pupil,
    ]) {
      seg(k, a[k.index], 14);
    }
    for (final k in const [AmigoP.browL, AmigoP.browR, AmigoP.browSlL, AmigoP.browSlR]) {
      seg(k, a[k.index], 12);
    }
    seg(AmigoP.mo, mo, falar ? 38 : 14);
    seg(AmigoP.mw, mw, falar ? 32 : 12);
    seg(AmigoP.round, rd, falar ? 32 : 12);
    seg(AmigoP.sm, sm, 12);
    seg(AmigoP.mx, mx, 10);
    seg(AmigoP.mAsym, mAs, 10);
    for (final k in const [AmigoP.tilt, AmigoP.headX, AmigoP.headY]) {
      seg(k, a[k.index], 6);
    }
    seg(AmigoP.blush, a[AmigoP.blush.index], 5);
    seg(AmigoP.ant, a[AmigoP.ant.index], 5);
    seg(AmigoP.armL, a[AmigoP.armL.index], 7);
    seg(AmigoP.armR, a[AmigoP.armR.index], 7);

    // ── mola do encolhe-estica
    _sqV += (-170 * sq - 11 * _sqV) * dt;
    sq += _sqV * dt;
    if (reduzirMovimento) sq *= 0.3;

    // ── símbolo (! ? …)
    final s = amigoSimbolo(emocao);
    if (s != simbolo) {
      simboloA -= dt * 8;
      if (simboloA <= 0) {
        simbolo = s;
        simboloA = 0;
      }
    } else if (s.isNotEmpty) {
      simboloA = math.min(1, simboloA + dt * 5);
    }
  }

  /// Respiração lenta (-1..1), ciclo de 3,8 s.
  double get respiracao =>
      parado || reduzirMovimento ? 0 : math.sin(t * 2 * math.pi / 3.8);
}
