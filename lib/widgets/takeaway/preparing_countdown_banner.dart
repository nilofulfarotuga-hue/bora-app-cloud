import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/order_model.dart';

import '../../l10n/tr.dart';

/// Banner mostrado ao cliente durante `OrderStatus.preparing` num pedido
/// takeaway. Apresenta o ETA absoluto (HH:mm) e uma contagem regressiva
/// que decrementa em tempo real.
///
/// Fonte de verdade: `order.takeawayReadyAt` (definido pelo servidor
/// quando o parceiro chama RPC `partner_takeaway_accept` com prep_minutes).
/// Sem `takeawayReadyAt` o widget colapsa (SizedBox.shrink).
class PreparingCountdownBanner extends StatefulWidget {
  const PreparingCountdownBanner({super.key, required this.order});

  final OrderModel order;

  @override
  State<PreparingCountdownBanner> createState() =>
      _PreparingCountdownBannerState();
}

class _PreparingCountdownBannerState extends State<PreparingCountdownBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readyAt = widget.order.takeawayReadyAt;
    if (readyAt == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final remaining = readyAt.difference(now);
    final hh = readyAt.hour.toString().padLeft(2, '0');
    final mm = readyAt.minute.toString().padLeft(2, '0');

    final String headline;
    final String subtitle;
    if (remaining.isNegative || remaining.inSeconds <= 0) {
      headline = 'Quase pronto…'.tr;
      subtitle = 'O parceiro vai marcar pronto a qualquer momento'.tr;
    } else if (remaining.inMinutes < 1) {
      headline = 'Pronto em menos de 1 min'.tr;
      subtitle = 'Pronto às {0}:{1}'.trArgs([hh, mm]);
    } else {
      headline = 'Pronto em ~{0} min'.trArgs([remaining.inMinutes]);
      subtitle = 'Pronto às {0}:{1}'.trArgs([hh, mm]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant, color: AppColors.success, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restaurante a preparar — {0}'.trArgs([headline]),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.success.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
