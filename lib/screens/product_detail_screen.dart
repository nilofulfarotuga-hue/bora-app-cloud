import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/allergens.dart';
import '../config/app_colors.dart';
import '../models/cart_item.dart';
import '../models/partner_product.dart';
import '../models/product_option.dart';
import '../models/product_variant.dart';
import '../services/pricing_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';
import '../utils/cart_feedback.dart';
import '../widgets/bora/bora_accent_button.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/coming_soon.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.isPartnerStore,
  });

  final PartnerProduct product;

  /// B1 (2026-06-11): obrigatório para a regra de preço exibido = cobrado.
  /// Não-parceiro: markup 15% runtime via PricingService.applyMarkup.
  final bool isPartnerStore;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductVariant? _selectedVariant;
  int _quantity = 1;

  // Option groups (modifiers) — fetched lazily for this product. Empty for
  // products without modifiers (the vast majority). Selections keyed by group id.
  List<ProductOptionGroup> _groups = const [];
  final Map<String, Set<String>> _sel = {};

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final res = await Supabase.instance.client
          .from('product_option_groups')
          .select(
              'id,product_id,name,description,is_required,min_choices,max_choices,sort_order,product_option_items(id,name,price_add,is_available,sort_order)')
          .eq('product_id', widget.product.id)
          .order('sort_order');
      final list = (res as List)
          .map((e) => ProductOptionGroup.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (mounted) setState(() => _groups = list);
    } catch (e) {
      debugPrint('ProductDetail._loadGroups error: $e');
    }
  }

  // ── Option-group helpers ───────────────────────────────────────────────────
  int _selCount(ProductOptionGroup g) => _sel[g.id]?.length ?? 0;
  bool get _requiredOk => _groups.every((g) => _selCount(g) >= g.minChoices);
  double get _optionsPrice {
    double sum = 0;
    for (final g in _groups) {
      final ids = _sel[g.id];
      if (ids == null) continue;
      for (final it in g.items) {
        if (ids.contains(it.id)) sum += it.priceAdd;
      }
    }
    return sum;
  }

  void _toggleOption(ProductOptionGroup g, ProductOptionItem it) {
    if (!it.isAvailable) return;
    final set = _sel.putIfAbsent(g.id, () => <String>{});
    setState(() {
      if (g.maxChoices <= 1) {
        set
          ..clear()
          ..add(it.id);
      } else if (set.contains(it.id)) {
        set.remove(it.id);
      } else if (set.length < g.maxChoices) {
        set.add(it.id);
      }
    });
  }

  String _groupHint(ProductOptionGroup g) {
    if (g.minChoices > 0 && g.minChoices == g.maxChoices) {
      return 'Escolhe ${g.minChoices}';
    }
    if (g.minChoices > 0) return 'Escolhe ${g.minChoices} a ${g.maxChoices}';
    return 'Escolhe até ${g.maxChoices}';
  }

  // Confirmação compacta e não-bloqueante (padrão Uber Eats / Glovo) — o
  // mesmo snack verde de uma linha usado no menu e nas lojas. Tocar só
  // adiciona; a acção "Ver" leva ao carrinho, sem navegar automaticamente.
  //
  // 2026-08-25 (defeito apanhado pelo Danilo no telemóvel): adicionar FECHA a
  // ficha e devolve o cliente ao menu da loja — o aviso fica por cima e a
  // barra "Ver carrinho" já mostra o total novo. O aviso é mostrado ANTES do
  // pop de propósito: o ScaffoldMessenger é global, portanto sobrevive à
  // navegação (e o "Ver" usa o NavigatorState capturado no helper).
  void _snackEFecha(String msg) {
    showAddedToCartSnack(context, msg);
    fecharFichaAposAdicionar(context);
  }

  // Sessão 4C: ProductVariant.id é UUID válido — usar directamente.
  // Embeber o nome do produto criava productId que falhava lookup na RPC.
  String _variantKey(ProductVariant v) => v.id;

  // B1 (2026-06-11): price = exibido/cobrado (markup não-parceiro runtime);
  // basePrice = puro de catálogo (product_lines.unit_price — fallback server).
  void _addToCart(BuildContext context, ProductVariant v) {
    context.read<CartStore>().addItem(CartItem(
          productId: _variantKey(v),
          name: '${widget.product.name} (${v.brandName})',
          price: PricingService.applyMarkup(v.price, widget.isPartnerStore),
          basePrice: v.price,
          quantity: _quantity,
        ));
    _snackEFecha('${v.brandName} × $_quantity adicionado ao carrinho');
  }

  void _addNoVariantToCart(BuildContext context) {
    context.read<CartStore>().addItem(CartItem(
          productId: widget.product.id,
          name: widget.product.name,
          price: PricingService.applyMarkup(
              widget.product.price, widget.isPartnerStore),
          basePrice: widget.product.price,
          quantity: _quantity,
        ));
    _snackEFecha('${widget.product.name} × $_quantity adicionado ao carrinho');
  }

  void _addWithOptions(BuildContext context) {
    final selected = <SelectedOption>[];
    for (final g in _groups) {
      final ids = _sel[g.id];
      if (ids == null || ids.isEmpty) continue;
      final names =
          g.items.where((it) => ids.contains(it.id)).map((it) => it.name).toList();
      if (names.isNotEmpty) {
        selected.add(SelectedOption(group: g.name, items: names));
      }
    }
    // T1 (2026-06-11): exibido = cobrado. O create_order soma o price_add das
    // opções ao preço base ANTES do ×1.15 não-parceiro — (base + extras) ×1.15.
    // O display aplica o mesmo markup a base + extras (parceiro: identidade).
    final unit = PricingService.applyMarkup(
        widget.product.price + _optionsPrice, widget.isPartnerStore);
    context.read<CartStore>().addItem(CartItem(
          productId: widget.product.id,
          name: widget.product.name,
          price: unit,
          basePrice: widget.product.price,
          quantity: _quantity,
          selectedOptions: selected,
        ));
    _snackEFecha('${widget.product.name} × $_quantity adicionado ao carrinho');
  }

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final rawVariants =
        context.watch<RestaurantStore>().variantsForProduct(widget.product.id);
    final variants = [...rawVariants]
      ..sort((a, b) => a.price.compareTo(b.price));

    // Auto-select first variant if none selected yet
    if (_selectedVariant == null && variants.isNotEmpty) {
      _selectedVariant = variants.first;
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final total = variants.length;
    final hasGroups = variants.isEmpty && _groups.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Hero image SliverAppBar ──────────────────────────────────
                SliverAppBar(
                  expandedHeight: MediaQuery.of(context).size.width,
                  pinned: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  actions: [
                    _CartBadge(cartStore: cartStore),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _selectedVariant != null
                          ? _ProductHeroImage(
                              key: ValueKey(_selectedVariant!.id),
                              photoUrl: widget.product.photoUrl,
                            )
                          : _ProductHeroImage(
                              key: const ValueKey('base'),
                              photoUrl: widget.product.photoUrl,
                            ),
                    ),
                  ),
                ),

                // ── Product name + description ───────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        if (widget.product.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.product.description,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                        // B6 (2026-06-12): alergénios (Reg. UE 1169/2011) —
                        // chips quando declarados; disclaimer quando vazio.
                        const SizedBox(height: 12),
                        if (widget.product.allergens.isNotEmpty) ...[
                          const Text(
                            'Alergénios',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final slug in widget.product.allergens)
                                Chip(
                                  label: Text(
                                    kAllergenLabels[slug] ?? slug,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: Colors.amber.shade50,
                                  side: BorderSide(
                                      color: Colors.amber.shade200),
                                ),
                            ],
                          ),
                        ] else
                          Text(
                            'Consulte o estabelecimento para informações '
                            'sobre alergénios.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // ── Option groups (modifiers) ────────────────────────────────
                if (hasGroups)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        children:
                            _groups.map((g) => _buildGroupCard(g)).toList(),
                      ),
                    ),
                  ),

                // ── Variants section header ──────────────────────────────────
                if (variants.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        total == 1
                            ? '1 marca disponível'
                            : '$total marcas disponíveis',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                // ── Variant cards (selection only) ───────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final v = variants[i];
                        final isCheapest = i == 0 && total > 1;
                        final isPremium = i == total - 1 && total > 1;
                        final isSelected = _selectedVariant?.id == v.id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _VariantCard(
                            variant: v,
                            displayPrice: PricingService.applyMarkup(
                                v.price, widget.isPartnerStore),
                            isSelected: isSelected,
                            isCheapest: isCheapest,
                            isPremium: isPremium,
                            primaryColor: primaryColor,
                            productPhotoUrl: widget.product.photoUrl,
                            onSelect: () =>
                                setState(() => _selectedVariant = v),
                          ),
                        );
                      },
                      childCount: variants.length,
                    ),
                  ),
                ),

                // ── Global quantity selector ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepButton(
                          icon: Icons.remove,
                          color: primaryColor,
                          onTap: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add,
                          color: primaryColor,
                          onTap: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Fixed bottom button ──────────────────────────────────────────
          _buildBottomBar(context, variants, hasGroups),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
      BuildContext context, List<ProductVariant> variants, bool hasGroups) {
    // "Em breve": o produto continua visível e navegável, mas o botão de
    // adicionar fica cinzento (não invisível) e explica porquê ao toque.
    final comingSoon = context.watch<CartStore>().vendorBlocksAddToCart;

    Widget wrap(Widget child) => SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: comingSoon
              ? Tooltip(
                  message: kComingSoonBlockedMessage,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showComingSoonBlockedSnackBar(context),
                    child: AbsorbPointer(child: child),
                  ),
                )
              : child,
        );

    if (comingSoon) {
      // Botão desactivado (onPressed: null → cinzento pelo tema).
      return wrap(const BoraPrimaryButton(
        label: 'Adicionar ao carrinho',
        icon: Icons.add_shopping_cart,
        onPressed: null,
      ));
    }

    // B1 (2026-06-11): botões exibem o preço COBRADO (markup runtime
    // não-parceiro via applyMarkup; parceiro = preço puro do menu).
    if (variants.isNotEmpty) {
      if (_selectedVariant == null) return const SizedBox.shrink();
      return wrap(BoraAccentButton(
        label:
            'Adicionar ao carrinho · €${PricingService.applyMarkup(_selectedVariant!.price, widget.isPartnerStore).toStringAsFixed(2)}',
        icon: Icons.add_shopping_cart,
        onPressed: () => _addToCart(context, _selectedVariant!),
      ));
    }

    if (hasGroups) {
      // T1: mesmo cálculo do _addWithOptions — (base + extras) com markup.
      // Antes as opções ficavam de fora do markup e o rótulo divergia do
      // cobrado em não-parceiro com opções.
      final unit = PricingService.applyMarkup(
          widget.product.price + _optionsPrice, widget.isPartnerStore);
      final ok = widget.product.price > 0 && _requiredOk;
      // Green primary button keeps the single orange element = the required
      // badge ("1 laranja por ecrã" — badge tem prioridade).
      return wrap(BoraPrimaryButton(
        label: ok
            ? 'Adicionar ao carrinho · €${unit.toStringAsFixed(2)}'
            : 'Completa as escolhas obrigatórias',
        icon: Icons.add_shopping_cart,
        onPressed: ok ? () => _addWithOptions(context) : null,
      ));
    }

    return wrap(BoraAccentButton(
      label: widget.product.price > 0
          ? 'Adicionar ao carrinho · €${PricingService.applyMarkup(widget.product.price, widget.isPartnerStore).toStringAsFixed(2)}'
          : 'Preço indisponível',
      icon: Icons.add_shopping_cart,
      onPressed:
          widget.product.price > 0 ? () => _addNoVariantToCart(context) : null,
    ));
  }

  // ── Option-group card ──────────────────────────────────────────────────────
  Widget _buildGroupCard(ProductOptionGroup g) {
    final count = _selCount(g);
    final satisfied = count >= g.minChoices;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  g.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (g.isRequired)
                const _Badge(label: 'Obrigatório', color: AppColors.accent)
              else
                const _Badge(
                    label: 'Opcional', color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                _groupHint(g),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                'Escolheste $count de ${g.maxChoices}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: satisfied ? AppColors.primary : AppColors.textSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...g.items.map((it) => _buildOptionRow(g, it)),
        ],
      ),
    );
  }

  Widget _buildOptionRow(ProductOptionGroup g, ProductOptionItem it) {
    final selected = _sel[g.id]?.contains(it.id) ?? false;
    final atMax = g.maxChoices > 1 && _selCount(g) >= g.maxChoices;
    final disabled = !it.isAvailable || (!selected && atMax);
    final single = g.maxChoices <= 1;
    final IconData icon = single
        ? (selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked)
        : (selected ? Icons.check_box : Icons.check_box_outline_blank);
    return InkWell(
      onTap: disabled ? null : () => _toggleOption(g, it),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: selected
                    ? AppColors.primary
                    : (disabled ? AppColors.textSubtle : AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                it.name,
                style: TextStyle(
                  fontSize: 14.5,
                  color: it.isAvailable
                      ? AppColors.textPrimary
                      : AppColors.textSubtle,
                  decoration: it.isAvailable
                      ? TextDecoration.none
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (it.priceAdd > 0)
              Text(
                '+€${it.priceAdd.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero image widget ─────────────────────────────────────────────────────────

class _ProductHeroImage extends StatelessWidget {
  const _ProductHeroImage({super.key, required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _HeroPlaceholder(),
      );
    }
    return _HeroPlaceholder();
  }
}

class _HeroPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEEEEE),
      child: const Center(
        child: Icon(Icons.fastfood_rounded, size: 80, color: Colors.grey),
      ),
    );
  }
}

