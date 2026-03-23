import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../stores/order_store.dart';
import '../stores/partner_product_store.dart';

class PartnerCallDriverScreen extends StatefulWidget {
  const PartnerCallDriverScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerCallDriverScreen> createState() => _PartnerCallDriverScreenState();
}

class _PartnerCallDriverScreenState extends State<PartnerCallDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<String, int> _quantities = {};

  bool _isSubmitting = false;

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
    _addressController.dispose();
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
    const commissionRate = 0.20;
    const deliveryFee = 2.5;
    final subtotal = _calculateSubtotal(products);
    final commission = subtotal * commissionRate;
    final total = subtotal + deliveryFee;
    final canSubmit = !_isSubmitting && subtotal > 0 && products.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Driver'),
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
                  'Submit a delivery request to call a driver. Delivery fee (€2.50) and platform commission (20%) will be charged to your restaurant.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _customerNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Customer name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the customer name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Customer phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the customer phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Delivery address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the delivery address';
                    }
                    return null;
                  },
                  minLines: 1,
                  maxLines: 2,
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
                              onDecrement: () => _updateQuantity(product.id, -1),
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
                _OrderSummaryCard(
                  subtotal: subtotal,
                  commission: commission,
                  deliveryFee: deliveryFee,
                  total: total,
                ),
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
                      _isSubmitting ? 'Chamando estafeta...' : 'Submeter pedido de entrega',
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
    if (!_formKey.currentState!.validate()) {
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
  const _OrderSummaryCard({
    required this.subtotal,
    required this.commission,
    required this.deliveryFee,
    required this.total,
  });

  final double subtotal;
  final double commission;
  final double deliveryFee;
  final double total;

  String _format(double value) => '€${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerEarnings = subtotal - commission;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo financeiro',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SummaryRow(label: 'Subtotal dos produtos', value: _format(subtotal)),
            _SummaryRow(
              label: 'Comissão da plataforma (20%)',
              value: _format(commission),
            ),
            _SummaryRow(
              label: 'Taxa de entrega',
              value: _format(deliveryFee),
            ),
            const Divider(height: 24),
            _SummaryRow(
              label: 'Total a cobrar ao cliente',
              value: _format(total),
              emphasize: true,
            ),
            _SummaryRow(
              label: 'Receita do parceiro',
              value: _format(partnerEarnings),
              emphasize: true,
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
