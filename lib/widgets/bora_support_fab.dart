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

import '../l10n/tr.dart';

enum FabPosition { bottomRight, bottomLeft, topRight, topLeft }

class BoraSupportFab extends StatelessWidget {
  const BoraSupportFab({
    super.key,
    this.orderId,
    this.position = FabPosition.bottomRight,
    this.heroTag,
  });

  final String? orderId;
  final FabPosition position;

  /// Etiqueta do herói. **Por omissão é única por instância** — ver o build.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // ETIQUETA ÚNICA POR INSTÂNCIA (2026-09-08).
    //
    // Isto tinha `heroTag = 'bora_support_fab'` fixo, e **26 ecrãs** usam este
    // botão. Bastava navegar de um para outro para haver dois heróis com a
    // mesma etiqueta na mesma subárvore, e o Flutter atira:
    //
    //   There are multiple heroes that share the same tag within a subtree.
    //   In this case, multiple heroes had the following tag: bora_support_fab
    //
    // Apanhado na corrida 34229774614, ao voltar do percurso do cliente. Em
    // release as asserções estão desligadas e a app não abaixo, mas a animação
    // do botão entre ecrãs fica partida à mesma — e em debug rebenta.
    //
    // `identityHashCode(context)` dá uma etiqueta estável para o mesmo
    // elemento e diferente entre ecrãs. Pôr `null` não servia: o
    // `FloatingActionButton` cai então num `_DefaultHeroTag` que é `const` e
    // portanto igual em todas as instâncias — o mesmo choque outra vez.
    final etiqueta = heroTag ?? 'bora_support_fab_${identityHashCode(context)}';
    return FloatingActionButton(
      heroTag: etiqueta,
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      tooltip: 'Suporte Bora'.tr,
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
