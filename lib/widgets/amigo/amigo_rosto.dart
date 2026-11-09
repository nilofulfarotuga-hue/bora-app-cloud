// O AMIGO — o rosto vivo (missão m11-amigo-rosto, 09/11/2026).
//
// Ordem do Danilo (09/11, 05:11): "Vai ter que ser um rosto com expressão
// falando com a pessoa... O Dipsy tinha feito, eu acho que ele verde. Seria
// legal colocar o logo da Bora na camisa dele... tem que ter as expressões."
//
// Desenho nativo do Flutter (CustomPainter + Ticker), sem janela web: corre
// igual em Android, iPhone e na web. O desenho é o do protótipo do Dipsy
// (amigo.js), coordenada a coordenada — ver docs/amigo/ficha-personagem-*.
// Uma classe só, de tamanho variável: 40 px na home, 220+ no ecrã do Amigo.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'amigo_boca.dart';
import 'amigo_emocao.dart';
import 'amigo_motor.dart';

export 'amigo_emocao.dart';

/// Caixa do desenho (coordenadas do protótipo) por variante.
const Rect kAmigoCaixaCamisa = Rect.fromLTRB(0, -28, 300, 345);
const Rect kAmigoCaixaRosto = Rect.fromLTRB(10, -6, 290, 246);

Rect amigoCaixa(AmigoVariante v) =>
    v == AmigoVariante.rosto ? kAmigoCaixaRosto : kAmigoCaixaCamisa;

/// O logótipo da Bora para a camisa (assets/branding/bora_logo.png, sem o
/// alterar), lido uma vez por arranque.
class AmigoLogoBora {
  AmigoLogoBora._();
  static ui.Image? imagem;
  static Future<ui.Image?>? _aCarregar;

  static Future<ui.Image?> carregar() => _aCarregar ??= _ler();

  static Future<ui.Image?> _ler() async {
    try {
      final data = await rootBundle.load('assets/branding/bora_logo.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 160,
      );
      final quadro = await codec.getNextFrame();
      return imagem = quadro.image;
    } catch (e) {
      debugPrint('[AmigoRosto] logo: $e');
      return null;
    }
  }
}

/// Uma fonte da boca da fala, lida a cada imagem (null = calado).
typedef AmigoFonteBoca = AmigoBocaForma? Function();

class AmigoRosto extends StatefulWidget {
  const AmigoRosto({
    super.key,
    required this.tamanho,
    this.emocao = AmigoEmocao.neutro,
    this.variante = AmigoVariante.rosto,
    this.boca,
    this.parado = false,
    this.acordar = false,
    this.semente,
    this.rotulo,
  });

  /// Largura do desenho (a altura sai da proporção da variante).
  final double tamanho;
  final AmigoEmocao emocao;
  final AmigoVariante variante;

  /// A boca da fala neste instante (a voz do Amigo); null = calado.
  final AmigoFonteBoca? boca;

  /// Capturas/testes: expressão parada, sem relógio.
  final bool parado;

  /// Pequena animação de entrada (olhos fechados → abre com um salto).
  final bool acordar;
  final int? semente;

  /// Texto do leitor de ecrã (por defeito "Amigo, <expressão>").
  final String? rotulo;

  /// Altura do desenho para uma largura, por variante.
  static double alturaPara(double largura, AmigoVariante v) {
    final c = amigoCaixa(v);
    return largura * c.height / c.width;
  }

  @override
  State<AmigoRosto> createState() => _AmigoRostoState();
}

