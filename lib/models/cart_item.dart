import 'product_option.dart';

class CartItem {
  final String productId;
  final String name;

  /// Preço EXIBIDO e COBRADO por unidade. Para lojas não-parceiro já inclui
  /// o markup de 15% (PricingService.applyMarkup, sem arredondar); para
  /// parceiros é o preço do menu. Gravado em orders.items como `price` para
  /// o histórico do cliente bater com o Stripe (B1 2026-06-11).
  final double price;
  int quantity;
  String purchaseStatus; // 'pending', 'bought', 'unavailable'
  double? actualPrice; // real price if different from estimated (future use)

  /// Preço PURO de catálogo (products.price, sem markup de exibição).
  /// Enviado em product_lines.unit_price — o servidor usa-o como fallback
  /// quando o product_id não existe em `products` (ex. variantes) e aplica
  /// o ×1.15 por cima; enviar o preço com markup causaria duplo markup.
  /// null em dados legados → tratar [price] como já-final.
  final double? basePrice;

  /// Modifiers chosen for this line (e.g. açaí toppings). Empty for normal
  /// products. [price] already includes any paid extras. Persisted in
  /// orders.items JSONB as `selected_options`.
  final List<SelectedOption> selectedOptions;

  /// T1 (2026-06-11): versão com preço das opções, gravada pelo SERVIDOR
  /// (create_order) em orders.items como `selected_options_priced`
  /// ({group, items:[{name, price_add}]}). Itens chegam aqui já formatados
  /// "Nome (+€X,XX)" quando price_add > 0. Read-only do histórico — NUNCA
  /// serializada em toJson (reorder tem de voltar aos nomes puros para o
  /// match server-side por nome funcionar).
  final List<SelectedOption> selectedOptionsPriced;

  /// Opções para exibição: com preço quando o servidor as gravou (histórico
  /// de pedidos), senão as escolhas locais (carrinho pré-checkout).
  List<SelectedOption> get displayOptions =>
      selectedOptionsPriced.isNotEmpty ? selectedOptionsPriced : selectedOptions;

  // Sessão 4C (2026-05-04): defesa run-time em release.
  // Asserts (4B5) STRIP em release → asserts são detectores dev. Validação
  // crítica usa `if-throw` no body do constructor (executa também em release).
  // Callers DEVEM passar productId real (TEXT) da row em public.products.
  // fromJson usa _raw (sem validação) por tolerância a legacy data persistida
  // em orders.items pré-Bug-B fix.
  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
    this.basePrice,
    this.selectedOptions = const [],
    this.selectedOptionsPriced = const [],
  })  : assert(productId.isNotEmpty, 'CartItem.productId vazio'),
        assert(!productId.contains(' '),
            'CartItem.productId com espaço — parece nome ($productId)'),
        assert(productId.length < 200,
            'CartItem.productId muito longo — parece nome (len=${productId.length})') {
    if (productId.isEmpty) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId vazio');
    }
    if (productId.contains(' ')) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId contém espaço — parece nome');
    }
    if (productId.length > 200) {
      throw ArgumentError.value(productId, 'productId',
          'CartItem.productId muito longo (${productId.length} chars) — parece nome');
    }
  }

  // Construtor sem asserts para desserializar legacy data persistida em
  // orders.items (productId pode ser nome literal pré-Bug-B fix). Não usar
  // para criar novas instâncias — usar [CartItem.new] que valida via asserts.
  CartItem._raw({
    required this.productId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.purchaseStatus = 'pending',
    this.actualPrice,
    this.basePrice,
    this.selectedOptions = const [],
    this.selectedOptionsPriced = const [],
  });

  /// Cart dedup key. Two lines with different option selections are distinct.
  /// Equals [name] when there are no options → products without modifiers keep
  /// the previous name-based merge behaviour unchanged.
  String get lineKey => selectedOptions.isEmpty
      ? name
      : '$name|${selectedOptions.map((o) => '${o.group}=${o.items.join(",")}').join(';')}';

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'purchaseStatus': purchaseStatus,
        if (actualPrice != null) 'actualPrice': actualPrice,
        if (basePrice != null) 'basePrice': basePrice,
        if (selectedOptions.isNotEmpty)
          'selected_options':
              selectedOptions.map((o) => o.toJson()).toList(),
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['productId'] as String?;
    final name = json['name'] as String;
    final rawOpts = json['selected_options'] as List?;
    final rawPriced = json['selected_options_priced'] as List?;
    return CartItem._raw(
      productId: (rawId == null || rawId.isEmpty) ? name : rawId,
      name: name,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int? ?? 1,
      purchaseStatus: json['purchaseStatus'] as String? ?? 'pending',
      actualPrice: (json['actualPrice'] as num?)?.toDouble(),
      basePrice: (json['basePrice'] as num?)?.toDouble(),
      selectedOptions: rawOpts == null
          ? const []
          : rawOpts
              .map((e) => SelectedOption.fromJson(e as Map<String, dynamic>))
              .toList(),
      selectedOptionsPriced:
          rawPriced == null ? const [] : _parsePricedOptions(rawPriced),
    );
  }

  // T1 (2026-06-11): selected_options_priced vem do servidor como
  // [{group, items:[{name, price_add}]}] — formata cada item como
  // "Nome (+€X,XX)" quando pago, só "Nome" quando grátis.
  static List<SelectedOption> _parsePricedOptions(List raw) {
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      final items = ((m['items'] as List?) ?? const []).map((it) {
        if (it is Map) {
          final name = (it['name'] ?? '').toString();
          final add = (it['price_add'] as num?)?.toDouble() ?? 0;
          return add > 0 ? '$name (+€${add.toStringAsFixed(2)})' : name;
        }
        return it.toString();
      }).toList();
      return SelectedOption(
          group: (m['group'] as String?) ?? '', items: items);
    }).toList();
  }
}
