import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// AppBar padronizado Bora para ecrãs internos (back + título + actions).
///
/// - Fundo: gradiente verde Bora (`AppColors.headerGradient`).
/// - Seta voltar, título e ícones de acção: **brancos** (regra de ouro do
///   laranja — só 1 elemento laranja por ecrã, nunca no header).
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
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.headerGradient),
      ),
      actions: actions,
    );
  }
}
