import 'package:flutter/material.dart';

import '../../config/app_spacing.dart';

/// Rodapé de ação fixo — a ÚNICA forma aprovada de pôr CTA no fundo de um
/// ecrã (regra da missão botoes-navbar-eta, 2026-08-31).
///
/// Cicatriz real: no Samsung do Danilo (barra de navegação Android de 3
/// botões) o "Finalizar viagem" do motorista ficava colado/tapado pela navbar
/// — o texto nem se lia e o toque quase não entrava. Cada ecrã tratava o
/// fundo à sua maneira e metade esquecia o `viewPadding`.
///
/// O que este widget garante, sempre:
///  · padding inferior = 16 px ALÉM do `viewPadding.bottom` do sistema
///    (navbar de 3 botões, gestos, ou nada — o sistema diz, nós somamos);
///  · área de toque mínima de 56 px de altura por botão;
///  · largura total, com espaço entre botões quando há mais do que um
///    (empilhados; para lado-a-lado passa-se uma Row como filho único).
///
/// Usa `viewPadding` (não `padding`) de propósito: um `SafeArea` acima já
/// consome o `padding`, e este rodapé tem de somar o espaço do sistema
/// exatamente uma vez, esteja onde estiver.
class BoraBottomActionBar extends StatelessWidget {
  const BoraBottomActionBar({
    super.key,
    required this.children,
    this.color,
    this.topPadding = Spacing.sm,
  });

  /// Botões/CTAs, empilhados na vertical, todos esticados à largura total.
  final List<Widget> children;

  /// Fundo opcional (ex.: `AppColors.surface` quando o rodapé assenta num
  /// mapa). Null → transparente, herda o fundo de quem o contém.
  final Color? color;

  final double topPadding;

  /// Folga inferior para o que não é um rodapé fixo — folhas que sobem
  /// (`showModalBottomSheet`) e listas roláveis que acabam num botão
  /// (varredura de 08/10/2026: Android 15 desenha a barra de 3 botões POR
  /// CIMA da app, e o "Marcar como entregue" ficava meio escondido).
  ///
  /// [base] + o MAIOR entre o teclado (`viewInsets`) e a barra do sistema
  /// (`viewPadding`): com o teclado aberto a barra fica por baixo dele, por
  /// isso nunca se soma duas vezes. O `useSafeArea: true` de uma folha NÃO
  /// protege o fundo (só topo e lados) — usa-se isto.
  static double folgaInferior(BuildContext context,
      {double base = Spacing.lg}) {
    final mq = MediaQuery.of(context);
    final teclado = mq.viewInsets.bottom;
    final sistema = mq.viewPadding.bottom;
    return base + (teclado > sistema ? teclado : sistema);
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        topPadding,
        Spacing.lg,
        Spacing.lg + bottomSafe,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: Spacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}
