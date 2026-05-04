// Sessão 5A-2 B12 — BoraSupportFab
// Botão de suporte. Cor #E65100, Icons.help_outline.
// FabPosition: BR (default) | BL | TR | TL — para evitar conflito com FAB próprio.

import 'package:flutter/material.dart';

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
      backgroundColor: const Color(0xFFE65100),
      foregroundColor: Colors.white,
      tooltip: 'Suporte Bora',
      onPressed: () => _open(context),
      child: const Icon(Icons.help_outline),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BoraSupportSheet(orderId: orderId),
    );
  }
}
