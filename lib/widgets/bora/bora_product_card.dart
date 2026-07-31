import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/partner_product.dart';
import '../../stores/cart_store.dart';
import 'coming_soon.dart';

/// Card grande de produto Bora — imagem preenche 62% do card, nome + preço
/// + botão "+" em baixo. Design consistente para grelhas 2 colunas (aspect 3:4).
///
/// Usar em `SliverGrid` ou `GridView.builder` com:
/// ```dart
/// SliverGridDelegateWithFixedCrossAxisCount(
///   crossAxisCount: 2,
///   mainAxisSpacing: 12,
///   crossAxisSpacing: 12,
///   childAspectRatio: 3 / 4,
/// )
/// ```
///
/// Para produtos com variants (ProductVariant), usar o card antigo — este
/// widget assume um único preço/botão "+".
class BoraProductCard extends StatelessWidget {
  const BoraProductCard({
    super.key,
    required this.product,
    required this.onAdd,
    required this.onTap,
    this.onFavoriteToggle,
    this.isFavorite = false,
    this.displayPrice,
  });

  final PartnerProduct product;

  /// Price shown to the user. When null, falls back to [product.price].
  /// Use this to render a marked-up price while keeping [product.price] raw.
  final double? displayPrice;

  /// Callback do botão "+" — deve chamar `CartStore.addItem(...)`.
  final VoidCallback onAdd;

  /// Callback do tap no card (normalmente abre ProductDetailScreen).
  final VoidCallback onTap;

  /// Se null, coração não é renderizado.
  final VoidCallback? onFavoriteToggle;

  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = product.photoUrl.isNotEmpty;
    final hasPrice = product.price > 0;
    // Loja em "Em breve" — catálogo navegável, carrinho fechado.
    final comingSoon = context.watch<CartStore>().vendorComingSoon;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 62,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhoto)
                    CachedNetworkImage(
                      imageUrl: product.photoUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const _Placeholder(),
                      errorWidget: (_, __, ___) => const _Placeholder(),
                    )
                  else
                    const _Placeholder(),
                  if (product.isPopular || product.isOnSale)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (product.isPopular)
                            const _MiniBadge(label: 'Top', color: Colors.orange),
                          if (product.isOnSale) ...[
                            if (product.isPopular) const SizedBox(width: 4),
                            const _MiniBadge(label: 'Promo', color: Colors.red),
                          ],
                        ],
                      ),
                    ),
                  if (onFavoriteToggle != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onFavoriteToggle,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 16,
                            color: isFavorite
                                ? Colors.red
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            hasPrice
                                ? '€${(displayPrice ?? product.price).toStringAsFixed(2)}'
                                : 'Indisponível',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: hasPrice
                                  ? AppColors.primary
                                  : Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          // Produtos com grupos de opção obrigatórios → "+"
                          // abre o detalhe (escolher opções) em vez de adicionar
                          // direto. Mercados/produtos sem opções: adicionar direto.
                          // Loja em "Em breve": botão cinzento + mensagem.
                          onTap: comingSoon
                              ? () => showComingSoonBlockedSnackBar(context)
                              : (hasPrice
                                  ? (product.hasRequiredOptions ? onTap : onAdd)
                                  : null),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: (hasPrice && !comingSoon)
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F2F2),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_cart_outlined,
        size: 48,
        color: Colors.grey.shade400,
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
