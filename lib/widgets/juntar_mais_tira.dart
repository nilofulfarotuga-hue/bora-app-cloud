import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/cart_item.dart';
import '../models/partner_product.dart';
import '../screens/product_detail_screen.dart';
import '../services/interruptores_app.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/cart_feedback.dart';
import '../utils/euros.dart';

/// Os produtos que a tira "Juntar mais" oferece (paridade pequena 5,
/// 29/10/2026): até [max] da MESMA loja, do mais barato para o mais caro,
/// sem esgotados. Só serve para escolher; quem adiciona é o carrinho.
List<PartnerProduct> produtosParaJuntarMais(
  Iterable<PartnerProduct> daLoja, {
  int max = 3,
}) {
  final lista = daLoja
      .where((p) =>
          p.isAvailable &&
          p.price > 0 &&
          !p.id.startsWith('premio-checkin-'))
      .toList()
    ..sort((a, b) {
      final c = a.price.compareTo(b.price);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return lista.take(max).toList();
}

/// Frase por baixo do título: o que falta, e para quê.
/// `null` quando não falta nada (a tira não aparece).
String? subtituloJuntarMais({
  required double faltaEntregaGratis,
  required double faltaMinimo,
}) {
  String eur2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  if (faltaEntregaGratis > 0) {
    return 'Faltam {0} € para a entrega grátis'.trArgs([eur2(faltaEntregaGratis)]);
  }
  if (faltaMinimo > 0) {
    return 'Faltam {0} € para evitar a taxa de pedido pequeno'
        .trArgs([eur2(faltaMinimo)]);
  }
  return null;
}

/// "Juntar mais" no carrinho: 3 produtos baratos da mesma loja, para chegar
/// à entrega grátis ou ao mínimo sem sair do carrinho. Só junta produtos pelo
/// método normal do carrinho: não toca em preços nem em taxas.
class JuntarMaisTira extends StatefulWidget {
  const JuntarMaisTira({super.key});

  @override
  State<JuntarMaisTira> createState() => _JuntarMaisTiraState();
}

class _JuntarMaisTiraState extends State<JuntarMaisTira> {
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance.ligado(InterruptoresApp.juntarMais).then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
  }

  void _adicionar(BuildContext context, CartStore cart, PartnerProduct p) {
    // Opções obrigatórias (tamanho, acompanhamento) ou venda ao peso: o "+"
    // abre o detalhe em vez de adicionar logo.
    if (p.hasRequiredOptions || p.soldByWeight) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(
            product: p,
            isPartnerStore: cart.isPartnerStore,
          ),
        ),
      );
      return;
    }
    cart.addItem(CartItem(
      productId: p.id,
      name: p.name,
      price: PricingService.applyMarkup(p.price, cart.isPartnerStore),
      basePrice: p.price,
      ageRestricted: p.ageRestricted,
    ));
    showAddedToCartSnack(context, '{0} no carrinho'.trArgs([p.name]));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final cart = context.watch<CartStore>();
    if (cart.items.isEmpty || cart.isTakeaway && cart.faltaParaMinimo <= 0) {
      return const SizedBox.shrink();
    }
    final sub = subtituloJuntarMais(
      faltaEntregaGratis: cart.isTakeaway ? 0 : cart.faltaParaEntregaGratis,
      faltaMinimo: cart.faltaParaMinimo,
    );
    final lojaId = cart.vendorRestaurantId;
    if (sub == null || lojaId == null) return const SizedBox.shrink();
    final store = context.watch<RestaurantStore>();
    final noCarrinho = {for (final i in cart.items) i.productId};
    final sugestoes = produtosParaJuntarMais(
      store
          .partnerProductsForRestaurant(lojaId)
          .where((p) => !noCarrinho.contains(p.id)),
    );
    if (sugestoes.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('tira_juntar_mais'),
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Juntar mais'.tr,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            sub,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark),
          ),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sugestoes.length,
              separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
              itemBuilder: (_, i) => _CartaoJuntar(
                produto: sugestoes[i],
                preco: PricingService.applyMarkup(
                    sugestoes[i].price, cart.isPartnerStore),
                onAdd: () => _adicionar(context, cart, sugestoes[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoJuntar extends StatelessWidget {
  const _CartaoJuntar({
    required this.produto,
    required this.preco,
    required this.onAdd,
  });

  final PartnerProduct produto;
  final double preco;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: SizedBox(
              width: 56,
              height: 56,
              child: produto.photoUrl.isEmpty
                  ? Container(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      alignment: Alignment.center,
                      child: const Icon(Icons.fastfood_outlined,
                          color: AppColors.primary),
                    )
                  : Image.network(
                      produto.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        alignment: Alignment.center,
                        child: const Icon(Icons.fastfood_outlined,
                            color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produto.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  eur(preco),
                  style: const TextStyle(
                      fontSize: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Juntar {0}'.trArgs([produto.name]),
            child: InkWell(
              key: Key('juntar_${produto.id}'),
              onTap: onAdd,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
