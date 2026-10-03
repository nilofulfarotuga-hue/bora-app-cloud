import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Barra de morada Bora — card branco com pin verde + morada em 2 linhas.
///
/// Padrão da home do cliente: "Entrega em" + rua/cidade. Toque abre selector.
///
/// `onHeader: true` adiciona uma border 1px subtil para destacar contra
/// fundos verdes (ex.: quando colocado dentro do gradient header). Sombra
/// `shadowSm` sempre activa (subtil em ambos os contextos).
class BoraAddressBar extends StatelessWidget {
  const BoraAddressBar({
    super.key,
    required this.label,
    required this.address,
    this.onTap,
    this.onHeader = false,
  });

  /// Prefixo (e.g. "Entrega em", "Recolha em").
  final String label;

  /// Endereço principal formatado.
  final String address;

  final VoidCallback? onTap;

  /// True quando renderizado sobre o header verde — adiciona border subtil.
  final bool onHeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowSm,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border:
                  onHeader ? Border.all(color: AppColors.divider) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
