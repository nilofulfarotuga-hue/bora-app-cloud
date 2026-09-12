import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/order_model.dart';

import '../../l10n/tr.dart';

/// BR §14.11 — cartão grande para o estado `readyForPickup`.
///
/// Mostra: vendor name, código 6 chars em destaque, info curbside (se
/// aplicável), e timestamp `takeawayReadyAt`. Usado em
/// [OrderTrackingScreen] e [OrderDetailsScreen].
class PickupCodeCard extends StatelessWidget {
  const PickupCodeCard({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final code = order.takeawayPickupCode ?? '—';
    final readyAt = order.takeawayReadyAt;
    final readyAtLabel = readyAt != null
        ? '${readyAt.hour.toString().padLeft(2, '0')}:${readyAt.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Pronto para levantar'.tr,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
          if (order.vendorName != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              order.vendorName!,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.xl,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Apresente este código no balcão'.tr,
            style: const TextStyle(fontSize: 13),
          ),
          if (order.takeawayIsCurbside) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.directions_car, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Curbside · {0}'.trArgs([order.takeawayCurbsideInfo ?? "—"]),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (readyAtLabel != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Pronto às {0}'.trArgs([readyAtLabel]),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
