import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Esqueleto de lista (adendo 4 · item 9, 29/10/2026): em vez de um círculo a
/// rodar no meio do ecrã, desenham-se [linhas] cartões cinzentos a pulsar com
/// a forma do que vai chegar (foto + duas linhas de texto). Dá a sensação de
/// que o ecrã já está lá e evita o salto de layout quando a lista chega.
///
/// Sem pacotes: um só `AnimationController` a mexer a opacidade. Respeita
/// "reduzir animações" do sistema (fica parado).
class SkeletonLista extends StatefulWidget {
  const SkeletonLista({super.key, this.linhas = 5, this.comFoto = true});

  final int linhas;
  final bool comFoto;

  @override
  State<SkeletonLista> createState() => _SkeletonListaState();
}

class _SkeletonListaState extends State<SkeletonLista>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parado = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (parado) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A carregar',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final opacidade = 0.45 + 0.4 * _ctrl.value;
            return Opacity(
              key: const Key('skeleton_lista'),
              opacity: opacidade,
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.md, Spacing.lg, Spacing.lg),
                itemCount: widget.linhas,
                separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
                itemBuilder: (_, __) => _LinhaSkeleton(comFoto: widget.comFoto),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LinhaSkeleton extends StatelessWidget {
  const _LinhaSkeleton({required this.comFoto});

  final bool comFoto;

  @override
  Widget build(BuildContext context) {
    Widget barra(double largura, double altura) => Container(
          width: largura,
          height: altura,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          if (comFoto) ...[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
            const SizedBox(width: Spacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (_, c) => barra(c.maxWidth * 0.6, 14),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (_, c) => barra(c.maxWidth * 0.35, 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
