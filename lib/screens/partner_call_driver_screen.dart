import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
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

  /// Preço de balcão (o que a loja cobra ao balcão). O servidor usa o mesmo.
  static double _precoBalcao(PartnerProduct product) =>
      product.partnerShelfPrice ?? product.price;

  double _calculateSubtotal(List<PartnerProduct> products) {
    double total = 0;
    for (final product in products) {
      final quantity = _quantityFor(product.id);
      if (quantity <= 0) continue;
      total += _precoBalcao(product) * quantity;
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
    // Só uma estimativa para o ecrã. Os valores que contam são calculados no
    // servidor (partner_chamar_estafeta) e mostrados depois de criar o pedido.
    final canSubmit = !_isSubmitting && subtotal > 0 && products.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Chamar estafeta',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
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
                  'O cliente pediu-te ao balcão ou por telefone? Chama um estafeta para lhe levar a encomenda. '
                  'O cliente paga em dinheiro os produtos ao teu preço, mais a comissão Bora (10%), '
                  'a taxa de serviço (5%) e a entrega. Tu ficas com o valor dos produtos.',
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
                      return 'Indica o nome do cliente';
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
                      return 'Indica o telefone do cliente';
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
                      'Escolhe uma sugestão para confirmar a morada.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Escolhe os produtos para esta entrega',
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
                        'Ainda não há produtos disponíveis. Adiciona produtos em "Gerir produtos" para criar pedidos.',
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
                _OrderSummaryCard(subtotal: subtotal),
                if (!canSubmit && products.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Escolhe pelo menos um produto para chamar um estafeta.',
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
                          ? 'A chamar estafeta...'
                          : 'Chamar estafeta',
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
        const SnackBar(content: Text('Indica a morada de entrega.')),
      );
      return;
    }

    if (!_addressSuggestionSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolhe uma morada da lista de sugestões.'),
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
          content: Text('Escolhe pelo menos um produto para criar o pedido.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final orderStore = context.read<OrderStore>();

    Map<String, dynamic> resultado;
    try {
      resultado = await orderStore.createPartnerDeliveryRequest(
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
      debugPrint('PartnerCallDriverScreen: chamar estafeta falhou => $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensagemErro(error))),
        );
        setState(() => _isSubmitting = false);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    String eur(Object? v) =>
        '€${((v as num?)?.toDouble() ?? 0).toStringAsFixed(2).replaceAll('.', ',')}';
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Estafeta chamado'),
        content: Text(
          'Total a cobrar ao cliente em dinheiro: ${eur(resultado['total'])}\n\n'
          'Produtos ${eur(resultado['subtotal'])} · comissão ${eur(resultado['comissao'])} · '
          'taxa de serviço ${eur(resultado['taxa_servico'])} · entrega ${eur(resultado['entrega'])}.\n\n'
          'O estafeta paga-te este total na recolha e cobra o mesmo ao cliente. '
          'Ficas com ${eur(resultado['subtotal'])}; o resto acerta-se no fecho semanal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _mensagemErro(Object error) {
    final code = error is PartnerCallDriverException ? error.code : '';
    switch (code) {
      case 'produto_nao_encontrado':
      case 'produto_sem_preco':
        return 'Um dos produtos já não está disponível. Atualiza a lista e tenta de novo.';
      case 'morada_em_falta':
        return 'Indica a morada de entrega.';
      case 'loja_nao_parceira':
      case 'forbidden':
        return 'Esta loja não pode chamar estafetas. Fala com a Bora.';
      default:
        if (error.toString().contains('CASH_LIMIT_EXCEEDED')) {
          return 'O total passa o limite de pagamento em dinheiro. Divide a encomenda.';
        }
        return 'Não foi possível chamar o estafeta. Tenta de novo.';
    }
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
                  '€${(product.partnerShelfPrice ?? product.price).toStringAsFixed(2)}',
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
  const _OrderSummaryCard({required this.subtotal});

  /// Produtos ao preço de balcão.
  final double subtotal;

  String _format(double value) =>
      '€${value.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // business_rules §2.4.1: o cliente paga produtos + comissão 10% + taxa
    // de serviço 5% + entrega, tudo em dinheiro; a loja fica com os produtos.
    // Estimativa: a entrega final depende da distância (servidor).
    final comissao = (subtotal * 0.10 * 100).roundToDouble() / 100;
    final taxa = (subtotal * 0.05 * 100).roundToDouble() / 100;
    const entregaDesde = 2.50;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo (estimativa)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _SummaryRow(
                label: 'Produtos (preço da loja)', value: _format(subtotal)),
            _SummaryRow(label: 'Comissão Bora (10%)', value: _format(comissao)),
            _SummaryRow(label: 'Taxa de serviço (5%)', value: _format(taxa)),
            _SummaryRow(
                label: 'Entrega (depende da distância)',
                value: 'desde ${_format(entregaDesde)}'),
            const Divider(height: 24),
            _SummaryRow(
              label: 'O cliente paga em dinheiro (aprox.)',
              value: _format(subtotal + comissao + taxa + entregaDesde),
              emphasize: true,
            ),
            _SummaryRow(
              label: 'Ficas com',
              value: _format(subtotal),
              emphasize: true,
            ),
            const SizedBox(height: 8),
            Text(
              'O total certo aparece quando chamares o estafeta. O estafeta '
              'paga-te esse total na recolha e cobra o mesmo ao cliente.',
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
