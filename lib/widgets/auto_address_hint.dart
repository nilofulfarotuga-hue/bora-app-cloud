import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';

/// Estado discreto de "a obter a sua localização", para os ecrãs que preenchem
/// a morada sozinhos.
///
/// De propósito é só uma linha de texto pequena: nunca um ecrã bloqueado, nunca
/// um diálogo. Enquanto isto está visível o campo de morada continua
/// totalmente escrevível — se o cliente começar a escrever, ganha ele.
class AutoAddressHint extends StatelessWidget {
  const AutoAddressHint({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: Spacing.xs, left: Spacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: Spacing.sm),
          Text(
            'A obter a sua localização...',
            style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
          ),
        ],
      ),
    );
  }
}
