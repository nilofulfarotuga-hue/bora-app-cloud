import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '_admin_cancel_order_dialog.dart';

/// Full-screen admin detail for an order. Pushed from `admin_orders_screen`
/// (FASE 4 BUG 3 F1.D). 4 tabs:
///   1. Resumo  — info + status badge + acção Cancelar (se estado activo)
///   2. Items   — lista de produtos (read-only)
///   3. Pagamento — método, status, refund info
///   4. Timeline — admin_audit_log filtrado por entity_id desta ordem
class AdminOrderDetailScreen extends StatefulWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('orders')
          .select(
              'id, status, payment_method, payment_status, payment_intent_id, '
              'price, total, final_total, cash_total_due, vendor_name, restaurant_id, user_id, '
              'assigned_driver_id, items, items_added, '
              'dropoff_address, pickup_address, '
              'cancel_reason, cancelled_at, '
              'cancelled_by, cancellation_initiator, cancellation_reason_code, '
              'refund_id, refund_status, refund_amount, refund_method, '
              'refunded_at, created_at, '
              // T1.1: payment breakdown columns
              'wallet_applied_cents, tokens_applied_count, '
              'tokens_applied_value_cents, stripe_charge_cents, '
              // FASE 3 admin cash display
              'driver_earnings, customer_total')
          .eq('id', widget.orderId)
          .maybeSingle();

      if (data == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Pedido não encontrado.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _order = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erro a carregar: $e';
        });
      }
    }
  }

  Future<void> _openCancelDialog() async {
    if (_order == null) return;
    final result = await showDialog(
      context: context,
      builder: (_) => AdminCancelOrderDialog(order: _order!),
    );
    if (result != null && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_order != null
            ? 'Pedido #${(_order!['id'] as String).substring(0, 8)}'
            : 'Pedido'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Resumo'),
            Tab(text: 'Items'),
            Tab(text: 'Pagamento'),
            Tab(text: 'Timeline'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _SummaryTab(order: _order!, onCancel: _openCancelDialog),
                    _ItemsTab(order: _order!),
                    _PaymentTab(order: _order!),
                    _TimelineTab(orderId: widget.orderId),
                  ],
                ),
    );
  }
}

