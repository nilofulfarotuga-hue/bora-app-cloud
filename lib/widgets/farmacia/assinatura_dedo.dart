// Assinatura com o dedo (missão farmacias-2026-11-11).
// Desenha traços com o dedo/rato e exporta um PNG com fundo branco.
// Funciona igual no Android, no iPhone e na web (só usa CustomPainter e dart:ui).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

class AssinaturaController extends ChangeNotifier {
  final List<List<Offset>> _tracos = [];
  Size _tamanho = Size.zero;

  List<List<Offset>> get tracos => _tracos;
  bool get vazia => _tracos.every((t) => t.length < 2);

  void _comecar(Offset p) {
    _tracos.add([p]);
    notifyListeners();
  }

  void _continuar(Offset p) {
    if (_tracos.isEmpty) return;
    _tracos.last.add(p);
    notifyListeners();
  }

  void limpar() {
    _tracos.clear();
    notifyListeners();
  }

  /// PNG com fundo branco e traço escuro. Devolve null se não houver assinatura.
  Future<Uint8List?> exportarPng({double escala = 2}) async {
    if (vazia || _tamanho.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(escala);
    canvas.drawRect(Offset.zero & _tamanho, Paint()..color = Colors.white);
    _AssinaturaPainter.pintar(canvas, _tracos);
    final imagem = await recorder.endRecording().toImage(
          (_tamanho.width * escala).ceil(),
          (_tamanho.height * escala).ceil(),
        );
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }
}

class AssinaturaDedo extends StatelessWidget {
  const AssinaturaDedo({super.key, required this.controller, this.altura = 160});

  final AssinaturaController controller;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: altura,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.dividerStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (context, c) {
            controller._tamanho = Size(c.maxWidth, c.maxHeight);
            return GestureDetector(
              // Não deixar a página rolar enquanto se assina.
              onVerticalDragStart: (d) => controller._comecar(d.localPosition),
              onVerticalDragUpdate: (d) => controller._continuar(d.localPosition),
              onHorizontalDragStart: (d) => controller._comecar(d.localPosition),
              onHorizontalDragUpdate: (d) => controller._continuar(d.localPosition),
              onTapDown: (d) => controller._comecar(d.localPosition),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => Stack(
                  children: [
                    if (controller.vazia)
                      const Center(
                        child: Text(
                          'Assine aqui com o dedo',
                          style: TextStyle(color: AppColors.textSubtle, fontSize: 15),
                        ),
                      ),
                    Positioned.fill(
                      child: CustomPaint(painter: _AssinaturaPainter(controller.tracos)),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: controller.limpar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Limpar'),
          ),
        ),
      ],
    );
  }
}

class _AssinaturaPainter extends CustomPainter {
  _AssinaturaPainter(this.tracos);
  final List<List<Offset>> tracos;

  static void pintar(Canvas canvas, List<List<Offset>> tracos) {
    final p = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final t in tracos) {
      if (t.length < 2) continue;
      final path = Path()..moveTo(t.first.dx, t.first.dy);
      for (final o in t.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => pintar(canvas, tracos);

  @override
  bool shouldRepaint(covariant _AssinaturaPainter old) => true;
}
