import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Banner promocional Bora — gradiente laranja, título bold + subtítulo opcional.
///
/// Padrão da referência visual: título à esquerda, imagem/ícone à direita.
class BoraPromoBanner extends StatelessWidget {
  const BoraPromoBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.trailingAsset,
    this.trailingIcon,
    this.onTap,
    this.height = 120,
  });

  final String title;
  final String? subtitle;
  final String? trailingAsset;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: AppColors.promoGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingAsset != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: Image.asset(
                trailingAsset!,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
              ),
            )
          else if (trailingIcon != null)
            Icon(trailingIcon, color: Colors.white, size: 56),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: content,
    );
  }
}
