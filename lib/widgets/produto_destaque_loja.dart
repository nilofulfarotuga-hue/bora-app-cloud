import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/partner_product.dart';
import '../screens/product_detail_screen.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import 'bora/coming_soon.dart';
import 'bora/maior_18.dart';
import 'bora/weight_price_text.dart';
import 'preco_com_promocao.dart';

/// Cartão largo no topo da loja com o produto em destaque — "Hambúrguer do
/// mês" (02/11/2026, missão boom-hamburguer-mes, bloco C; padrão Glovo/Uber
/// Eats). Foto, selo, nome, preço e "Adicionar", com as MESMAS regras do
/// cartão de produto da loja: preço por PricingService.applyMarkup (promoção
/// pelo PrecoComPromocao), loja fechada/"em breve" desativa o botão, produto
/// com opções obrigatórias abre o detalhe. O ecrã não calcula preço.
class ProdutoDestaqueLoja extends StatelessWidget {
  const ProdutoDestaqueLoja({
    super.key,
    required this.product,
    required this.rotulo,
    required this.isPartnerStore,
    required this.onAdd,
  });

  final PartnerProduct product;
  final String rotulo;
  final bool isPartnerStore;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final displayPrice =
        PricingService.applyMarkup(product.price, isPartnerStore);
    final cart = context.watch<CartStore>();
    final comingSoon = cart.vendorBlocksAddToCart;
    final fechada = cart.lojaFechada;
    final avisoFechada = cart.avisoLojaFechada;
    final bloqueado = comingSoon || fechada;

    void openDetail() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              product: product,
              isPartnerStore: isPartnerStore,
            ),
          ),
        );

    final VoidCallback adicionar = fechada
        ? () => showLojaFechadaSnackBar(context, avisoFechada)
        : comingSoon
            ? () => showComingSoonBlockedSnackBar(context)
            : (product.hasRequiredOptions ? openDetail : onAdd);

    return Padding(
      key: const Key('produto_destaque_loja'),
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: openDetail,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppColors.shadowCard,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 190,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (product.photoUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: product.photoUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 900,
                            errorWidget: (_, __, ___) => const _SemFoto(),
                          )
                        else
                          const _SemFoto(),
                        Positioned(
                          top: Spacing.md,
                          left: Spacing.md,
                          child: Container(
                            key: const Key('produto_destaque_selo'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '🔥 $rotulo',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (product.ageRestricted)
                          const Positioned(
                              bottom: 8, left: 8, child: Maior18Badge()),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (product.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            product.description.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: Spacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: PrecoComPromocao(
                                restaurantId: product.restaurantId,
                                productId: product.id,
                                isPartnerStore: isPartnerStore,
                                estiloPreco: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                                semPromocao: WeightPriceText(
                                  key: const Key('produto_destaque_preco'),
                                  displayPrice:
                                      product.price > 0 ? displayPrice : 0,
                                  soldByWeight: product.soldByWeight,
                                  unavailableLabel: 'Sem preço',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              key: const Key('produto_destaque_adicionar'),
                              onPressed: adicionar,
                              style: FilledButton.styleFrom(
                                backgroundColor: bloqueado
                                    ? Colors.grey.shade400
                                    : AppColors.primary,
                                minimumSize: const Size(0, 44),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: Text('Adicionar'.tr,
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SemFoto extends StatelessWidget {
  const _SemFoto();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.accent.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: const Text('🍔', style: TextStyle(fontSize: 56)),
      );
}
