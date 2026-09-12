import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Card quadrado de categoria para o grid 4 colunas do interior do mercado.
/// Mostra foto do produto mais popular da categoria + nome sobreposto.
class MarketCategoryChipLarge extends StatelessWidget {
  const MarketCategoryChipLarge({
    super.key,
    required this.categoryName,
    required this.photoUrl,
    required this.onTap,
  });

  final String categoryName;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CategoryImage(photoUrl: photoUrl),
                  // Gradient escuro no fundo para legibilidade do texto
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            categoryName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  const _CategoryImage({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const _Fallback(),
      );
    }
    return const _Fallback();
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFE8F5E9),
        child: const Center(
          child: Icon(Icons.category_rounded,
              size: 28, color: AppColors.primary),
        ),
      );
}
