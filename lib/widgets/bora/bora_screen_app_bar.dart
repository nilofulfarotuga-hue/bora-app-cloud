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
      // B4 (2026-06-11): era Colors.transparent + gradiente só no
      // flexibleSpace — quando o flexibleSpace não pinta (DecoratedBox sem
      // child pode colapsar consoante as constraints), o título branco fica
      // sobre o fundo claro do Scaffold (#F0F2EF) = header ilegível
      // (Marcações / Agenda / Sugestões do Robot no build 278). Fundo sólido
      // primary é visualmente IGUAL ao headerGradient ([primary, primary])
      // e garante header verde mesmo que o flexibleSpace falhe.
      backgroundColor: AppColors.primary,
      // M3: impede o tint de scrolled-under de alterar a cor do header.
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
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
