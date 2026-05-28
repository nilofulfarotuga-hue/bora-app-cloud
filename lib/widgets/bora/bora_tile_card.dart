import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Card categoria Bora — rounded 20, fundo gradiente, label bold.
///
/// Dois layouts disponíveis:
/// - **`BoraTileCard.image()`** (recomendado): Image.asset (PNG 3D cartoon
///   das categorias em `assets/categories/`) ocupando ~70% do tile, label
///   em baixo sobre o gradient verde.
/// - **Construtor default (`@Deprecated`)**: renderiza ícone Material ou
///   imagem em overlay full-bleed com gradient escurecido para contraste
///   do label. Mantido para preservar callers existentes — migrar na Fase 4.
class BoraTileCard extends StatelessWidget {
  /// Construtor legacy — preserva quem ainda passa IconData/icon custom.
  /// Será removido depois da migração dos ecrãs (Fase 4).
  @Deprecated('Use BoraTileCard.image() com PNG das categorias 3D cartoon.')
  const BoraTileCard({
    super.key,
    required this.label,
    required this.gradient,
    required this.onTap,
    this.icon,
    this.iconData,
    this.imageAsset,
    this.height = 140,
  }) : _useImageLayout = false;

  /// Construtor recomendado — usa PNG 3D cartoon (assets/categories/).
  const BoraTileCard.image({
    super.key,
    required this.label,
    required String this.imageAsset,
    required this.gradient,
    required this.onTap,
    this.height = 140,
  })  : icon = null,
        iconData = null,
        _useImageLayout = true;

  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  /// Widget de ícone custom (prioridade sobre iconData). Legacy.
  final Widget? icon;

  /// IconData simples, renderizado branco grande. Legacy.
  final IconData? iconData;

  /// Path de asset PNG/JPG.
  final String? imageAsset;

  final double height;

  /// Layout switch: true → 70% imagem em cima + label rodapé.
  final bool _useImageLayout;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.xl),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: AppColors.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: _useImageLayout ? _buildImageLayout() : _buildLegacyLayout(),
      ),
    );
  }

  /// Layout novo — Image.asset PNG em cima (~70%), label rodapé.
  Widget _buildImageLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 70,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Image.asset(
              imageAsset!,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            0,
            Spacing.md,
            Spacing.md,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              height: 1.1,
              shadows: [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Layout legacy — icon ou imageAsset com overlay full-bleed.
  Widget _buildLegacyLayout() {
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Stack(
        children: [
          if (imageAsset != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xl),
                child: Opacity(
                  opacity: 0.9,
                  child: Image.asset(imageAsset!, fit: BoxFit.cover),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: icon ??
                (iconData != null
                    ? Icon(iconData, color: Colors.white, size: 36)
                    : const SizedBox.shrink()),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                shadows: [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
