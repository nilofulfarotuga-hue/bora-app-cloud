import 'package:flutter/material.dart';

/// Estrelas + contagem de avaliações públicas (BR §44).
///
/// Renderiza só quando há pelo menos uma avaliação contabilizada.
/// `compact=true` reduz fonte e ícone para uso em cards/listas.
class RatingStarsBadge extends StatelessWidget {
  const RatingStarsBadge({
    super.key,
    required this.avgRating,
    required this.ratingsCount,
    this.compact = false,
    this.color,
  });

  final double? avgRating;
  final int ratingsCount;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (avgRating == null || ratingsCount <= 0) {
      return const SizedBox.shrink();
    }
    final size = compact ? 14.0 : 16.0;
    final fontSize = compact ? 12.0 : 14.0;
    final c = color ?? Colors.grey.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: size, color: Colors.amber),
        const SizedBox(width: 4),
        Text(
          '${avgRating!.toStringAsFixed(1)} ($ratingsCount)',
          style: TextStyle(
            fontSize: fontSize,
            color: c,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
