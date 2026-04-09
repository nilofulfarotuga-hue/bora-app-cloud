import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import 'chat_screen.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final OrderModel order;

  /// Short code shown to the client: first 6 chars of UUID, uppercase.
  String get _orderCode => '#${order.id.replaceAll('-', '').substring(0, 6).toUpperCase()}';


  @override
  Widget build(BuildContext context) {
    // Watch live order so status updates in real time.
    final orderStore = context.watch<OrderStore>();
    final liveOrder = orderStore.orders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );

    final hasDriver = liveOrder.assignedDriverId != null &&
        liveOrder.status.index >= OrderStatus.driverAccepted.index;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido $_orderCode'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status card ───────────────────────────────────────────────
          _StatusCard(order: liveOrder),

          const SizedBox(height: 16),

          // ── Driver card (only when assigned) ─────────────────────────
          if (hasDriver) ...[
            _DriverCard(
              order: liveOrder,
              onChat: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    order: liveOrder,
                    senderType: ChatSenderType.client,
                  ),
                ),
              ),
              onCall: () => _callPhone(context, liveOrder.driverPhone ?? ''),
            ),
            const SizedBox(height: 16),
          ],

          // ── Order info card ───────────────────────────────────────────
          _OrderInfoCard(order: liveOrder),

          const SizedBox(height: 16),

          // ── Codes card ────────────────────────────────────────────────
          _CodesCard(orderCode: _orderCode, deliveryCode: order.deliveryCode),

          const SizedBox(height: 16),

          // ── Address card ──────────────────────────────────────────────
          _AddressCard(order: liveOrder),

          if (liveOrder.customerNotes != null &&
              liveOrder.customerNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _NotesCard(notes: liveOrder.customerNotes!),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _callPhone(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
      );
    }
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final OrderModel order;

  Color get _statusColor {
    switch (order.status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
        return Colors.orange;
      case OrderStatus.callingDriver:
        return Colors.blue;
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return Colors.green;
      case OrderStatus.delivered:
        return Colors.green.shade700;
      case OrderStatus.rejected:
        return Colors.red;
    }
  }

  IconData get _statusIcon {
    switch (order.status) {
      case OrderStatus.created:
        return Icons.receipt_long_outlined;
      case OrderStatus.preparing:
        return Icons.soup_kitchen_outlined;
      case OrderStatus.callingDriver:
        return Icons.search_outlined;
      case OrderStatus.driverAccepted:
        return Icons.directions_bike_outlined;
      case OrderStatus.pickedUp:
        return Icons.shopping_bag_outlined;
      case OrderStatus.onTheWay:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.check_circle_outline;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_statusIcon, color: _statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado do pedido',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.status.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Driver card ───────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.order,
    required this.onChat,
    required this.onCall,
  });

  final OrderModel order;
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    // Resolve real driver name from DriverStore, fall back to phone on order.
    final driverStore = context.watch<DriverStore>();
    final resolvedDriver = order.assignedDriverId != null
        ? driverStore.getDriverById(order.assignedDriverId!)
        : null;
    final driverName = resolvedDriver?.name ??
        (order.driverPhone != null && order.driverPhone!.isNotEmpty
            ? 'Estafeta ${order.driverPhone}'
            : 'Estafeta');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'O teu estafeta',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Avatar placeholder
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  color: Colors.green.shade700,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((order.driverPhone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.driverPhone!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (order.driverPhone ?? '').isEmpty ? null : onCall,
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Ligar'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Chat'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Order info card ───────────────────────────────────────────────────────────

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Resumo do pedido',
      child: Column(
        children: [
          _Row(label: 'Serviço', value: order.serviceType.label),
          _Row(
              label: 'Total',
              value: '€${order.total.toStringAsFixed(2)}',
              bold: true),
          _Row(label: 'Taxa de entrega',
              value: '€${order.deliveryFee.toStringAsFixed(2)}'),
          _Row(
              label: 'Pagamento',
              value: order.paymentMethod.name.toUpperCase()),
          if (order.vendorName != null)
            _Row(label: 'Estabelecimento', value: order.vendorName!),
        ],
      ),
    );
  }
}

// ── Codes card ────────────────────────────────────────────────────────────────

class _CodesCard extends StatelessWidget {
  const _CodesCard({required this.orderCode, required this.deliveryCode});

  final String orderCode;
  final String deliveryCode;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Códigos',
      child: Column(
        children: [
          _CodeRow(
            label: 'Código do pedido',
            code: orderCode,
            icon: Icons.receipt_outlined,
          ),
          const SizedBox(height: 12),
          _CodeRow(
            label: 'Código de entrega',
            code: deliveryCode,
            icon: Icons.lock_outline,
            subtitle: 'Mostra este código ao estafeta na entrega',
          ),
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({
    required this.label,
    required this.code,
    required this.icon,
    this.subtitle,
  });

  final String label;
  final String code;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              Text(code,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label copiado')),
            );
          },
          tooltip: 'Copiar',
        ),
      ],
    );
  }
}

// ── Address card ──────────────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Endereços',
      child: Column(
        children: [
          if (order.pickupAddress != null && order.pickupAddress!.isNotEmpty)
            _AddressRow(
              icon: Icons.circle,
              iconColor: Colors.orange.shade600,
              label: 'Recolha',
              address: order.pickupAddress!,
            ),
          if (order.pickupAddress != null &&
              order.pickupAddress!.isNotEmpty &&
              order.dropoffAddress != null &&
              order.dropoffAddress!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Container(
                  height: 20, width: 2, color: Colors.grey.shade300),
            ),
          if (order.dropoffAddress != null && order.dropoffAddress!.isNotEmpty)
            _AddressRow(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFF1C6EF2),
              label: 'Entrega',
              address: order.dropoffAddress!,
            ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              Text(address,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Notes card ────────────────────────────────────────────────────────────────

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Notas',
      child: Row(
        children: [
          Icon(Icons.notes_rounded, color: Colors.grey.shade500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(notes,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}