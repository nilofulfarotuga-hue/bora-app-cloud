import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// AppBar padronizado Bora para ecrãs de fluxo cliente.
///
/// - Fundo: gradiente verde Bora (`AppColors.headerGradient`).
/// - Seta voltar e título: cor laranja (`AppColors.accent`).
/// - Usar no slot `appBar:` do Scaffold.
///
/// Exemplo:
/// ```dart
/// Scaffold(
///   appBar: const BoraScreenAppBar(title: 'Enviar Encomenda'),
///   body: ...,
/// );
/// ```
class BoraScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BoraScreenAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.accent),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.headerGradient),
      ),
      actions: actions,
    );
  }
}
