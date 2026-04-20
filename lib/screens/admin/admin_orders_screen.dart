import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

  static const _statusOptions = [
    ('all', 'Todos'),
    ('created', 'Criado'),
    ('preparing', 'A preparar'),
    ('callingDriver', 'A chamar'),
    ('driverAccepted', 'Aceite'),
    ('pickedUp', 'Recolhido'),
    ('onTheWay', 'A caminho'),
    ('delivered', 'Entregue'),
    ('rejected', 'Rejeitado'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var base = Supabase.instance.client.from('orders').select(
          'id, status, payment_method, price, created_at, vendor_name, assigned_driver_id');
      final data = _statusFilter == 'all'
          ? await base.order('created_at', ascending: false).limit(100)
          : await base
              .eq('status', _statusFilter)
              .order('created_at', ascending: false)
              .limit(100);
      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancel(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Cancelar pedido'),
        content: const Text('Tem a certeza que quer cancelar este pedido?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': 'rejected'}).eq('id', orderId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':
        return AppColors.primary;
      case 'rejected':
        return Colors.red;
      case 'driverAccepted':
      case 'pickedUp':
      case 'onTheWay':
        return Colors.blue;
      case 'callingDriver':
        return Colors.purple;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    const labels = {
      'created': 'Criado',
      'preparing': 'A preparar',
      'callingDriver': 'A chamar estafeta',
      'driverAccepted': 'Estafeta aceite',
      'pickedUp': 'Recolhido',
      'onTheWay': 'A caminho',
      'delivered': 'Entregue',
      'rejected': 'Rejeitado',
    };
    return labels[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Pedidos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _statusOptions.map((opt) {
                final isSelected = _statusFilter == opt.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt.$2),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primary,
                    onSelected: (_) {
                      setState(() => _statusFilter = opt.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Erro: $_error'))
                    : _orders.isEmpty
                        ? const Center(child: Text('Sem pedidos'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _orders.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final o = _orders[i];
                                final status = o['status'] as String? ?? '';
                                final canCancel =
                                    !['delivered', 'rejected'].contains(status);
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                o['vendor_name'] as String? ??
                                                    'Pedido',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 15),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _statusColor(status)
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                _statusLabel(status),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _statusColor(status),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '€${(o['price'] as num? ?? 0).toStringAsFixed(2)} · ${o['payment_method'] ?? '—'}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13),
                                        ),
                                        Text(
                                          'ID: ${(o['id'] as String).substring(0, 8).toUpperCase()}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12),
                                        ),
                                        if (canCancel) ...[
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  _cancel(o['id'] as String),
                                              icon: const Icon(
                                                  Icons.cancel_outlined,
                                                  size: 16,
                                                  color: Colors.red),
                                              label: const Text('Cancelar',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
