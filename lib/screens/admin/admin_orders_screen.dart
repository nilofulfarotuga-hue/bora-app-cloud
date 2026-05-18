import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/admin/test_order_badge.dart';
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
  // T1.1: filter by payment method including 'mixed' (wallet/tokens applied).
  String _paymentFilter = 'all';
  // 7-alpha-ADMIN-FILTER: filtro is_test_order. Default 'real' (so reais).
  String _filtroTeste = 'real';
  // PROMPT C (2026-05-14, PT-BR) — filtro por tipo de serviço.
  // 'all', 'delivery' (restaurant/storeShopping/carryGroceries/sendPackage),
  // 'takeaway'.
  String _serviceTypeFilter = 'all';

  static const _paymentOptions = <(String, String)>[
    ('all', 'Todos'),
    ('card', 'Cartão'),
    ('mbway', 'MBWay'),
    ('cash', 'Dinheiro'),
    ('mixed', 'Misto (carteira/tokens)'),
  ];

  static const _statusOptions = [
    ('all', 'Todos'),
    ('created', 'Criado'),
    ('preparing', 'Preparando'),
    ('readyForPickup', 'Pronto para retirada'),
    ('callingDriver', 'Chamando'),
    ('driverAccepted', 'Aceito'),
    ('pickedUp', 'Coletado'),
    ('onTheWay', 'A caminho'),
    ('delivered', 'Entregue'),
    ('rejected', 'Rejeitado'),
  ];

  static const _serviceTypeOptions = <(String, String)>[
    ('all', 'Todos'),
    ('delivery', 'Entrega'),
    ('takeaway', 'Takeaway'),
  ];

  static const _testOptions = <(String, String)>[
    ('real', 'Pedidos reais'),
    ('test', 'Apenas teste'),
    ('all', 'Todos'),
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
      // T1.1: extra cols for payment breakdown column.
      // 7-alpha-ADMIN-FILTER: include is_test_order para badge inline.
      // PROMPT C: include service_type + takeaway_pickup_code para filtro
      // e coluna "Código retirada".
      var base = Supabase.instance.client.from('orders').select(
          'id, status, payment_method, payment_status, price, created_at, '
          'vendor_name, assigned_driver_id, customer_name, service_type, '
          'takeaway_pickup_code, '
          'wallet_applied_cents, tokens_applied_count, tokens_applied_value_cents, '
          'stripe_charge_cents, is_test_order');
      var query = _statusFilter == 'all' ? base : base.eq('status', _statusFilter);
      if (_paymentFilter != 'all') {
        // 'mixed' covers any order with wallet OR tokens applied.
        if (_paymentFilter == 'mixed') {
          query = query.or('wallet_applied_cents.gt.0,tokens_applied_count.gt.0');
        } else {
          query = query.eq('payment_method', _paymentFilter);
        }
      }
      // 7-alpha-ADMIN-FILTER: filtra is_test_order conforme estado.
      if (_filtroTeste == 'real') {
        query = query.eq('is_test_order', false);
      } else if (_filtroTeste == 'test') {
        query = query.eq('is_test_order', true);
      }
      // PROMPT C — filtro por tipo de serviço (PT-BR).
      if (_serviceTypeFilter == 'takeaway') {
        query = query.eq('service_type', 'takeaway');
      } else if (_serviceTypeFilter == 'delivery') {
        query = query.neq('service_type', 'takeaway');
      }
      // 'all' = sem filtro is_test_order.
      final data =
          await query.order('created_at', ascending: false).limit(100);
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
      case 'readyForPickup':
        return Colors.green; // takeaway pronto
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
      'preparing': 'Preparando',
      'readyForPickup': 'Pronto para retirada',
      'callingDriver': 'Chamando entregador',
      'driverAccepted': 'Entregador aceito',
      'pickedUp': 'Coletado',
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
          // Filter chips: status
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
          // T1.1 Filter chips: payment method
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _paymentOptions.map((opt) {
                final isSelected = _paymentFilter == opt.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt.$2,
                        style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: Colors.purple.withValues(alpha: 0.15),
                    checkmarkColor: Colors.purple,
                    onSelected: (_) {
                      setState(() => _paymentFilter = opt.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // 7-alpha-ADMIN-FILTER: chips de filtro is_test_order (3 estados).
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _testOptions.map((opt) {
                final isSelected = _filtroTeste == opt.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt.$2,
                        style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: Colors.orange.withValues(alpha: 0.18),
                    checkmarkColor: Colors.orange.shade800,
                    onSelected: (_) {
                      setState(() => _filtroTeste = opt.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // PROMPT C (PT-BR) — chips de tipo de serviço (Entrega/Takeaway/Todos)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _serviceTypeOptions.map((opt) {
                final isSelected = _serviceTypeFilter == opt.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt.$2,
                        style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: Colors.teal.withValues(alpha: 0.18),
                    checkmarkColor: Colors.teal.shade800,
                    onSelected: (_) {
                      setState(() => _serviceTypeFilter = opt.$1);
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
                        ? const Center(child: Text('Nenhum pedido'))
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
                                            // 7-alpha-ADMIN-FILTER: badge teste inline.
                                            if (o['is_test_order'] == true) ...[
                                              const SizedBox(width: 6),
                                              const TestOrderBadge(compact: true),
                                              const SizedBox(width: 6),
                                            ],
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
                                        // T1.1: payment breakdown badges
                                        _PaymentBreakdownBadges(order: o),
                                        // PROMPT C — código de retirada (PT-BR)
                                        // Aparece apenas quando service_type='takeaway'
                                        // e takeaway_pickup_code está presente.
                                        if (o['service_type'] == 'takeaway' &&
                                            (o['takeaway_pickup_code']
                                                    as String? ??
                                                    '')
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 2),
                                            child: Text(
                                              'Código retirada: ${o['takeaway_pickup_code']}',
                                              style: TextStyle(
                                                  color: Colors.green.shade800,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600),
                                            ),
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

// T1.1: Payment breakdown badges shown inline in admin order list.
class _PaymentBreakdownBadges extends StatelessWidget {
  const _PaymentBreakdownBadges({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final wallet = (order['wallet_applied_cents'] as num?)?.toInt() ?? 0;
    final tokensCount = (order['tokens_applied_count'] as num?)?.toInt() ?? 0;
    final tokensValue =
        (order['tokens_applied_value_cents'] as num?)?.toInt() ?? 0;
    final stripe = (order['stripe_charge_cents'] as num?)?.toInt() ?? 0;

    if (wallet == 0 && tokensCount == 0 && stripe == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (wallet > 0)
            _badge('wallet €${(wallet / 100).toStringAsFixed(2)}',
                Colors.green),
          if (tokensCount > 0)
            _badge('$tokensCount tokens (€${(tokensValue / 100).toStringAsFixed(2)})',
                Colors.deepPurple),
          if (stripe > 0)
            _badge('Stripe €${(stripe / 100).toStringAsFixed(2)}', Colors.blue),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
