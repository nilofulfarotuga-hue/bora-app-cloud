import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// De onde sai a folha de partilha (`sharePositionOrigin` do share_plus).
///
/// app-15-11 (varredura 9166, n.º 4): no iPad, e no iPhone com iOS 26, a folha
/// de partilha sem esta origem fazia a app ir abaixo. Com [context] usa o sítio
/// do botão ou do ecrã; sem ele (serviços, ou depois de fechar uma folha) usa o
/// centro da janela, que serve sempre.
Rect origemDaPartilha([BuildContext? context]) {
  final caixa = context?.findRenderObject();
  if (caixa is RenderBox && caixa.hasSize && caixa.attached) {
    final origem = caixa.localToGlobal(Offset.zero) & caixa.size;
    if (!origem.isEmpty) return origem;
  }
  final vista = WidgetsBinding.instance.platformDispatcher.views.first;
  final tamanho = vista.physicalSize / vista.devicePixelRatio;
  return Rect.fromCenter(
      center: tamanho.center(Offset.zero), width: 1, height: 1);
}
