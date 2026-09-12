// Sessão 7-UI-BUG004 (2026-05-08) — bottom sheet apresentado quando a RPC
// `driver_cancel_order` devolve `support_required:true`. Backend FIX em
// 7-FIX (2026-05-07, migration 20260507223338) bloqueia cancelamento pós
// status `pickedUp`. UI redirecciona o estafeta para o suporte.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';

// TODO: mover para configuração centralizada (env / remote config) em sessão futura.
const String _supportPhone = '+351937501673';

class CancelBlockedPickupSheet extends StatelessWidget {
  const CancelBlockedPickupSheet({
    super.key,
    required this.orderId,
    required this.onContactSupport,
  });

  final String orderId;
  final VoidCallback onContactSupport;

  Future<void> _callSupport(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: _supportPhone);
    const mode = LaunchMode.externalApplication;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: mode);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir o telefone. '
              'Liga manualmente: +351 937 501 673',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir telefone: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Não consigo cancelar este pedido',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Após recolher, só o suporte pode cancelar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onContactSupport();
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Contactar suporte'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _callSupport(context),
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Ligar agora (emergência)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: const BorderSide(color: AppTheme.secondary, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
