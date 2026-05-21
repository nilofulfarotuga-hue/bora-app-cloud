import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/order_service_type.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/pricing_service.dart';
import '../stores/order_store.dart';
import '../stores/partner_product_store.dart';
import '../widgets/address_autocomplete_field.dart';

class PartnerCallDriverScreen extends StatefulWidget {
  const PartnerCallDriverScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerCallDriverScreen> createState() =>
      _PartnerCallDriverScreenState();
}

class _PartnerCallDriverScreenState extends State<PartnerCallDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<String, int> _quantities = {};

  LatLng? _dropoffLocation;
  bool _addressSuggestionSelected = false;

  // The exact address string that was last confirmed via the suggestions list.
  // The controller listener compares against this to distinguish programmatic
  // text updates (controller set by AddressAutocompleteField after a selection)
  // from genuine user edits (backspace, typing, paste).
  String _lastConfirmedAddress = '';

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_onAddressControllerChanged);
  }

  /// Fires on EVERY change to _addressController — text AND selection.
  /// Resets address state only when the new text differs from the last
  /// confirmed address, which means the user genuinely edited the field.
  void _onAddressControllerChanged() {
    final text = _addressController.text;

    debugPrint(
      '[ADDR_LISTENER] text="$text" confirmed="$_lastConfirmedAddress" '
      'selected=$_addressSuggestionSelected',
    );

    if (text == _lastConfirmedAddress) {
      debugPrint('[ADDR_LISTENER] → matches confirmed, NO reset');
      return;
    }
    if (!_addressSuggestionSelected && _dropoffLocation == null) {
      debugPrint('[ADDR_LISTENER] → state already clear, skip');
      return;
    }

    debugPrint(
        '[ADDR_LISTENER] → RESET triggered from _onAddressControllerChanged');
    setState(() {
      _addressSuggestionSelected = false;
      _dropoffLocation = null;
    });
  }

  void _updateQuantity(String productId, int delta) {
    setState(() {
      final current = _quantities[productId] ?? 0;
      final next = (current + delta).clamp(0, 999);
      if (next == 0) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = next;
      }
    });
  }

  int _quantityFor(String productId) => _quantities[productId] ?? 0;

  double _calculateSubtotal(List<PartnerProduct> products) {
    double total = 0;
    for (final product in products) {
      final quantity = _quantityFor(product.id);
      if (quantity <= 0) continue;
      total += product.price * quantity;
    }
    return total;
  }

  List<PartnerOrderLine> _buildSelectedItems(List<PartnerProduct> products) {
    final lines = <PartnerOrderLine>[];
    for (final product in products) {
      final quantity = _quantityFor(product.id);
      if (quantity <= 0) continue;
      lines.add(PartnerOrderLine(product: product, quantity: quantity));
    }
    return lines;
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _phoneController.dispose();
    _addressController
      ..removeListener(_onAddressControllerChanged)
      ..dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productStore = context.watch<PartnerProductStore>();
    final products = productStore
        .productsForRestaurant(widget.restaurant.id)
        .where((product) => product.isAvailable)
        .toList();
    final subtotal = _calculateSubtotal(products);
    // Estimativa preview-only. Os valores definitivos são calculados de novo
    // dentro de createPartnerDeliveryRequest com a distância real do mapa.
    // Distance default (1 km) é aceitável aqui — a entrega base é fixa até 4 km.
    final pricing = PricingService.calculateBreakdown(
      serviceType: OrderServiceType.restaurant,
      subtotal: subtotal,
      distanceKm: PricingService.defaultDistanceKm,
      isPartnerStore: true,
      isPartnerSelfDispatch: true,
    );
    final canSubmit = !_isSubmitting && subtotal > 0 && products.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Chamar estafeta',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.restaurant.name,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Submeta um pedido de entrega para chamar um estafeta. '
                  'É cobrada uma comissão de 10% sobre o valor dos produtos ao parceiro. '
                  'A taxa de serviço (5%) e a taxa de entrega são pagas pelo cliente em dinheiro ao estafeta.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _customerNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome do cliente',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Indique o nome do cliente';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone do cliente',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Indique o telefone do cliente';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AddressAutocompleteField(
                  controller: _addressController,
                  labelText: 'Morada de entrega',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  onSelected: (address, coords) {
                    debugPrint(
                        '[ON_SELECTED] address="$address" coords=$coords');
                    // Set _lastConfirmedAddress BEFORE setState so the
                    // controller listener sees the confirmed value immediately.
                    _lastConfirmedAddress = address;
                    setState(() {
                      _addressSuggestionSelected = true;
                      _dropoffLocation = coords;
                    });
                    debugPrint(
                      '[ON_SELECTED] state after: selected=$_addressSuggestionSelected '
                      'confirmed="$_lastConfirmedAddress"',
                    );
                  },
                ),
                if (!_addressSuggestionSelected &&
                    _addressController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 12),
                    child: Text(
                      'Selecione uma sugestão para confirmar a morada.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Selecione os produtos para esta entrega',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (products.isEmpty)
                  Card(
                    color: Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.orange.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Ainda não existem produtos disponíveis. Adicione produtos em "Gerir produtos" para criar pedidos.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  Column(
                    children: products
                        .map(
                          (product) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ProductSelectionTile(
                              product: product,
                              quantity: _quantityFor(product.id),
                              onIncrement: () => _updateQuantity(product.id, 1),
                              onDecrement: () =>
                                  _updateQuantity(product.id, -1),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notas adicionais (opcional)',
                    prefixIcon: Icon(Icons.note_outlined),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                _OrderSummaryCard(pricing: pricing),
                if (!canSubmit && products.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selecione pelo menos um produto para chamar um estafeta.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.local_shipping_outlined),
                    label: Text(
                      _isSubmitting
                          ? 'Chamando estafeta...'
                          : 'Submeter pedido de entrega',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    debugPrint(
      '[SUBMIT] address="${_addressController.text}" '
      'selected=$_addressSuggestionSelected coords=$_dropoffLocation '
      'confirmed="$_lastConfirmedAddress"',
    );

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique a morada de entrega.')),
      );
      return;
    }

    if (!_addressSuggestionSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha uma morada da lista de sugestões.'),
        ),
      );
      return;
    }

    final products = context
        .read<PartnerProductStore>()
        .productsForRestaurant(widget.restaurant.id)
        .where((product) => product.isAvailable)
        .toList();
    final selectedItems = _buildSelectedItems(products);
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos um produto para criar o pedido.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final orderStore = context.read<OrderStore>();

    try {
      await orderStore.createPartnerDeliveryRequest(
        restaurant: widget.restaurant,
        customerName: _customerNameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        deliveryAddress: _addressController.text.trim(),
        dropoffLocation: _dropoffLocation,
        items: selectedItems,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível criar o pedido: $error'),
          ),
        );
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      return;
    }

    if (!mounted) return;

    setState(() => _isSubmitting = false);
    Navigator.of(context).pop(true);
  }
}