// ── TAB 1 — Resumo ──────────────────────────────────────────────────────────

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.order, required this.onCancel});
  final Map<String, dynamic> order;
  final VoidCallback onCancel;

  bool get _canCancel {
    final status = order['status'] as String? ?? '';
    return !['delivered', 'cancelled', 'rejected'].contains(status);
  }

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? '';
    final created = DateTime.tryParse(order['created_at'] as String? ?? '');
    final cancelled = DateTime.tryParse(order['cancelled_at'] as String? ?? '');
    final initiator = order['cancellation_initiator'] as String?;
    final reasonCode = order['cancellation_reason_code'] as String?;
    final cancelReason = order['cancel_reason'] as String?;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(order['vendor_name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  _StatusBadge(status: status),
                ]),
                const SizedBox(height: 8),
                Text(
                  'ID: ${order['id']}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                if (created != null)
                  Text('Criado: ${_fmtDate(created)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (cancelled != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Cancelado em ${_fmtDate(cancelled)}'
                    '${initiator != null ? " (por $initiator)" : ""}',
                    style: const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                  if (reasonCode != null)
                    Text('Categoria: $reasonCode',
                        style: const TextStyle(fontSize: 12)),
                  if (cancelReason != null && cancelReason.isNotEmpty)
                    Text('Motivo: $cancelReason',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                _row(Icons.person_outline, 'Cliente', order['user_id']),
                _row(Icons.two_wheeler, 'Entregador', order['assigned_driver_id'] ?? '—'),
                _row(Icons.store, 'Restaurante (FK)', order['restaurant_id'] ?? '—'),
                _row(Icons.location_on, 'Entrega',
                    order['dropoff_address'] ?? '—'),
                _row(Icons.store_mall_directory, 'Recolha',
                    order['pickup_address'] ?? '—'),
                _row(Icons.euro, 'Total', '€${_amount(order)}'),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Text('Acções', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.cancel,
            label: 'Cancelar pedido',
            color: AppColors.error,
            enabled: _canCancel,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
        Expanded(child: Text(value?.toString() ?? '—', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ── TAB 2 — Items ───────────────────────────────────────────────────────────

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final items = order['items'];
    final itemsAdded = order['items_added'];
    final canonical = items is List ? items : <dynamic>[];
    final added = itemsAdded is List ? itemsAdded : <dynamic>[];

    if (canonical.isEmpty && added.isEmpty) {
      return const Center(child: Text('Sem items registados.'));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (canonical.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Items do pedido',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          for (final raw in canonical)
            if (raw is Map) _buildCanonicalRow(Map<String, dynamic>.from(raw)),
        ],
        if (added.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.add_box_outlined,
                    size: 18, color: Colors.blue),
                const SizedBox(width: 6),
                Text('Adicionados pelo entregador (${added.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.blue)),
              ],
            ),
          ),
          for (final raw in added)
            if (raw is Map) _buildAddedRow(Map<String, dynamic>.from(raw)),
        ],
      ],
    );
  }

  Widget _buildCanonicalRow(Map<String, dynamic> m) {
    final qty = m['qty'] ?? m['quantity'] ?? 1;
    final name = m['name'] ?? m['title'] ?? '—';
    final price = m['price'] ?? m['line_total'];
    final status = m['purchaseStatus'] ?? m['purchase_status'];
    Color? bg;
    Widget? leadingIcon;
    if (status == 'bought') {
      bg = Colors.green.shade50;
      leadingIcon = const Icon(Icons.check_circle,
          color: Colors.green, size: 20);
    } else if (status == 'unavailable') {
      bg = Colors.red.shade50;
      leadingIcon = const Icon(Icons.cancel, color: Colors.red, size: 20);
    }
    return Container(
      color: bg,
      child: ListTile(
        dense: true,
        leading: leadingIcon ??
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text('${qty}x', style: const TextStyle(fontSize: 11)),
            ),
        title: Text(name.toString(),
            style: TextStyle(
              decoration: status == 'unavailable'
                  ? TextDecoration.lineThrough
                  : null,
            )),
        subtitle: status != null
            ? Text(status.toString(),
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: price != null
            ? Text('$qty× €${(price as num).toStringAsFixed(2)}')
            : null,
      ),
    );
  }

  Widget _buildAddedRow(Map<String, dynamic> m) {
    final name = m['name'] ?? '—';
    final qty = (m['qty'] as num?)?.toInt() ?? 1;
    final baseCents = (m['price_base_cents'] as num?)?.toInt() ?? 0;
    final finalCents = (m['price_final_cents'] as num?)?.toInt() ?? baseCents;
    final reason = m['reason'] as String? ?? 'driver_substitution';
    final addedAt = m['added_at'] as String?;
    return Container(
      color: Colors.blue.shade50,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.add_box, color: Colors.blue, size: 20),
        title: Text(name.toString()),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Base €${(baseCents / 100).toStringAsFixed(2)}'
                ' · Cliente €${(finalCents / 100).toStringAsFixed(2)} (×$qty)',
                style: const TextStyle(fontSize: 11)),
            Text('$reason${addedAt != null ? " · $addedAt" : ""}',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade700)),
          ],
        ),
        trailing: Text('€${(finalCents * qty / 100).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── TAB 3 — Pagamento ───────────────────────────────────────────────────────

class _PaymentTab extends StatelessWidget {
  const _PaymentTab({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final method = order['payment_method'] as String?;
    final paymentStatus = order['payment_status'] as String?;
    final pi = order['payment_intent_id'] as String?;
    final refundStatus = order['refund_status'] as String?;
    final refundId = order['refund_id'] as String?;
    final refundAmount = (order['refund_amount'] as num?)?.toDouble();
    final refundedAt = DateTime.tryParse(order['refunded_at'] as String? ?? '');

    // T1.1: payment breakdown
    final wallet = (order['wallet_applied_cents'] as num?)?.toInt() ?? 0;
    final tokensCount = (order['tokens_applied_count'] as num?)?.toInt() ?? 0;
    final tokensValue =
        (order['tokens_applied_value_cents'] as num?)?.toInt() ?? 0;
    final stripeCents = (order['stripe_charge_cents'] as num?)?.toInt() ?? 0;
    final priceCents = (((order['price'] as num?) ?? 0) * 100).round();
    final hasMixedPayment = wallet > 0 || tokensCount > 0;

    // FASE 3 — cash collected display
    final orderStatus = order['status'] as String? ?? '';
    final isCash = method == 'cash';
    final isDelivered = orderStatus == 'delivered';
    // Sessão 3: cash_total_due tem prioridade quando NOT NULL (inclui sacos
    // mercado pós-finalização). Fallback histórico para final_total/price.
    final cashCollected = (order['cash_total_due'] as num?)?.toDouble() ??
        (order['customer_total'] as num?)?.toDouble() ??
        (order['final_total'] as num?)?.toDouble() ??
        (order['price'] as num?)?.toDouble() ??
        0;
    final driverEarnings =
        (order['driver_earnings'] as num?)?.toDouble() ?? 0;
    // Cash adjustment = montante que driver deve à Bora no settlement
    // (driver recebeu cash do cliente; Bora paga driver_earnings).
    final cashAdjustment = cashCollected - driverEarnings;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Pagamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _row('Método', method ?? '—'),
              _row('Estado', paymentStatus ?? '—'),
              _row('Total', '€${_amount(order)}'),
              if (pi != null) _row('Stripe PI', pi),
            ]),
          ),
        ),
        // FASE 3: Cash entregue — só aparece se cash + delivered
        if (isCash && isDelivered) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('💵', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text('Cash entregue',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _row('Valor recebido pelo entregador',
                      '€${cashCollected.toStringAsFixed(2)}'),
                  _row('Driver earnings',
                      '€${driverEarnings.toStringAsFixed(2)}'),
                  const Divider(),
                  _row(
                    'Cash adjustment (driver → Bora)',
                    '€${cashAdjustment.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Settlement diário processa automaticamente.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
        // T1.1: Detalhe pagamento (decomposed components)
        if (hasMixedPayment) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.purple.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Detalhe pagamento',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _row('Total bruto',
                      '€${(priceCents / 100).toStringAsFixed(2)}'),
                  if (wallet > 0)
                    _row('Saldo Bora aplicado',
                        '€${(wallet / 100).toStringAsFixed(2)}'),
                  if (tokensCount > 0)
                    _row('Tokens aplicados',
                        '$tokensCount tokens (€${(tokensValue / 100).toStringAsFixed(2)})'),
                  if (stripeCents > 0)
                    _row('Cartão / MBWay',
                        '€${(stripeCents / 100).toStringAsFixed(2)}'),
                  const Divider(),
                  _row(
                    'Soma componentes',
                    '€${((wallet + tokensValue + stripeCents) / 100).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          color: refundStatus == 'failed'
              ? AppColors.error.withValues(alpha: 0.05)
              : refundStatus == 'succeeded'
                  ? AppColors.success.withValues(alpha: 0.05)
                  : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reembolso', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _row('Estado', refundStatus ?? '—'),
              if (refundAmount != null) _row('Valor', '€${refundAmount.toStringAsFixed(2)}'),
              if (refundId != null) _row('Stripe Refund', refundId),
              if (refundedAt != null) _row('Data', _fmtDate(refundedAt)),
              if (refundStatus == 'failed') ...[
                const SizedBox(height: 8),
                const Text(
                  '⚠️ Refund falhou — verifica Stripe Dashboard manualmente.',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ── TAB 4 — Timeline ────────────────────────────────────────────────────────

class _TimelineTab extends StatefulWidget {
  const _TimelineTab({required this.orderId});
  final String orderId;
  @override
  State<_TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<_TimelineTab> {
  late Future<List<Map<String, dynamic>>> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .from('admin_audit_log')
        .select('id, action, admin_email, details, created_at')
        .eq('entity_type', 'order')
        .eq('entity_id', widget.orderId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        final entries = snap.data ?? const [];
        if (entries.isEmpty) {
          return const Center(child: Text('Sem entradas de audit.'));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = entries[i];
              final at = DateTime.tryParse(e['created_at'] as String? ?? '');
              final details = e['details'] as Map<String, dynamic>?;
              final summary = details == null ? '' : _summariseDetails(details);
              return ListTile(
                leading: Icon(_iconFor(e['action'] as String?), color: AppColors.primary, size: 20),
                title: Text(e['action'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${e['admin_email'] ?? '—'}${summary.isEmpty ? '' : '\n$summary'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(at == null ? '—' : _fmtDate(at),
                    style: const TextStyle(fontSize: 11)),
                isThreeLine: summary.isNotEmpty,
              );
            },
          ),
        );
      },
    );
  }

  IconData _iconFor(String? action) {
    if (action == null) return Icons.history;
    if (action == 'order_cancel' || action == 'order_cancel_complete') return Icons.cancel;
    if (action == 'order_cancel_idempotent') return Icons.repeat;
    if (action.startsWith('order_refund')) return Icons.attach_money;
    return Icons.history;
  }

  String _summariseDetails(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['previous_status'] != null) parts.add('prev=${d['previous_status']}');
    if (d['reason_code'] != null) parts.add('cat=${d['reason_code']}');
    if (d['reason'] != null) parts.add('"${d['reason']}"');
    if (d['refund_result'] != null) {
      final amt = d['refund_amount'];
      parts.add('refund=${d['refund_result']}${amt != null ? " €$amt" : ""}');
    }
    if (d['notifications'] != null) {
      final n = d['notifications'] as Map?;
      if (n != null) {
        final ok = n.entries.where((e) => (e.value as Map?)?['ok'] == true).length;
        parts.add('notify=$ok/${n.length}');
      }
    }
    if (d['attempted_reason_code'] != null) parts.add('attempted=${d['attempted_reason_code']}');
    return parts.join(' · ');
  }
}

// ── Helpers / shared widgets ───────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'created'        => ('Criado', Colors.grey),
      'preparing'      => ('A preparar', Colors.amber),
      'callingDriver'  => ('A chamar entregador', Colors.orange),
      'driverAccepted' => ('Aceite', Colors.blue),
      'pickedUp'       => ('Recolhido', Colors.purple),
      'onTheWay'       => ('A caminho', Colors.purple),
      'delivered'      => ('Entregue', AppColors.success),
      'cancelled'      => ('Cancelado', AppColors.error),
      'rejected'       => ('Rejeitado', Colors.red.shade900),
      _                => (status, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: enabled ? (color ?? AppColors.primary) : Colors.black26),
        title: Text(label,
            style: TextStyle(
                color: enabled ? AppColors.textPrimary : Colors.black38,
                fontWeight: FontWeight.w600)),
        onTap: enabled ? onTap : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
         '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _amount(Map<String, dynamic> order) {
  final v = order['total'] ?? order['final_total'] ?? order['price'];
  if (v is num) return v.toStringAsFixed(2);
  return '0.00';
}

