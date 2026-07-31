import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/cart_item.dart';
import '../../models/partner_product.dart';
import '../../screens/product_detail_screen.dart';
import '../../services/pricing_service.dart';
import '../../stores/cart_store.dart';
import '../../stores/restaurant_store.dart';
import '../../utils/cart_feedback.dart';
import '../bora/coming_soon.dart';

/// Card horizontal estilo Glovo para secções de produtos no interior do mercado.
/// Largura fixa ~160px, altura ~220px — adequado para scroll horizontal.
///
/// Comportamento do botão "+":
///   - sem variantes → CartStore.addItem() directo + SnackBar
///   - com variantes → Navigator.push ProductDetailScreen
class MarketProductCard extends StatelessWidget {
  const MarketProductCard({
    super.key,
    required this.product,
    required this.restaurantId,
    required this.storeName,
    required this.isPartnerStore,
  });

  final PartnerProduct product;
  final String restaurantId;
  final String storeName;
  final bool isPartnerStore;

  static const double _cardWidth = 160;
  static const double _imageHeight = 120;

  void _handleAdd(BuildContext context) {
    final variants =
        context.read<RestaurantStore>().variantsForProduct(product.id);
    if (variants.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            product: product,
            isPartnerStore: isPartnerStore,
          ),
        ),
      );
      return;
    }
    // B1 (2026-06-11): price = exibido/cobrado (markup não-parceiro);
    // basePrice = puro de catálogo (vai em product_lines.unit_price).
    context.read<CartStore>().addItem(CartItem(
          productId: product.id,
          name: product.name,
          price: PricingService.applyMarkup(product.price, isPartnerStore),
          basePrice: product.price,
          quantity: 1,
        ));
    showAddedToCartSnack(context, '${product.name} no carrinho');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            product: product,
            isPartnerStore: isPartnerStore,
          ),
        ),
      ),
      child: SizedBox(
        width: _cardWidth,
        child: Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductImage(product: product),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // B1 (2026-06-11): preço exibido = preço COBRADO =
                    // products.price com markup runtime (applyMarkup;
                    // parceiro = puro). O servidor NÃO honra discount_price
                    // na cobrança — exibir o desconto riscado cobrando o
                    // preço cheio era enganoso (14 produtos Lidl afetados;
                    // decisão sobre honrar promoções reportada ao Danilo).
                    Text(
                      '€${PricingService.applyMarkup(product.price, isPartnerStore).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    _AddButton(onTap: () => _handleAdd(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});
  final PartnerProduct product;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: MarketProductCard._imageHeight,
          child: product.photoUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: product.photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const _Placeholder(),
                )
              : const _Placeholder(),
        ),
        if (product.isOnSale)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Promoção',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF0F0F0),
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 32, color: Color(0xFFBDBDBD)),
        ),
      );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Loja em "Em breve": botão cinzento (não invisível) + mensagem ao toque.
    final comingSoon = context.watch<CartStore>().vendorComingSoon;
    // identifier estável para o E2E tocar o "+" pequeno do card por id
    // (btn_add_carrinho), em vez de adivinhar a coordenada do ícone sem texto.
    return Semantics(
      identifier: 'btn_add_carrinho',
      button: true,
      child: GestureDetector(
        onTap: comingSoon ? () => showComingSoonBlockedSnackBar(context) : onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: comingSoon ? Colors.grey.shade400 : AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add,
              color: Colors.white, size: 18, semanticLabel: 'Adicionar'),
        ),
      ),
    );
  }
}
