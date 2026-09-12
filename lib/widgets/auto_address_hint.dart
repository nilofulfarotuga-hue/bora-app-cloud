import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';

import '../l10n/tr.dart';

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
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs, left: Spacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'A obter a sua localização...'.tr,
            style: const TextStyle(fontSize: 13, color: AppColors.textSubtle),
          ),
        ],
      ),
    );
  }
}
