import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '_admin_cancel_order_dialog.dart';
import 'admin_order_detail_screen.dart';

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

  /// Open cancel dialog (FASE 4 BUG 3 F1.B). Refresh list on success.
  Future<void> _cancel(Map<String, dynamic> order) async {
    final result = await showDialog(
      context: context,
      builder: (_) => AdminCancelOrderDialog(order: order),
    );
    if (result != null && mounted) {
      _load();
    }
  }

  /// Push the new full-screen detail (FASE 4 BUG 3 F1.D).
  void _openDetail(Map<String, dynamic> order) {
    final id = order['id'] as String?;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminOrderDetailScreen(orderId: id)),
    );
  }

  /// CSV export (B3). Shares via native sheet — admin can email/Drive/AirDrop.
  Future<void> _exportCsv() async {
    final headers = [
      'order_id',
      'created_at',
      'status',
      'service_type',
      'vendor_name',
      'customer_name',
      'price',
      'payment_method',
      'payment_status',
      'driver_id',
    ];
    final rows = _orders
        .map((o) => [
              o['id'] ?? '',
              o['created_at'] ?? '',
              o['status'] ?? '',
              o['service_type'] ?? '',
              o['vendor_name'] ?? '',
              o['customer_name'] ?? '',
              o['price'] ?? '',
              o['payment_method'] ?? '',
              o['payment_status'] ?? '',
              o['assigned_driver_id'] ?? '',
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    try {
      await AdminExportService.instance.exportCsv(
        filename: 'bora_pedidos_$stamp.csv',
        headers: headers,
        rows: rows,
        subject: 'Bora — Pedidos $stamp',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar: $e')),
      );
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
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar CSV',
            onPressed: _orders.isEmpty ? null : _exportCsv,
          ),
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
                                  child: InkWell(
                                    onTap: () => _openDetail(o),
                                    borderRadius: BorderRadius.circular(8),
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
                                              onPressed: () => _cancel(o),
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
