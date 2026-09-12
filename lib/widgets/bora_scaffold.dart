// Sessão 5A-2 B11 — BoraScaffold wrapper minimal
// Adiciona FAB suporte overlay quando provider está em estado renderizável.
// Scaffolds existentes não são tocados; apenas screens que importam
// este wrapper recebem FAB. Scaffolds com FAB próprio podem omitir o
// wrapper e usar BoraSupportFab directamente em floatingActionButton.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/support_settings_provider.dart';
import 'bora_support_fab.dart';

class BoraScaffold extends StatelessWidget {
  const BoraScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.showSupportFab = true,
    this.supportFabPosition = FabPosition.bottomRight,
    this.supportFabOrderId,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool showSupportFab;
  final FabPosition supportFabPosition;
  final String? supportFabOrderId;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportSettingsProvider>();
    final renderFab = showSupportFab && provider.shouldShowFab;

    Widget content = body;
    if (renderFab) {
      content = Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            right: supportFabPosition == FabPosition.bottomRight ||
                    supportFabPosition == FabPosition.topRight
                ? 16
                : null,
            left: supportFabPosition == FabPosition.bottomLeft ||
                    supportFabPosition == FabPosition.topLeft
                ? 16
                : null,
            top: supportFabPosition == FabPosition.topRight ||
                    supportFabPosition == FabPosition.topLeft
                ? 16
                : null,
            bottom: supportFabPosition == FabPosition.bottomRight ||
                    supportFabPosition == FabPosition.bottomLeft
                ? 24
                : null,
            child: SafeArea(
              child: BoraSupportFab(
                orderId: supportFabOrderId,
                position: supportFabPosition,
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: content,
    );
  }
}
