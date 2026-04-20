import 'package:flutter/material.dart';

import '../../config/app_spacing.dart';

/// Card categoria Bora — rounded 20, fundo gradiente, ícone grande, label bold.
///
/// Usado na home do cliente (grid 2 colunas) e como bloco de navegação para
/// categorias principais (Restaurantes, Supermercados, Farmácia, etc).
class BoraTileCard extends StatelessWidget {
  const BoraTileCard({
    super.key,
    required this.label,
    required this.gradient,
    required this.onTap,
    this.icon,
    this.iconData,
    this.imageAsset,
    this.height = 140,
  });

  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  /// Widget de ícone custom (prioridade sobre iconData).
  final Widget? icon;

  /// IconData simples, renderizado branco grande.
  final IconData? iconData;

  /// Path de asset PNG/JPG. Se presente, renderiza em vez do ícone.
  final String? imageAsset;

  final double height;

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
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
            // Gradient overlay para garantir contraste do label.
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
      ),
    );
  }
}