class _AmigoRostoState extends State<AmigoRosto>
    with SingleTickerProviderStateMixin {
  late final AmigoMotor _motor;
  late final Ticker _ticker;
  final _Repintar _repintar = _Repintar();
  Duration _ultimo = Duration.zero;

  @override
  void initState() {
    super.initState();
    _motor = AmigoMotor(semente: widget.semente, parado: widget.parado);
    if (widget.parado) {
      _motor.saltarPara(widget.emocao);
    } else {
      _motor.setEmocao(widget.emocao);
      if (widget.acordar) _motor.acordar();
    }
    _ticker = createTicker(_tique);
    if (!widget.parado) _ticker.start();
    if (widget.variante == AmigoVariante.rostoCamisa && AmigoLogoBora.imagem == null) {
      AmigoLogoBora.carregar().then((_) {
        if (mounted) _repintar.avisar();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AmigoRosto old) {
    super.didUpdateWidget(old);
    if (old.emocao != widget.emocao) {
      if (widget.parado) {
        _motor.saltarPara(widget.emocao);
        _repintar.avisar();
      } else {
        _motor.setEmocao(widget.emocao);
      }
    }
    if (old.parado != widget.parado) {
      _motor.parado = widget.parado;
      if (widget.parado) {
        _ticker.stop();
        _motor.saltarPara(widget.emocao);
        _repintar.avisar();
      } else if (!_ticker.isActive) {
        _ultimo = Duration.zero;
        _ticker.start();
      }
    }
    if (widget.variante == AmigoVariante.rostoCamisa && AmigoLogoBora.imagem == null) {
      AmigoLogoBora.carregar().then((_) {
        if (mounted) _repintar.avisar();
      });
    }
  }

  void _tique(Duration agora) {
    final dt = _ultimo == Duration.zero
        ? 1 / 60
        : (agora - _ultimo).inMicroseconds / 1e6;
    _ultimo = agora;
    final f = widget.boca?.call();
    _motor.fala = f;
    _motor.energia = f?.vol ?? 0;
    _motor.update(dt);
    _repintar.avisar();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repintar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motor.reduzirMovimento = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget.tamanho;
    final h = AmigoRosto.alturaPara(w, widget.variante);
    return Semantics(
      image: true,
      label: widget.rotulo ?? 'Amigo, ${amigoEmocaoRotulo(widget.emocao).toLowerCase()}',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(w, h),
          painter: AmigoPintor(
            motor: _motor,
            variante: widget.variante,
            repintar: _repintar,
          ),
        ),
      ),
    );
  }
}

class _Repintar extends ChangeNotifier {
  void avisar() => notifyListeners();
}

// ─── A pintura ─────────────────────────────────────────────────────────────

const Color _verde = Color(0xFF16A34A);
const Color _verdeClaro = Color(0xFF2BCB63);
const Color _verdeEscuro = Color(0xFF13843D);
const Color _laranja = Color(0xFFF97316);
const Color _corOlho = Color(0xFFF4FFF7);
const Color _pupila = Color(0xFF06160D);
const Color _ecraCentro = Color(0xFF123A24);
const Color _contornoEcra = Color(0xFF0E5C2B);
const Color _fundoBoca = Color(0xFF3B1105);

double _lim(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _rad(double graus) => graus * math.pi / 180;

/// Pinta o Amigo no instante atual do [motor]. Público para o painel e os
/// testes poderem pintar uma imagem parada.
class AmigoPintor extends CustomPainter {
  AmigoPintor({
    required this.motor,
    required this.variante,
    Listenable? repintar,
  }) : super(repaint: repintar);

  final AmigoMotor motor;
  final AmigoVariante variante;

  static final Paint _brilho = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
  static final Map<String, TextPainter> _simbolos = {};

  static final Paint _casca = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 36),
      const Offset(0, 232),
      const [_verdeClaro, _verde, _verdeEscuro],
      const [0, .55, 1],
    );
  static final Paint _cascaCorpo = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 236),
      const Offset(0, 322),
      const [_verdeClaro, _verde, _verdeEscuro],
      const [0, .55, 1],
    );
  static final Paint _ecra = Paint()
    ..shader = ui.Gradient.radial(
      const Offset(150, 121),
      124,
      const [_ecraCentro, Color(0xFF06160D)],
    );

  @override
  void paint(Canvas canvas, Size size) {
    final caixa = amigoCaixa(variante);
    final k = size.width / caixa.width;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-caixa.left, -caixa.top);
    _pintar(canvas);
    canvas.restore();
  }

  void _pintar(Canvas canvas) {
    final m = motor;
    final t = m.t;
    final resp = m.respiracao;
    final falar = m.fala != null;
    final en = m.energia;
    final mexe = !m.parado && !m.reduzirMovimento;
    final camisa = variante == AmigoVariante.rostoCamisa;

    final hx = m.v(AmigoP.headX) + (falar && mexe ? math.sin(t * 1.7) * 1.2 : 0);
    final hy = m.v(AmigoP.headY) + resp * 1.6 + (falar && mexe ? en * 3.2 : 0);
    final tilt = m.v(AmigoP.tilt) +
        (!mexe
            ? 0
            : falar
                ? math.sin(t * 2.3) * 1.6
                : math.sin(t * 0.7) * 0.6);
    final sy = 1 + m.sq;
    final sx = 1 - m.sq * 0.6;

    // braços: o direito acena quando fica alegre
    var aR = m.v(AmigoP.armR);
    var aL = m.v(AmigoP.armL);
    final desde = t - m.mudouEm;
    if (m.emocao == AmigoEmocao.alegre && desde < 1.8 && mexe) {
      aR += math.sin(desde * 14) * 18 * (1 - desde / 1.8);
    }
    aL += resp * 2;
    aR -= resp * 2;

    if (camisa) {
      // sombra
      canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(150, 333), width: 2 * (64 - hy * 0.4), height: 14),
        Paint()..color = const Color(0x21000000),
      );
      // corpo (respira)
      canvas.save();
      canvas.translate(150, 322);
      canvas.scale(1 - resp * 0.006, 1 + resp * 0.014);
      canvas.translate(-150, -322);
      _corpo(canvas);
      canvas.restore();
      _braco(canvas, 94, 102, aL);
    }

    // cabeça
    canvas.save();
    canvas.translate(hx, hy);
    canvas.translate(150, 228);
    canvas.rotate(_rad(tilt));
    canvas.scale(sx, sy);
    canvas.translate(-150, -228);
    _cabeca(canvas, tilt, en);
    canvas.restore();

    if (camisa) _braco(canvas, 190, 198, aR);

    _simbolo(canvas, t);
  }

  void _corpo(Canvas canvas) {
    final escuro = Paint()..color = _verdeEscuro;
    canvas.drawRRect(
        RRect.fromLTRBR(131, 224, 169, 244, const Radius.circular(6)), escuro);
    canvas.drawOval(Rect.fromCenter(center: const Offset(127, 322), width: 34, height: 16), escuro);
    canvas.drawOval(Rect.fromCenter(center: const Offset(173, 322), width: 34, height: 16), escuro);
    canvas.drawRRect(
        RRect.fromLTRBR(96, 236, 204, 322, const Radius.circular(42)), _cascaCorpo);
    // peito branco com o logótipo da Bora (o protótipo tinha um cadeado)
    canvas.drawOval(Rect.fromCenter(center: const Offset(150, 286), width: 70, height: 54),
        Paint()..color = Colors.white);
    final logo = AmigoLogoBora.imagem;
    if (logo != null) {
      const larg = 54.0;
      final alt = larg * logo.height / logo.width;
      paintImage(
        canvas: canvas,
        rect: Rect.fromCenter(center: const Offset(150, 286), width: larg, height: alt),
        image: logo,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
  }

  void _braco(Canvas canvas, double x, double cx, double graus) {
    canvas.save();
    canvas.translate(cx, 258);
    canvas.rotate(_rad(graus));
    canvas.translate(-cx, -258);
    canvas.drawRRect(RRect.fromLTRBR(x, 254, x + 16, 294, const Radius.circular(8)),
        Paint()..color = _verde);
    canvas.drawCircle(Offset(cx, 297), 10.5, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, 297),
        10.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFE5E7EB));
    canvas.restore();
  }

  void _cabeca(Canvas canvas, double tilt, double en) {
    final m = motor;
    final t = m.t;
    final mexe = !m.parado && !m.reduzirMovimento;

    // antena (brilha a pensar e a falar)
    final glow = _lim(
        m.v(AmigoP.ant) *
                (0.55 +
                    0.45 *
                        math.sin(t * (m.emocao == AmigoEmocao.pensativo ? 6 : 3))) +
            en * 0.6,
        0,
        1);
    canvas.save();
    canvas.translate(150, 40);
    canvas.rotate(_rad(mexe ? math.sin(t * 1.3) * 3 - tilt * 0.3 : -tilt * 0.3));
    canvas.translate(-150, -40);
    canvas.drawLine(
        const Offset(150, 40),
        const Offset(150, 16),
        Paint()
          ..color = _verdeEscuro
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(
        const Offset(150, 12),
        12,
        Paint()
          ..color = _laranja.withValues(alpha: 0.15 + glow * 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(const Offset(150, 12), 8, Paint()..color = _laranja);
    canvas.restore();

    // orelhas, casca e ecrã
    final laranja = Paint()..color = _laranja;
    canvas.drawRRect(RRect.fromLTRBR(24, 110, 46, 162, const Radius.circular(11)), laranja);
    canvas.drawRRect(RRect.fromLTRBR(254, 110, 276, 162, const Radius.circular(11)), laranja);
    canvas.drawRRect(RRect.fromLTRBR(38, 36, 262, 232, const Radius.circular(86)), _casca);
    final ecra = RRect.fromLTRBR(56, 54, 244, 214, const Radius.circular(70));
    canvas.drawRRect(ecra, _ecra);
    canvas.drawRRect(
        ecra,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _contornoEcra);

    canvas.save();
    canvas.clipRRect(ecra);
    canvas.drawPath(
        Path()
          ..moveTo(78, 96)
          ..quadraticBezierTo(90, 64, 132, 60),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x1AFFFFFF));
    _rosto(canvas);
    canvas.restore();
  }

  Path _olho(double cx, double cy, double s, double w, double hto, double hti,
      double hbo, double hbi) {
    final xi = cx + s * w, xo = cx - s * w;
    const k = 1.33;
    return Path()
      ..moveTo(xo, cy)
      ..cubicTo(xo, cy - hto * k, xi, cy - hti * k, xi, cy)
      ..cubicTo(xi, cy + hbi * k, xo, cy + hbo * k, xo, cy)
      ..close();
  }

  void _rosto(Canvas canvas) {
    final m = motor;
    final lookX = _lim(m.v(AmigoP.lookX), -1, 1);
    final lookY = _lim(m.v(AmigoP.lookY), -1, 1);
    canvas.save();
    canvas.translate(lookX * 6, lookY * 4); // a cara segue o olhar (paralaxe)

    // bochechas
    final corado = Paint()..color = _laranja.withValues(alpha: _lim(m.v(AmigoP.blush) * 0.55, 0, 1));
    canvas.drawOval(Rect.fromCenter(center: const Offset(84, 166), width: 30, height: 16), corado);
    canvas.drawOval(Rect.fromCenter(center: const Offset(216, 166), width: 30, height: 16), corado);

    final preenche = Paint()..color = _corOlho;
    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round
      ..color = _corOlho;
    final sobr = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..color = _corOlho;
    final brilhoTraco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _corOlho.withValues(alpha: 0.75)
      ..maskFilter = _brilho.maskFilter;
    final brilhoFill = Paint()
      ..color = _corOlho.withValues(alpha: 0.75)
      ..maskFilter = _brilho.maskFilter;

    final sl = m.v(AmigoP.lidSlant);
    final pf = m.pf;
    for (final (lado, cx, s, op) in [
      ('L', 112.0, 1.0, m.v(AmigoP.openL)),
      ('R', 188.0, -1.0, m.v(AmigoP.openR)),
    ]) {
      final w = 23 * m.v(AmigoP.eyeW);
      final h = 30 * op * pf;
      final hto = h * (1 + 0.5 * math.min(sl, 0) + 0.15 * math.max(sl, 0));
      final hti = h * (1 - 0.5 * math.max(sl, 0) - 0.15 * math.min(sl, 0));
      final hb = 30 * op * m.v(AmigoP.bottom) * (0.35 + 0.65 * pf);
      final olho = _olho(cx, 128, s, w, hto, hti, hb, hb);
      canvas.drawPath(olho, brilhoFill);
      canvas.drawPath(olho, preenche);
      canvas.drawPath(olho, traco);

      // pupila presa dentro do olho
      final px = cx + lookX * 9, py = 130 + lookY * 9;
      canvas.save();
      canvas.clipPath(olho);
      canvas.drawCircle(Offset(px, py), 11.5 * m.v(AmigoP.pupil), Paint()..color = _pupila);
      canvas.drawCircle(Offset(px - 4, py - 5), 3.6, Paint()..color = Colors.white);
      canvas.restore();

      // sobrancelha
      final by = (lado == 'L' ? m.v(AmigoP.browL) : m.v(AmigoP.browR)) + 80 + (1 - op) * 6;
      final bs = lado == 'L' ? m.v(AmigoP.browSlL) : m.v(AmigoP.browSlR);
      final xi = cx + s * 15, xo = cx - s * 16;
      final yi = by + bs, yo = by - bs * 0.35;
      final sob = Path()
        ..moveTo(xo, yo)
        ..quadraticBezierTo(cx, math.min(yi, yo) - 6, xi, yi);
      canvas.drawPath(sob, brilhoTraco);
      canvas.drawPath(sob, sobr);
    }

    // boca
    final mw = 24 * m.v(AmigoP.mw);
    final mo = math.max(0.0, m.v(AmigoP.mo));
    final sm = m.v(AmigoP.sm);
    final cx = 150 + m.v(AmigoP.mx);
    const cy = 176.0;
    final mAs = m.v(AmigoP.mAsym);
    final yl = cy - sm * 0.55 - mAs * 0.5, yr = cy - sm * 0.55 + mAs * 0.5;
    final ty = cy + sm * 0.3 - mo * 0.38;
    final byy = ty + mo * 1.38 + math.max(0.0, sm) * 0.5 + 0.4;
    final kk = mw * (0.55 + 0.45 * _lim(m.v(AmigoP.round), 0, 1));
    final boca = Path()
      ..moveTo(cx - mw, yl)
      ..cubicTo(cx - kk, ty, cx + kk, ty, cx + mw, yr)
      ..cubicTo(cx + kk, byy, cx - kk, byy, cx - mw, yl)
      ..close();
    canvas.drawPath(boca, Paint()..color = _fundoBoca);
    canvas.save();
    canvas.clipPath(boca);
    final dh = _lim((byy - ty) * 0.22, 0, 6);
    canvas.drawRRect(
        RRect.fromLTRBR(cx - mw * 0.55, ty - 2, cx + mw * 0.55, ty + dh, const Radius.circular(2)),
        Paint()..color = const Color(0xEBFFFFFF));
    final fundoY = (ty + byy) / 2 + (byy - ty) * 0.38;
    final ry = math.max(0.0, (byy - ty) * 0.32);
    if (ry > 0.2) {
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, fundoY + 3), width: mw * 1.1, height: ry * 2),
          Paint()..color = _laranja);
    }
    canvas.restore();
    final linha = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = _corOlho;
    canvas.drawPath(
        boca,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeJoin = StrokeJoin.round
          ..color = _corOlho.withValues(alpha: 0.7)
          ..maskFilter = _brilho.maskFilter);
    canvas.drawPath(boca, linha);
    canvas.restore();
  }

  void _simbolo(Canvas canvas, double t) {
    final m = motor;
    final sa = m.simboloA;
    final st = m.simbolo;
    if (st.isEmpty || sa <= 0.01) return;
    final tp = _simbolos.putIfAbsent(
      st,
      () => TextPainter(
        text: TextSpan(
          text: st,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _laranja,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    final mexe = !m.parado && !m.reduzirMovimento;
    final pop = sa < 1
        ? 0.6 + sa * 0.5 + math.sin(sa * math.pi) * 0.25
        : 1 + (mexe ? math.sin(t * 3) * 0.05 : 0.0);
    canvas.save();
    canvas.translate(262, 40);
    canvas.scale(pop);
    canvas.rotate(_rad(mexe ? math.sin(t * 2) * 8 : 0));
    canvas.translate(-262, -40);
    canvas.saveLayer(
        null, Paint()..color = Color.fromRGBO(255, 255, 255, _lim(sa, 0, 1)));
    tp.paint(canvas, Offset(262 - tp.width / 2, 52 - tp.height * 0.8));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AmigoPintor old) =>
      old.motor != motor || old.variante != variante;
}
