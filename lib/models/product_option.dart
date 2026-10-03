/// Product option groups (modifiers) — e.g. açaí cups: "Escolha os Acompanhamentos"
/// (pick N free) + "Deseja Extras?" (+€ each). Backed by DB tables
/// product_option_groups / product_option_items. Read-only on the client; the
/// partner manages them in the partner panel.
class ProductOptionItem {
  final String id;
  final String groupId;
  final String name;
  final double priceAdd; // € extra (0 = included)
  final bool isAvailable;
  final int sortOrder;

  const ProductOptionItem({
    required this.id,
    required this.groupId,
    required this.name,
    this.priceAdd = 0,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  factory ProductOptionItem.fromMap(Map<String, dynamic> m, String groupId) =>
      ProductOptionItem(
        id: m['id'] as String,
        groupId: groupId,
        name: (m['name'] as String?) ?? '',
        priceAdd: (m['price_add'] as num?)?.toDouble() ?? 0,
        isAvailable: m['is_available'] as bool? ?? true,
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}

class ProductOptionGroup {
  final String id;
  final String productId;
  final String name;
  final String? description;
  final bool isRequired;
  final int minChoices;
  final int maxChoices;
  final int sortOrder;
  final List<ProductOptionItem> items;

  const ProductOptionGroup({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    this.isRequired = false,
    this.minChoices = 0,
    this.maxChoices = 1,
    this.sortOrder = 0,
    this.items = const [],
  });

  bool get isMulti => maxChoices > 1;

  factory ProductOptionGroup.fromMap(Map<String, dynamic> m) {
    final raw = (m['product_option_items'] as List?) ?? const [];
    final items = raw
        .map((e) =>
            ProductOptionItem.fromMap(e as Map<String, dynamic>, m['id'] as String))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ProductOptionGroup(
      id: m['id'] as String,
      productId: (m['product_id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      description: m['description'] as String?,
      isRequired: m['is_required'] as bool? ?? false,
      minChoices: m['min_choices'] as int? ?? 0,
      maxChoices: m['max_choices'] as int? ?? 1,
      sortOrder: m['sort_order'] as int? ?? 0,
      items: items,
    );
  }
}

/// One group's chosen items — persisted inside CartItem and serialised into
/// orders.items JSONB as {"group": "...", "items": ["Granola", "Mel", ...]}.
class SelectedOption {
  final String group;
  final List<String> items;

  const SelectedOption({required this.group, required this.items});

  Map<String, dynamic> toJson() => {'group': group, 'items': items};

  factory SelectedOption.fromJson(Map<String, dynamic> m) => SelectedOption(
        group: (m['group'] as String?) ?? '',
        items: ((m['items'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}
