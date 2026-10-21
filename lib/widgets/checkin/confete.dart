// lib/widgets/checkin/confete.dart
//
// Confete curto (1,8 s) por cima do cartão do check-in quando nasce um prémio
// de marco (Bloco D, 21/10/2026). Sem pacotes novos: um CustomPainter com
// papelinhos a cair, cores da marca. Não recebe toques (IgnorePointer).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

class Confete extends StatefulWidget {
  const Confete({super.key, this.duracao = const Duration(milliseconds: 1800), this.onFim});

  final Duration duracao;
  final VoidCallback? onFim;

  @override
  State<Confete> createState() => _ConfeteState();
}

class _ConfeteState extends State<Confete> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Papel> _papeis;

  @override
  void initState() {
    super.initState();
    final r = math.Random(7);
    const cores = [
      AppColors.primary,
      Color(0xFF22C55E),
      Color(0xFFFACC15),
      Color(0xFF60A5FA),
      Color(0xFFF472B6),
    ];
    _papeis = List.generate(
      38,
      (i) => _Papel(
        x: r.nextDouble(),
        atraso: r.nextDouble() * 0.35,
        velocidade: 0.7 + r.nextDouble() * 0.6,
        deriva: (r.nextDouble() - 0.5) * 0.25,
        rotacao: r.nextDouble() * math.pi,
        cor: cores[i % cores.length],
        largura: 5 + r.nextDouble() * 4,
      ),
    );
    _c = AnimationController(vsync: this, duration: widget.duracao)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onFim?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          key: const Key('checkin_confete'),
          painter: _ConfetePainter(_papeis, _c.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Papel {
  const _Papel({
    required this.x,
    required this.atraso,
    required this.velocidade,
    required this.deriva,
    required this.rotacao,
    required this.cor,
    required this.largura,
  });

  final double x;
  final double atraso;
  final double velocidade;
  final double deriva;
  final double rotacao;
  final Color cor;
  final double largura;
}

class _ConfetePainter extends CustomPainter {
  _ConfetePainter(this.papeis, this.t);

  final List<_Papel> papeis;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint();
    for (final p in papeis) {
      final local = ((t - p.atraso) / (1 - p.atraso)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -12 + (size.height + 24) * local * p.velocidade;
      final x = size.width * (p.x + p.deriva * local);
      final opacidade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      paint.color = p.cor.withValues(alpha: opacidade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotacao + local * 6);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.largura, height: p.largura * 0.55), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfetePainter old) => old.t != t;
}
