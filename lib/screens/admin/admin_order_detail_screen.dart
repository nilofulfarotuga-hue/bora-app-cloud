import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '_admin_cancel_order_dialog.dart';
import 'admin_chat_viewer_screen.dart';

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
              'driver_earnings, customer_total, '
              // FAVORES (errand) — campos do favor + foto + valor real
              'service_type, errand_description, errand_location, '
              'errand_speed, errand_home_stop, errand_estimated_purchase_cents, '
              'errand_home_stop_address, errand_home_stop_reason, '
              'errand_home_stop_cash_cents, errand_return_leg, errand_leg, '
              'final_purchase_value, errand_request_photo_url')
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Text(_order != null
            ? 'Pedido #${(_order!['id'] as String).substring(0, 8)}'
            : 'Pedido'),
        actions: [
          // M11: viewer read-only da conversa do pedido (audit no acesso).
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Ver conversa',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminChatViewerScreen(orderId: widget.orderId),
              ),
            ),
          ),
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
                    _SummaryTab(
                      order: _order!,
                      onCancel: _openCancelDialog,
                      onReassigned: _refresh,
                    ),
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
  const _SummaryTab({
    required this.order,
    required this.onCancel,
    required this.onReassigned,
  });
  final Map<String, dynamic> order;
  final VoidCallback onCancel;
  final VoidCallback onReassigned;

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
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
                // FAVORES (errand) — bloco específico do favor (PT-BR admin).
                if (order['service_type'] == 'errand') ...[
                  const Divider(),
                  _row(Icons.assignment_outlined, 'Favor',
                      order['errand_description'] ?? '—'),
                  _row(Icons.place_outlined, 'Local',
                      order['errand_location'] ?? '—'),
                  _row(Icons.flash_on, 'Velocidade',
                      order['errand_speed'] ?? '—'),
                  // Parte 9 (rodada 2) — paragem em casa completa (PT-BR).
                  if (order['errand_home_stop'] == true) ...[
                    _row(Icons.house_outlined, 'Passa em casa',
                        order['errand_home_stop_address'] ?? 'Sim (sem morada)'),
                    if (order['errand_home_stop_reason'] != null)
                      _row(Icons.info_outline, 'Motivo da parada',
                          order['errand_home_stop_reason'].toString()),
                    if (order['errand_home_stop_cash_cents'] != null &&
                        (order['errand_home_stop_cash_cents'] as num) > 0)
                      _row(Icons.payments_outlined, 'Dinheiro a pegar em casa',
                          '€${((order['errand_home_stop_cash_cents'] as num) / 100).toStringAsFixed(2)}'),
                    _row(Icons.replay, 'Perna de volta',
                        order['errand_return_leg'] == true ? 'Sim' : 'Não'),
                    _row(
                        Icons.timeline,
                        'Estado da perna',
                        switch ((order['errand_leg'] as num?)?.toInt() ?? 0) {
                          1 => 'Em casa do cliente',
                          2 => 'No local do favor',
                          3 => 'De volta a casa',
                          _ => 'Por iniciar',
                        }),
                  ],
                  _row(
                      Icons.shopping_bag_outlined,
                      'Compra estimada',
                      order['errand_estimated_purchase_cents'] != null
                          ? '€${((order['errand_estimated_purchase_cents'] as num) / 100).toStringAsFixed(2)}'
                          : '—'),
                  _row(
                      Icons.receipt_long,
                      'Valor real (recibo)',
                      order['final_purchase_value'] != null
                          ? '€${(order['final_purchase_value'] as num).toStringAsFixed(2)}'
                          : '—'),
                  if (order['errand_request_photo_url'] != null &&
                      (order['errand_request_photo_url'] as String).isNotEmpty)
                    _row(Icons.photo_camera_outlined, 'Foto do cliente',
                        'Sim (anexada)'),
                ],
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
          // P8 (2026-08-17) — Reatribuir estafeta. Só em pedido ativo (não
          // terminal). Chama a RPC admin_reassign_order (user_id, offer limpo,
          // notifica o novo estafeta, auditoria). A lista de elegíveis vem de
          // admin_live_drivers (online, aprovado).
          if (_canReassign) ...[
            const SizedBox(height: 8),
            _ReassignButton(
              orderId: order['id'] as String,
              onDone: onReassigned,
            ),
          ],
        ],
      ),
    );
  }

  /// Reatribuir só faz sentido enquanto há entrega por concluir (do momento em
  /// que se chama estafeta até estar a caminho).
  bool get _canReassign {
    final status = order['status'] as String? ?? '';
    return const [
      'callingDriver',
      'driverAccepted',
      'pickedUp',
      'onTheWay',
    ].contains(status);
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
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
        _CashBreakdownCard(
          orderId: order['id'] as String,
          paymentMethod: method,
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

// Bloco "Acerto de Caixa" — chama admin_order_cash_breakdown(p_order_id) e só
// aparece para pagamento em dinheiro ou quando há talão de loja (>0).
class _CashBreakdownCard extends StatefulWidget {
  const _CashBreakdownCard({required this.orderId, required this.paymentMethod});
  final String orderId;
  final String? paymentMethod;

  @override
  State<_CashBreakdownCard> createState() => _CashBreakdownCardState();
}

class _CashBreakdownCardState extends State<_CashBreakdownCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _permissionError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_order_cash_breakdown',
        params: {'p_order_id': widget.orderId},
      );
      Map<String, dynamic>? map;
      if (res is Map) {
        map = Map<String, dynamic>.from(res);
      } else if (res is List && res.isNotEmpty && res.first is Map) {
        map = Map<String, dynamic>.from(res.first as Map);
      }
      if (!mounted) return;
      setState(() {
        _data = map;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _permissionError = true;
      });
    }
  }

  double _num(String key) {
    final v = _data?[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  bool _bool(String key) => _data?[key] == true;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    final isCash = widget.paymentMethod == 'cash';

    if (_permissionError) {
      if (!isCash) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Acerto de caixa indisponível (sem permissão).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    final talao = _num('talao_loja');
    if (_data == null || (!isCash && talao <= 0)) {
      return const SizedBox.shrink();
    }

    final lucroBora = _num('lucro_bora');
    final gap = _num('gap_preco_catalogo');
    final direcao = _data!['direcao'] as String? ??
        (_bool('bora_deve_ao_estafeta')
            ? 'Bora deve ao entregador'
            : _bool('estafeta_deve_a_bora')
                ? 'Entregador deve à Bora'
                : 'Quitado');

    String eur(double v) => '€${v.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.point_of_sale, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Acerto de Caixa',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              _kv('Cliente pagou', eur(_num('cliente_pagou'))),
              _kv('Produtos', eur(_num('produtos'))),
              _kv('Entrega', eur(_num('entrega'))),
              _kv('Taxa de serviço', eur(_num('taxa_servico'))),
              _kv('Sacos', eur(_num('sacos'))),
              _kv('Ganho do entregador', eur(_num('ganho_estafeta'))),
              _kv('Valor do talão da loja', eur(talao)),
              const Divider(),
              _kv('Saldo do entregador', eur(_num('saldo_estafeta'))),
              _kv('Direção', direcao),
              _kv('Lucro da Bora', eur(lucroBora),
                  valueColor: lucroBora < 0 ? AppColors.error : null),
              if (gap != 0)
                _kv('Diferença de preço do catálogo', eur(gap),
                    valueColor: gap > 0 ? AppColors.error : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 170,
          child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
        ),
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
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.divider),
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

/// P8 (2026-08-17) — botão + fluxo de "Reatribuir estafeta" no admin (PT-BR).
/// Lista os estafetas elegíveis (RPC admin_live_drivers: online + aprovado),
/// pede confirmação e chama admin_reassign_order. A RPC faz o padrão provado:
/// assigned_driver_id = user_id do novo, offer limpo, notifica, auditoria.
class _ReassignButton extends StatefulWidget {
  const _ReassignButton({required this.orderId, required this.onDone});
  final String orderId;
  final VoidCallback onDone;

  @override
  State<_ReassignButton> createState() => _ReassignButtonState();
}

class _ReassignButtonState extends State<_ReassignButton> {
  bool _busy = false;

  Future<void> _abrir() async {
    setState(() => _busy = true);
    List<Map<String, dynamic>> elegiveis = const [];
    try {
      final res =
          await Supabase.instance.client.rpc('admin_live_drivers');
      if (res is List) {
        elegiveis = res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {/* lista vazia — o diálogo mostra o aviso */}
    if (!mounted) return;
    setState(() => _busy = false);

    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReassignSheet(drivers: elegiveis),
    );
    if (escolhido == null || !mounted) return;

    final novoId = (escolhido['user_id'] ?? escolhido['driver_id'] ??
            escolhido['id'])
        ?.toString();
    if (novoId == null || novoId.isEmpty) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_reassign_order',
        params: {
          'p_order_id': widget.orderId,
          'p_new_driver': novoId,
          'p_motivo': 'reatribuído pelo admin no painel',
        },
      );
      final data = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (!mounted) return;
      setState(() => _busy = false);
      if (data['ok'] == true) {
        messenger.showSnackBar(SnackBar(
            content: Text(
                'Pedido reatribuído a ${data['estafeta'] ?? 'estafeta'}. Notificação enviada.')));
        widget.onDone();
      } else {
        messenger.showSnackBar(SnackBar(
            content: Text('Não foi possível reatribuir: ${data['error'] ?? 'erro'}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Erro ao reatribuir: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      icon: _busy ? Icons.hourglass_top : Icons.published_with_changes,
      label: _busy ? 'A reatribuir…' : 'Reatribuir estafeta',
      color: AppColors.primary,
      enabled: !_busy,
      onTap: _abrir,
    );
  }
}

/// Folha de seleção do novo estafeta (elegíveis = online + aprovado).
class _ReassignSheet extends StatelessWidget {
  const _ReassignSheet({required this.drivers});
  final List<Map<String, dynamic>> drivers;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Reatribuir a…',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Estafetas online e aprovados.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            if (drivers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhum estafeta online no momento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: drivers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = drivers[i];
                    final nome = (d['driver_name'] ?? d['name'] ?? 'Estafeta')
                        .toString();
                    final tel =
                        (d['driver_phone'] ?? d['phone'] ?? '').toString();
                    return ListTile(
                      leading: const Icon(Icons.two_wheeler,
                          color: AppColors.primary),
                      title: Text(nome),
                      subtitle: tel.isNotEmpty ? Text(tel) : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, d),
                    );
                  },
                ),
              ),
          ],
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

