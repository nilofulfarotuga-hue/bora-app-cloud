// BORA ASSISTENTE (07/10/2026) — botão flutuante do assistente de compras.
//
// `BoraClientFabs` é o par que os ecrãs principais do cliente usam como
// `floatingActionButton`: assistente (verde, em cima) + suporte (laranja,
// em baixo — o `BoraSupportFab` de sempre, intocado). Com
// `platform_settings.assistant_enabled = false` só fica o suporte, para o
// desligar não deixar um botão morto.

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../screens/client/assistant/assistant_chat_screen.dart';
import '../services/assistant_service.dart';
import 'bora_support_fab.dart';

class BoraAssistantFab extends StatelessWidget {
  const BoraAssistantFab({super.key, this.heroTag});

  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // Etiqueta única por instância (mesma razão do BoraSupportFab).
    final etiqueta =
        heroTag ?? 'bora_assistant_fab_${identityHashCode(context)}';
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantFlags.enabled,
      builder: (context, ligado, _) {
        if (!ligado) return const SizedBox.shrink();
        return FloatingActionButton(
          heroTag: etiqueta,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          tooltip: 'Bora Assistente'.tr,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AssistantChatScreen(),
            ),
          ),
          child: const Icon(Icons.auto_awesome),
        );
      },
    );
  }
}

/// Assistente em cima, suporte em baixo.
class BoraClientFabs extends StatelessWidget {
  const BoraClientFabs({super.key, this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    // Lê o interruptor uma vez por sessão (só com sessão iniciada).
    AssistantFlags.carregar();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: AssistantFlags.enabled,
          builder: (_, ligado, __) => ligado
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: BoraAssistantFab(),
                )
              : const SizedBox.shrink(),
        ),
        BoraSupportFab(orderId: orderId),
      ],
    );
  }
}
