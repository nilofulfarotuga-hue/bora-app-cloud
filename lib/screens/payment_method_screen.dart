import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../models/order_model.dart';
import '../stores/cart_store.dart';
import '../stores/order_store.dart';
import '../services/payment_service.dart';

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  PaymentMethod _selectedMethod = PaymentMethod.card;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final cartStore = context.watch<CartStore>();
    final pricing = cartStore.pricingBreakdown;
    final totalToPay = pricing.customerTotal;
    final hasApartmentDelivery = cartStore.apartmentDelivery;
    double baseDeliveryFee = pricing.deliveryFee - pricing.apartmentSurcharge;
    if (baseDeliveryFee < 0) {
      baseDeliveryFee = 0;
    }

    const paymentOptions = <_PaymentOption>[
      _PaymentOption(
        method: PaymentMethod.card,
        title: 'Cartão (Stripe)',
        subtitle: 'Pague com cartão de crédito ou débito.',
        icon: Icons.credit_card,
      ),
      _PaymentOption(
        method: PaymentMethod.mbway,
        title: 'MBWay',
        subtitle: 'Receba uma notificação e confirme no MBWay.',
        icon: Icons.phone_iphone,
      ),
      _PaymentOption(
        method: PaymentMethod.cash,
        title: 'Dinheiro',
        subtitle: 'Pague diretamente ao estafeta na entrega.',
        icon: Icons.payments,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamento'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Resumo do pedido',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(label: 'Subtotal', value: pricing.subtotal),
                        if (pricing.serviceFee > 0)
                          _SummaryRow(label: 'Taxas', value: pricing.serviceFee),
                        _SummaryRow(label: 'Entrega', value: baseDeliveryFee),
                        if (pricing.apartmentSurcharge > 0)
                          _SummaryRow(
                            label: 'Entrega em apartamento',
                            value: pricing.apartmentSurcharge,
                          ),
                        if (hasApartmentDelivery)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.apartment, color: Colors.orange.shade600, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Apartment delivery requested — +€1 bonus para o estafeta.',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 24),
                        _SummaryRow(
                          label: 'Total a pagar',
                          value: totalToPay,
                          isStrong: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Escolha o método de pagamento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                ...paymentOptions.map(
                  (option) => _PaymentOptionTile(
                    option: option,
                    groupValue: _selectedMethod,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMethod = value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing
                    ? null
                    : () => _confirmPayment(context, totalToPay),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar pagamento'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(BuildContext context, double amount) async {
    if (_isProcessing) return;

    if (kIsWeb && _selectedMethod == PaymentMethod.card) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Card payments are currently supported only on mobile devices.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final paymentService = PaymentService();
    bool success = true;

    switch (_selectedMethod) {
      case PaymentMethod.card:
        success = await paymentService.payWithCard(amount);
        break;
      case PaymentMethod.mbway:
        success = await paymentService.payWithMBWay(amount);
        break;
      case PaymentMethod.cash:
        success = await paymentService.payWithCash(amount);
        break;
    }

    if (!mounted) return;

    if (!success) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento não pôde ser concluído.')),
      );
      return;
    }

    final cartStore = context.read<CartStore>();
    final orderStore = context.read<OrderStore>();
    final authStore = context.read<AuthStore>();
    final ordered = await cartStore.finishOrder(
      orderStore,
      paymentMethod: _selectedMethod,
      clientPhone: authStore.currentClient?.phone,
      customerName: authStore.currentClient?.name,
    );

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (!ordered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível criar o pedido. Tente novamente.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pagamento efetuado com sucesso.')),
    );
    Navigator.pop(context, true);
  }
}

class _PaymentOption {
  const _PaymentOption({
    required this.method,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final PaymentMethod method;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.option,
    required this.groupValue,
    required this.onChanged,
  });

  final _PaymentOption option;
  final PaymentMethod groupValue;
  final ValueChanged<PaymentMethod?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = option.method == groupValue;
    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: RadioListTile<PaymentMethod>(
        value: option.method,
        groupValue: groupValue,
        onChanged: onChanged,
        title: Text(option.title),
        subtitle: Text(option.subtitle),
        secondary: Icon(option.icon),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  final String label;
  final double value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isStrong ? FontWeight.bold : FontWeight.normal,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textStyle),
          Text('€${value.toStringAsFixed(2)}', style: textStyle),
        ],
      ),
    );
  }
}
