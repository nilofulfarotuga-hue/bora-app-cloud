// O AMIGO — as expressões (missão m11-amigo-rosto, 09/11/2026).
//
// Os números vêm do protótipo do Dipsy (Desktop\bora-amigo-teste\amigo.js,
// 08/11/2026): cada expressão é um conjunto de alvos para os parâmetros da
// cara (abertura dos olhos, sobrancelhas, boca, cabeça, braços, antena).
// O motor (amigo_motor.dart) aproxima-se suavemente destes alvos.
// Ficha completa: docs/amigo/ficha-personagem-2026-11-09.md.

/// As caras do Amigo. As 6 do pedido do Danilo (alegre, triste, surpreso,
/// pensativo, confuso, a falar) mais o repouso (neutro) e "a ouvir".
enum AmigoEmocao {
  neutro,
  alegre,
  triste,
  surpreso,
  pensativo,
  confuso,
  aFalar,
  aOuvir,
}

/// As duas variantes que o painel escolhe (`amigo_rosto_variante`).
enum AmigoVariante {
  /// Só a cara (cabeça com antena e orelhas).
  rosto,

  /// Cara + corpo com camisa verde e o logótipo da Bora ao peito.
  rostoCamisa,
}

/// `amigo_rosto_variante` do painel → variante (por defeito, com camisa).
AmigoVariante amigoVarianteDe(Object? v) {
  final s = (v ?? '').toString().replaceAll('"', '').trim().toLowerCase();
  return s == 'rosto' ? AmigoVariante.rosto : AmigoVariante.rostoCamisa;
}

/// O nome que vai e vem do servidor (`emocao` do client-assistant).
String amigoEmocaoNome(AmigoEmocao e) => switch (e) {
      AmigoEmocao.neutro => 'neutro',
      AmigoEmocao.alegre => 'alegre',
      AmigoEmocao.triste => 'triste',
      AmigoEmocao.surpreso => 'surpreso',
      AmigoEmocao.pensativo => 'pensativo',
      AmigoEmocao.confuso => 'confuso',
      AmigoEmocao.aFalar => 'a_falar',
      AmigoEmocao.aOuvir => 'a_ouvir',
    };

/// `emocao` do servidor → cara (null = o servidor não disse / valor estranho).
AmigoEmocao? amigoEmocaoDe(Object? v) {
  final s = (v ?? '').toString().trim().toLowerCase().replaceAll(' ', '_');
  for (final e in AmigoEmocao.values) {
    if (amigoEmocaoNome(e) == s) return e;
  }
  if (s == 'falar' || s == 'a-falar') return AmigoEmocao.aFalar;
  if (s == 'feliz') return AmigoEmocao.alegre;
  return null;
}

/// Os parâmetros da cara, pela ordem da lista de valores do motor.
enum AmigoP {
  openL,
  openR,
  bottom,
  lidSlant,
  eyeW,
  pupil,
  lookX,
  lookY,
  browL,
  browR,
  browSlL,
  browSlR,
  mw,
  mo,
  sm,
  mx,
  mAsym,
  round,
  tilt,
  headX,
  headY,
  blush,
  armL,
  armR,
  ant,
}

const Map<AmigoP, double> _base = {
  AmigoP.openL: 1,
  AmigoP.openR: 1,
  AmigoP.bottom: 1,
  AmigoP.lidSlant: 0,
  AmigoP.eyeW: 1,
  AmigoP.pupil: 1,
  AmigoP.lookX: 0,
  AmigoP.lookY: 0,
  AmigoP.browL: 0,
  AmigoP.browR: 0,
  AmigoP.browSlL: 0,
  AmigoP.browSlR: 0,
  AmigoP.mw: 1,
  AmigoP.mo: 0,
  AmigoP.sm: 5,
  AmigoP.mx: 0,
  AmigoP.mAsym: 0,
  AmigoP.round: 0,
  AmigoP.tilt: 0,
  AmigoP.headX: 0,
  AmigoP.headY: 0,
  AmigoP.blush: 0.15,
  AmigoP.armL: 16,
  AmigoP.armR: -16,
  AmigoP.ant: 0.25,
};

