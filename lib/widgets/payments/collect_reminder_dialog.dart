import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import 'collect_badge.dart';

/// Lembrete GRANDE de cobrança, mostrado no momento em que o trabalho fecha.
///
/// O [CollectBadge] vive no painel durante o serviço e é discreto de propósito.
/// Este é o oposto: aparece uma vez, tapa o ecrã e exige um toque. Existe porque
/// o momento perigoso não é o meio da corrida — é o fim, quando o passageiro já
/// abriu a porta e o motorista já está a pensar na próxima. Esquecer de cobrar
/// aqui é dinheiro que a Bora nunca mais vê.
///
/// Não decide nada: o [state] e o [amountCents] vêm de quem chama (no TVDE, de
/// `TvdeFareView` — a mesma fonte do badge e do ecrã do cliente).
Future<void> showCollectReminderDialog(
  BuildContext context, {
  required CollectState state,
  int amountCents = 0,
  int earnedCents = 0,
}) {
  final collect = state == CollectState.collectCash;
  final color = collect ? Colors.orange.shade900 : AppColors.primary;
  final eur = '€${(amountCents / 100).toStringAsFixed(2)}';
  final ganhoEur = '€${(earnedCents / 100).toStringAsFixed(2)}';

  final String title;
  final String subtitle;
  final IconData icon;
  if (collect) {
    icon = Icons.payments;
    title = 'COBRAR EM DINHEIRO';
    subtitle = 'Recebe este valor em mão antes de o passageiro sair.';
  } else if (state == CollectState.paidOnline) {
    icon = Icons.check_circle;
    title = 'JÁ PAGO NA APP';
    subtitle = 'Não cobres nada ao passageiro.';
  } else {
    icon = Icons.card_membership;
    title = 'COBERTO PELO PLANO';
    subtitle = 'Não cobres nada ao passageiro.';
  }

  return showDialog<void>(
    context: context,
    // Impossível saltar sem ver: sem toque fora, sem botão "voltar".
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (collect) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                eur,
                key: const Key('collect_reminder_amount'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 40, fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5),
            ),
            if (earnedCents > 0) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Nesta corrida ganhaste $ganhoEur',
                key: const Key('collect_reminder_earned'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('collect_reminder_ok'),
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () => Navigator.pop(ctx),
              child: Text(collect ? 'Recebi em mão' : 'Entendido'),
            ),
          ),
        ],
      ),
    ),
  );
}
