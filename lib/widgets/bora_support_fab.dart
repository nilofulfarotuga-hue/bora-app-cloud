// Sessão 5A-2 B12 — BoraSupportFab
// Sessão 6 B2 — onTap mudou: chat IA directo se kill switch ON.
// Botão de suporte. Cor #E65100, Icons.help_outline.
// FabPosition: BR (default) | BL | TR | TL — para evitar conflito com FAB próprio.
// Comportamento: provider.shouldShowAiCard==true → Navigator.push(SupportChatScreen);
// senão (kill OFF / state=loading|error) → fallback BoraSupportSheet (menu antigo).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../providers/support_settings_provider.dart';
import '../screens/support_chat_screen.dart';
import 'bora_support_sheet.dart';

enum FabPosition { bottomRight, bottomLeft, topRight, topLeft }

class BoraSupportFab extends StatelessWidget {
  const BoraSupportFab({
    super.key,
    this.orderId,
    this.position = FabPosition.bottomRight,
    this.heroTag = 'bora_support_fab',
  });

  final String? orderId;
  final FabPosition position;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: heroTag,
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      tooltip: 'Suporte Bora',
      onPressed: () => _open(context),
      child: const Icon(Icons.help_outline),
    );
  }

  void _open(BuildContext context) {
    final provider = context.read<SupportSettingsProvider>();
    if (provider.shouldShowAiCard) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportChatScreen(orderId: orderId),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => BoraSupportSheet(orderId: orderId),
      );
    }
  }
}
