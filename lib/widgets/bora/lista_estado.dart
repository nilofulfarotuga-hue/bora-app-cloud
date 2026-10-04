import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';

/// Estados de uma lista do cliente (04/10/2026): enquanto carrega e quando
/// falha não se mostra "vazio" — mostra-se o que está a acontecer, com
/// "Tentar outra vez" (padrão Glovo/Uber Eats).
class ListaACarregar extends StatelessWidget {
  const ListaACarregar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class ListaComErro extends StatelessWidget {
  const ListaComErro({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// Texto simples em PT-PT. Por omissão, a frase genérica.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56,
                color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message ?? 'Não foi possível carregar. Verifica a ligação.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('Tentar outra vez'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