const Map<AmigoEmocao, Map<AmigoP, double>> _alvos = {
  AmigoEmocao.neutro: {},
  AmigoEmocao.alegre: {
    AmigoP.openL: .92, AmigoP.openR: .92, AmigoP.bottom: -.42, //
    AmigoP.browL: -7, AmigoP.browR: -7, AmigoP.sm: 15, AmigoP.mo: 9,
    AmigoP.mw: 1.18, AmigoP.blush: .8, AmigoP.armR: -150, AmigoP.armL: 30,
    AmigoP.headY: -5, AmigoP.ant: 1,
  },
  AmigoEmocao.triste: {
    AmigoP.openL: .72, AmigoP.openR: .72, AmigoP.lidSlant: -.6, //
    AmigoP.bottom: .85, AmigoP.browL: -2, AmigoP.browR: -2,
    AmigoP.browSlL: -10, AmigoP.browSlR: -10, AmigoP.sm: -12, AmigoP.mw: .78,
    AmigoP.lookY: .6, AmigoP.tilt: -7, AmigoP.headY: 7, AmigoP.blush: 0,
    AmigoP.armL: 6, AmigoP.armR: -6, AmigoP.pupil: 1.18, AmigoP.ant: 0,
  },
  AmigoEmocao.surpreso: {
    AmigoP.openL: 1.32, AmigoP.openR: 1.32, AmigoP.eyeW: 1.1, //
    AmigoP.pupil: .72, AmigoP.browL: -17, AmigoP.browR: -17, AmigoP.mo: 20,
    AmigoP.mw: .56, AmigoP.round: 1, AmigoP.sm: 0, AmigoP.headY: -9,
    AmigoP.armL: 70, AmigoP.armR: -70, AmigoP.ant: 1,
  },
  AmigoEmocao.pensativo: {
    AmigoP.openL: .82, AmigoP.openR: .6, AmigoP.lookX: .75, //
    AmigoP.lookY: -.8, AmigoP.browL: -2, AmigoP.browR: -12,
    AmigoP.browSlR: 4, AmigoP.sm: 2, AmigoP.mw: .55, AmigoP.mx: 13,
    AmigoP.mAsym: -5, AmigoP.tilt: 7, AmigoP.armR: 128, AmigoP.ant: .8,
  },
  AmigoEmocao.confuso: {
    AmigoP.openL: 1.08, AmigoP.openR: .68, AmigoP.browL: -13, //
    AmigoP.browR: 5, AmigoP.browSlL: -4, AmigoP.browSlR: 7, AmigoP.sm: -2,
    AmigoP.mw: .72, AmigoP.mAsym: 8, AmigoP.mx: -6, AmigoP.tilt: -10,
    AmigoP.lookX: -.35, AmigoP.ant: .5,
  },
  AmigoEmocao.aFalar: {
    AmigoP.sm: 7, AmigoP.browL: -3, AmigoP.browR: -3, AmigoP.blush: .3, //
    AmigoP.ant: .7,
  },
  AmigoEmocao.aOuvir: {
    AmigoP.openL: 1.08, AmigoP.openR: 1.08, AmigoP.browL: -5, //
    AmigoP.browR: -5, AmigoP.sm: 6, AmigoP.lookY: .15, AmigoP.tilt: 4,
    AmigoP.ant: 1, AmigoP.blush: .25,
  },
};

/// Os alvos de uma expressão, como lista indexada por [AmigoP.index].
List<double> amigoAlvos(AmigoEmocao e) {
  final o = _alvos[e] ?? const {};
  return [for (final p in AmigoP.values) o[p] ?? _base[p]!];
}

/// O símbolo que aparece por cima da cabeça ("!", "?", "…") ou vazio.
String amigoSimbolo(AmigoEmocao e) => switch (e) {
      AmigoEmocao.surpreso => '!',
      AmigoEmocao.confuso => '?',
      AmigoEmocao.pensativo => '…',
      _ => '',
    };

/// Rótulo em português para o leitor de ecrã e para o painel.
String amigoEmocaoRotulo(AmigoEmocao e) => switch (e) {
      AmigoEmocao.neutro => 'Normal',
      AmigoEmocao.alegre => 'Alegre',
      AmigoEmocao.triste => 'Triste',
      AmigoEmocao.surpreso => 'Surpreso',
      AmigoEmocao.pensativo => 'Pensativo',
      AmigoEmocao.confuso => 'Confuso',
      AmigoEmocao.aFalar => 'A falar',
      AmigoEmocao.aOuvir => 'A ouvir',
    };
