import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// AppBar Bora — header verde gradiente com logo "B" + mota + título.
///
/// Uso em ecrãs principais (home, listagens, dashboards). Para ecrãs de
/// detalhe ou fluxo modal, preferir `AppBar` standard do `ThemeData`.
///
/// Exemplo:
/// ```dart
/// Scaffold(
///   appBar: BoraAppBar(
///     title: 'Olá, Cliente!',
///     subtitle: 'O que precisas hoje?',
///     actions: [IconButton(icon: Icon(Icons.search), onPressed: ...)],
///   ),
///   body: ...,
/// );
/// ```
/// NOTA: usar dentro de `body:` (e.g. `Column([BoraAppBar(...), Expanded(...)])`),
/// não no slot `appBar:` do Scaffold — este widget já trata da safe-area
/// superior internamente para permitir header edge-to-edge com status bar.
class BoraAppBar extends StatelessWidget {
  const BoraAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.showLogo = true,
    this.actions,
    this.leading,
    this.height = 140,
  });

  /// Título principal branco. Se null, mostra apenas o logo (estilo home).
  final String? title;

  /// Subtítulo opcional abaixo do título (e.g. "O que precisas hoje?").
  final String? subtitle;

  /// Se true (default) renderiza o logo "B + mota" à esquerda.
  final bool showLogo;

  /// Botões de acção à direita (search, notifications, etc).
  final List<Widget>? actions;

  /// Widget leading custom. Se null e [showLogo] true, usa logo Bora.
  final Widget? leading;

  /// Altura do conteúdo (safe-area top é adicionada automaticamente).
  final double height;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Container(
      height: height + safeTop,
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      padding: EdgeInsets.only(
        top: safeTop + Spacing.md,
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: Spacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null)
            leading!
          else if (showLogo)
            const _BoraLogo(),
          if (showLogo || leading != null) const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// Logo Bora "B + mota" em fallback text (até ter asset).
class _BoraLogo extends StatelessWidget {
  const _BoraLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      alignment: Alignment.center,
      child: const Text(
        'B',
        style: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}