// ─── Variant card (large) ──────────────────────────────────────────────────────

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.displayPrice,
    required this.isSelected,
    required this.isCheapest,
    required this.isPremium,
    required this.primaryColor,
    required this.productPhotoUrl,
    required this.onSelect,
  });

  final ProductVariant variant;

  /// B1: preço exibido = cobrado (markup não-parceiro aplicado pelo caller).
  final double displayPrice;
  final bool isSelected;
  final bool isCheapest;
  final bool isPremium;
  final Color primaryColor;
  final String productPhotoUrl;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ── Variant image ──────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: productPhotoUrl.isNotEmpty
                    ? Image.network(
                        productPhotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _SmallPlaceholder(),
                      )
                    : _SmallPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),

            // ── Brand name + badge ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.brandName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (isCheapest)
                    _Badge(label: 'Mais barato', color: Colors.green.shade600)
                  else if (isPremium)
                    _Badge(label: 'Premium', color: Colors.blue.shade600),
                  const SizedBox(height: 6),
                  Text(
                    '€${displayPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // ── Selection indicator ────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primaryColor : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(
      {required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: disabled ? Colors.grey : color),
      ),
    );
  }
}

class _SmallPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEEEEE),
      child:
          const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
    );
  }
}

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.cartStore});

  final CartStore cartStore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
        ),
        if (cartStore.totalItems > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.red,
                child: Text(
                  '${cartStore.totalItems}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