class _ProductSelectionTile extends StatelessWidget {
  const _ProductSelectionTile({
    required this.product,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final PartnerProduct product;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDecrementDisabled = quantity == 0;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: theme.textTheme.titleMedium,
            ),
            if (product.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                product.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '€${product.price.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: isDecrementDisabled ? null : onDecrement,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$quantity',
                      style: theme.textTheme.titleMedium,
                    ),
                    IconButton(
                      onPressed: onIncrement,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.pricing});

  final OrderPricingBreakdown pricing;

  String _format(double value) => '€${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Neste fluxo (parceiro chama estafeta): o cliente paga TUDO em dinheiro
    // ao estafeta — subtotal + comissão + taxa serviço + entrega. O parceiro
    // recebe o valor total das mãos do estafeta e depois acerta a comissão
    // (10% sobre o subtotal) com a Bora no acerto semanal.
    final partnerNetEarnings = pricing.subtotal - pricing.platformCommission;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo financeiro (estimativa)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SummaryRow(
                label: 'Subtotal dos produtos',
                value: _format(pricing.subtotal)),
            _SummaryRow(
              label: 'Comissão Bora (10%) — paga pelo parceiro',
              value: _format(pricing.platformCommission),
            ),
            _SummaryRow(
              label: 'Taxa de serviço (5%) — paga pelo cliente',
              value: _format(pricing.serviceFee),
            ),
            _SummaryRow(
              label: 'Taxa de entrega — paga pelo cliente',
              value: _format(pricing.deliveryFee),
            ),
            const Divider(height: 24),
            _SummaryRow(
              label: 'Total a cobrar ao cliente em dinheiro',
              value: _format(pricing.customerTotal),
              emphasize: true,
            ),
            _SummaryRow(
              label: 'Receita líquida do parceiro',
              value: _format(partnerNetEarnings),
              emphasize: true,
            ),
            const SizedBox(height: 8),
            Text(
              'O estafeta cobra o total em dinheiro ao cliente e entrega esse '
              'mesmo valor ao parceiro. A Bora acerta a comissão no fecho semanal.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = emphasize
        ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
