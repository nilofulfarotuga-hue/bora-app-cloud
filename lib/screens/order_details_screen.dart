import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../config/app_theme.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../services/wallet_service.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/errand_budget_banner.dart';
import '../widgets/private_bucket_image.dart';
import '../widgets/refund_choice_dialog.dart';
import 'chat_screen.dart';
import 'wallet_history_screen.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final OrderModel order;

  /// Short code shown to the client: first 6 chars of UUID, uppercase.
  String get _orderCode =>
      '#${order.id.replaceAll('-', '').substring(0, 6).toUpperCase()}';

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
      floatingActionButton: BoraSupportFab(orderId: order.id),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status card ───────────────────────────────────────────────
          _StatusCard(order: liveOrder),

          const SizedBox(height: 16),

          // ── 8.2 Banner de autorização de orçamento (errand pending) ───
          ErrandBudgetBanner(order: liveOrder),

          // ── Refund banner (F2 — clareza método de reembolso) ─────────
          if (liveOrder.status == OrderStatus.cancelled)
            _RefundBanner(order: liveOrder),

          // ── Cashback badge (F11 — só se delivered) ────────────────────
          if (liveOrder.status == OrderStatus.delivered)
            _CashbackBadge(orderId: liveOrder.id),

          // ── Driver card (only when assigned) ─────────────────────────
          if (hasDriver) ...[
            _DriverCard(
              order: liveOrder,
              onChat: () => Navigator.push(
                context,
                MaterialPageRoute(
                  // Card do estafeta → par cliente↔estafeta explícito (o
                  // fallback por status caía em client_partner no preparing).
                  builder: (_) => ChatScreen(
                    order: liveOrder,
                    senderType: ChatSenderType.client,
                    chatTarget: ChatTarget.driver,
                    conversationType: resolveConversationType(
                        ChatSenderType.client, liveOrder.status,
                        ChatTarget.driver),
                  ),
                ),
              ),
              onCall: () => _callPhone(context, liveOrder.driverPhone ?? ''),
            ),
            const SizedBox(height: 16),
          ],

          // ── Order info card ───────────────────────────────────────────
          _OrderInfoCard(order: liveOrder),

          // ── 8.3 Talão do favor (errand com compra) ───────────────────
          if (liveOrder.serviceType == OrderServiceType.errand &&
              liveOrder.errandHasPurchase) ...[
            const SizedBox(height: 16),
            _ErrandReceiptCard(order: liveOrder),
          ],

          // ── Items card (only when order has items) ──────────────────
          // BUG #4 (2026-05-12) — esconder em storeShopping V2 porque
          // _PurchaseV2Card abaixo já mostra items definitivos pós-finalize.
          if (liveOrder.items.isNotEmpty && liveOrder.purchaseFlowVersion != 2) ...[
            const SizedBox(height: 16),
            _ItemsCard(order: liveOrder),
          ],

          // ── BLOCO 3.7 close-TODOs — StoreShopping v2 badges/breakdown ─
          if (liveOrder.purchaseFlowVersion == 2) ...[
            const SizedBox(height: 16),
            _PurchaseV2Card(order: liveOrder),
          ],

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

          // ── Cancel order (F1 — refund choice) ──────────────────────────
          if (_isCancelable(liveOrder)) ...[
            const SizedBox(height: 16),
            _CancelOrderButton(order: liveOrder),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// True para tiers `before_dispatch` / `after_accept` / `after_pickup`.
  /// Status terminais (delivered/rejected/cancelled) não são canceláveis.
  bool _isCancelable(OrderModel o) {
    switch (o.status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return true;
      case OrderStatus.readyForPickup:
        // Takeaway pronto — cliente deve levantar; suporte humano trata
        // cancelamentos excepcionais.
        return false;
      case OrderStatus.delivered:
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return false;
    }
  }

  Future<void> _callPhone(BuildContext _ctx, String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (_ctx.mounted) {
      ScaffoldMessenger.of(_ctx).showSnackBar(
        const SnackBar(content: Text('Não foi possível iniciar a chamada.')),
      );
    }
  }
}

// ── Refund banner (F2 — clareza prazo) ────────────────────────────────────────

class _RefundBanner extends StatelessWidget {
  const _RefundBanner({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final refundEur = order.refundAmount ?? 0;
    if (refundEur <= 0) return const SizedBox.shrink();

    final method = order.refundMethod ?? 'stripe';
    final isWallet = method == 'wallet';
    final color = isWallet ? Colors.green.shade100 : Colors.amber.shade100;
    final border = isWallet ? Colors.green : Colors.amber.shade700;
    final icon = isWallet ? Icons.flash_on : Icons.access_time;
    final text = isWallet
        ? '€${refundEur.toStringAsFixed(2)} disponíveis no Saldo Bora — imediato.'
        : 'Reembolso em curso. Pode demorar 5-10 dias úteis a aparecer no cartão.';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: border),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Cashback badge (F11) ──────────────────────────────────────────────────────

class _CashbackBadge extends StatelessWidget {
  const _CashbackBadge({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('wallet_transactions')
          .select('amount_cents')
          .eq('related_order_id', orderId)
          .eq('kind', 'cashback')
          .limit(1)
          .then((r) => (r as List).map((e) => (e as Map).cast<String, dynamic>()).toList()),
      builder: (ctx, snap) {
        final rows = snap.data;
        if (rows == null || rows.isEmpty) return const SizedBox.shrink();
        final cents = (rows.first['amount_cents'] as num?)?.toInt() ?? 0;
        if (cents <= 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border.all(color: Colors.green.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.celebration, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Recebeste €${(cents / 100).toStringAsFixed(2)} de cashback no teu Saldo Bora!',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              // T2.4: link directo para o histórico do Saldo Bora.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.account_balance_wallet,
                      size: 16, color: Colors.green),
                  label: const Text('Ver no saldo',
                      style: TextStyle(color: Colors.green)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            WalletHistoryScreen(highlightOrderId: orderId),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Cancel order button + dialog (F1 + F3) ────────────────────────────────────

class _CancelOrderButton extends StatefulWidget {
  const _CancelOrderButton({required this.order});
  final OrderModel order;

  @override
  State<_CancelOrderButton> createState() => _CancelOrderButtonState();
}

class _CancelOrderButtonState extends State<_CancelOrderButton> {
  OrderModel get order => widget.order;

  // Taxas de cancelamento — lidas de platform_settings via RPC get_setting
  // (mesmo padrão do refund_choice_dialog). Os defaults espelham a DB
  // (100c / 250c / ratio 1.0) e servem de fallback se a leitura falhar.
  // Isto é APENAS a estimativa mostrada ao cliente — o débito real é
  // calculado server-side pela Edge Fn cancel-order-with-choice.
  // Adendo2 (2026-08-16): cancelar ANTES de o estafeta aceitar é GRÁTIS
  // (cancel_fee_before_dispatch_cents = 0 em produção, padrão Uber/Glovo).
  // O default espelha a regra nova; a leitura live continua a mandar.
  double _feeBeforeDispatchEur = 0.0;
  double _feeAfterAcceptEur = 2.50;
  double _afterPickupRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _loadCancelFees();
  }

  Future<void> _loadCancelFees() async {
    try {
      final supa = Supabase.instance.client;
      final before = await supa
          .rpc('get_setting', params: {'p_key': 'cancel_fee_before_dispatch_cents'});
      final after = await supa
          .rpc('get_setting', params: {'p_key': 'cancel_fee_after_accept_cents'});
      final ratio = await supa
          .rpc('get_setting', params: {'p_key': 'cancel_fee_after_pickup_ratio'});
      if (!mounted) return;
      setState(() {
        final b = double.tryParse('${before ?? ''}');
        final a = double.tryParse('${after ?? ''}');
        final r = double.tryParse('${ratio ?? ''}');
        if (b != null) _feeBeforeDispatchEur = b / 100.0;
        if (a != null) _feeAfterAcceptEur = a / 100.0;
        if (r != null) _afterPickupRatio = r;
      });
    } catch (_) {/* mantém defaults */}
  }

  /// Reembolso estimado por tier (lê platform_settings; fallback = DB).
  /// before_dispatch=€1 fee, after_accept=€2.50 fee, after_pickup=100% fee.
  double _refundableEur() {
    // finalTotal é autoritativo da DB e já inclui bag_fee para storeShopping.
    // Somar bagFee ao total duplicava o saco (bug 2026-05-22).
    final total = order.finalTotal ?? order.total;
    switch (order.status) {
      case OrderStatus.created:
      case OrderStatus.preparing:
      case OrderStatus.callingDriver:
        return (total - _feeBeforeDispatchEur).clamp(0, double.infinity);
      case OrderStatus.driverAccepted:
        return (total - _feeAfterAcceptEur).clamp(0, double.infinity);
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return (total - total * _afterPickupRatio).clamp(0, double.infinity);
      default:
        return 0;
    }
  }

  String _paymentMethodStr() {
    final pm = order.paymentMethod.name;
    return pm; // 'card' | 'mbway' | 'cash'
  }

  /// Cents da taxa de cancelamento (total - refundable). Para cash o cliente
  /// não pagou nada à frente — esta taxa é debitada à wallet (saldo devedor).
  double _cancelFeeEur() {
    final total = order.finalTotal ?? order.total;
    return (total - _refundableEur()).clamp(0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final refundable = _refundableEur();
    final isCash = order.paymentMethod == PaymentMethod.cash;
    return OutlinedButton.icon(
      onPressed: () async {
        if (isCash) {
          // Cash: não há dinheiro digital para reembolsar. Mostrar apenas
          // dialog informativo com a taxa que ficará em dívida na wallet.
          final reason = await _showCashCancelDialog(context, _cancelFeeEur());
          if (reason == null || !context.mounted) return;
          try {
            await WalletService.instance.cancelWithChoice(
              orderId: order.id,
              reason: reason,
              refundMethod: 'wallet',
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  // Adendo2: sem taxa = mensagem limpa, nada de "€0,00".
                  _cancelFeeEur() <= 0.009
                      ? 'Pedido cancelado. Sem qualquer custo.'
                      : 'Pedido cancelado. Taxa de €${_cancelFeeEur().toStringAsFixed(2)} '
                          'descontada na próxima compra.',
                ),
              ),
            );
            await context.read<OrderStore>().loadOrders();
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao cancelar: $e')),
            );
          }
          return;
        }

        // Card / MBWay: dialog completo com opções de reembolso.
        final res = await showRefundChoiceDialog(
          context,
          orderId: order.id,
          refundableEur: refundable,
          originalPaymentMethod: _paymentMethodStr(),
        );
        if (res != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.refundMethod == 'wallet'
                  ? 'Cancelado. Saldo disponível imediatamente.'
                  : 'Cancelado. Reembolso ao cartão em 5-10 dias úteis.'),
            ),
          );
          // Trigger refresh do OrderStore (realtime channel também actualizará)
          await context.read<OrderStore>().loadOrders();
        }
      },
      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
      label: const Text(
        'Cancelar pedido',
        style: TextStyle(color: Colors.red),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

/// Dialog informativo para cancelamento de pedido cash. Retorna o motivo
/// (não-vazio) se o utilizador confirmou, ou null se cancelou.
Future<String?> _showCashCancelDialog(BuildContext context, double feeEur) async {
  final reasonCtrl = TextEditingController();
  String? error;
  bool submitting = false;
  try {
    return await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Cancelar pedido'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  // Adendo2 (2026-08-16): janela grátis NUNCA ameaça taxa.
                  feeEur <= 0.009
                      ? 'Pagamento em dinheiro: não há reembolso a fazer.\n\n'
                          'Cancelamento gratuito — ainda nenhum estafeta '
                          'aceitou o teu pedido.'
                      : 'Pagamento em dinheiro: não há reembolso a fazer.\n\n'
                          'A tua conta ficará com uma dívida de €${feeEur.toStringAsFixed(2)} '
                          '(taxa de cancelamento). O valor será descontado '
                          'automaticamente na tua próxima compra.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo do cancelamento',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () {
                      final r = reasonCtrl.text.trim();
                      if (r.length < 3) {
                        setState(() => error =
                            'Indica um motivo (mínimo 3 caracteres)');
                        return;
                      }
                      setState(() => submitting = true);
                      Navigator.pop(ctx, r);
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirmar cancelamento'),
            ),
          ],
        );
      },
    ),
    );
  } finally {
    reasonCtrl.dispose();
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
      case OrderStatus.readyForPickup:
        return AppTheme.primary;
      case OrderStatus.callingDriver:
        return Colors.blue;
      case OrderStatus.driverAccepted:
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return AppTheme.primary;
      case OrderStatus.delivered:
        return AppTheme.primary;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  IconData get _statusIcon {
    switch (order.status) {
      case OrderStatus.created:
        return Icons.receipt_long_outlined;
      case OrderStatus.preparing:
        return Icons.soup_kitchen_outlined;
      case OrderStatus.readyForPickup:
        return Icons.storefront_outlined;
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
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
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
              value:
                  '€${(order.finalTotal ?? order.total).toStringAsFixed(2)}',
              bold: true),
          _Row(
              label: 'Taxa de entrega',
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              Text(code,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4)),
              if (subtitle != null)
                Text(subtitle!,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
              child:
                  Container(height: 20, width: 2, color: Colors.grey.shade300),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}

// ── Items card ───────────────────────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'O que compraste',
      child: Column(
        children: [
          ...order.items.map((item) {
            final isUnavailable = item.purchaseStatus == 'unavailable';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.quantity}× ${item.name}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            decoration: isUnavailable
                                ? TextDecoration.lineThrough
                                : null,
                            color: isUnavailable
                                ? Colors.grey.shade400
                                : Colors.black87,
                          ),
                        ),
                        // T1 (2026-06-11): opções escolhidas com preço cobrado
                        // (selected_options_priced gravado pelo create_order).
                        if (item.displayOptions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.displayOptions
                                  .map((o) =>
                                      '${o.group}: ${o.items.join(', ')}')
                                  .join('\n'),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isUnavailable)
                    Text(
                      'indisponível',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                      ),
                    )
                  else
                    Text(
                      '€${(item.price * item.quantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            );
          }),
          if (order.bagFee > 0) ...[
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saco de transporte (${order.bagCount})',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Text(
                    '€${order.bagFee.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Taxa de pedido pequeno (2026-08-27) — linha propria, como no
          // carrinho e no checkout. O valor vem gravado do servidor.
          if (order.smallOrderFee > 0) ...[
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Taxa de pedido pequeno',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Text(
                    '€${order.smallOrderFee.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
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

// ── 8.3 — Talão do favor visível ao cliente (errand). Lê order_receipts_v2
// (RLS owner-scoped) + foto via PrivateBucketImage (bucket privado receipts).
class _ErrandReceiptCard extends StatefulWidget {
  const _ErrandReceiptCard({required this.order});
  final OrderModel order;
  @override
  State<_ErrandReceiptCard> createState() => _ErrandReceiptCardState();
}

class _ErrandReceiptCardState extends State<_ErrandReceiptCard> {
  bool _loading = true;
  String? _photoPath;
  int? _typedCents;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('order_receipts_v2')
          .select('photo_url, driver_typed_total_cents')
          .eq('order_id', widget.order.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _photoPath = row?['photo_url'] as String?;
        _typedCents = (row?['driver_typed_total_cents'] as num?)?.toInt();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final estimated = o.errandEstimatedPurchaseCents / 100.0;
    final real =
        _typedCents != null ? _typedCents! / 100.0 : o.finalPurchaseValue;
    final hasReceipt = _photoPath != null && _photoPath!.isNotEmpty;
    final photo = !hasReceipt
        ? null
        : (_photoPath!.startsWith('http') || _photoPath!.contains('/')
            ? _photoPath!
            : 'receipts/${_photoPath!}');

    return _Card(
      title: 'TALÃO DA COMPRA',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo != null) ...[
                  PrivateBucketImage(
                    urlOrPath: photo,
                    height: 200,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Ainda sem talão. Aparece aqui quando o estafeta concluir a compra.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                if (estimated > 0)
                  _Row(
                      label: 'Orçado',
                      value: '€${estimated.toStringAsFixed(2)}'),
                if (real != null && real > 0)
                  _Row(
                    label: 'Valor do talão',
                    value: '€${real.toStringAsFixed(2)}',
                    bold: true,
                  ),
              ],
            ),
    );
  }
}

// ── BLOCO 3.7 (close-TODOs 2026-05-11) — StoreShopping v2 badges card ─────
//
// Renderiza items pós-compra com badges semânticos quando
// order.purchaseFlowVersion == 2. Backward compat: pedidos v1 NÃO renderizam
// este widget (gate ao nível da composição parent). PT-PT.

class _PurchaseV2Card extends StatefulWidget {
  const _PurchaseV2Card({required this.order});
  final OrderModel order;

  @override
  State<_PurchaseV2Card> createState() => _PurchaseV2CardState();
}

class _PurchaseV2CardState extends State<_PurchaseV2Card> {
  List<Map<String, dynamic>>? _items;
  Map<String, dynamic>? _receipt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orderId = widget.order.id;
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('order_purchase_items_v2')
            .select('id, original_name, original_price_cents, original_qty, '
                'status, actual_name, actual_price_cents, actual_qty')
            .eq('order_id', orderId)
            .order('created_at', ascending: true),
        Supabase.instance.client
            .from('order_receipts_v2')
            .select('driver_typed_total_cents, reimbursement_status')
            .eq('order_id', orderId)
            .maybeSingle(),
      ]);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(results[0] as List);
          _receipt = results[1] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _unavailableCreditCents() {
    if (_items == null) return 0;
    var sum = 0;
    for (final it in _items!) {
      if (it['status'] == 'unavailable') {
        final p = (it['original_price_cents'] as int?) ?? 0;
        final q = (it['original_qty'] as int?) ?? 1;
        sum += p * q;
      }
    }
    return sum;
  }

  // BUG #3 (2026-05-13) — soma real dos itens efectivamente comprados
  // (status purchased/replaced). Distingue do `driver_typed_total_cents` que
  // é o valor digitado pelo estafeta (auditoria).
  int _purchasedItemsTotalCents() {
    if (_items == null) return 0;
    var sum = 0;
    for (final it in _items!) {
      final status = it['status'] as String?;
      if (status != 'purchased' && status != 'replaced') continue;
      final price = (it['actual_price_cents'] as int?) ??
          (it['original_price_cents'] as int? ?? 0);
      final qty = (it['actual_qty'] as int?) ??
          (it['original_qty'] as int? ?? 0);
      sum += price * qty;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Card(
        color: AppTheme.cardBg,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final items = _items ?? const <Map<String, dynamic>>[];
    final creditCents = _unavailableCreditCents();
    final creditEur = (creditCents / 100).toStringAsFixed(2);

    return Card(
      color: AppTheme.cardBg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shopping_basket, color: AppTheme.secondary),
                const SizedBox(width: 8),
                const Text(
                  'Compra detalhada',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                'Aguardando o estafeta concluir a compra na loja…',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...items.map(_itemRow),
            // BUG B (2026-05-13) — mostrar saco como linha na lista quando
            // bagCount > 0. Usa bagFee/bagCount para preco unitario (mercado
            // €0.10 cada; restaurante €0.30 fixo logo bagCount=1).
            if (widget.order.bagCount > 0 && widget.order.bagFee > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: AppTheme.secondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '🛍️ Saco plástico — ${widget.order.bagCount}× €${(widget.order.bagFee / widget.order.bagCount).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '€${widget.order.bagFee.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (creditCents > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Crédito por items indisponíveis',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                  Text(
                    '+€$creditEur',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Foi adicionado ao seu saldo livre (Carteira).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (_receipt != null) ...[
              const Divider(height: 24),
              // BUG C (2026-05-13) — "Total digitado pelo estafeta" foi
              // removido daqui (era exposto ao cliente por engano). Mantem-se
              // apenas no ecra do estafeta (auditoria interna).
              Row(
                children: [
                  Icon(Icons.shopping_basket,
                      size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Soma dos itens',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                  Text(
                    '€${(_purchasedItemsTotalCents() / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> it) {
    final status = (it['status'] as String?) ?? 'pending';
    final name = (it['original_name'] as String?) ?? '';
    final actualName = it['actual_name'] as String?;
    final actualPriceCents = it['actual_price_cents'] as int?;
    final originalPriceCents = (it['original_price_cents'] as int?) ?? 0;
    final qty = (it['original_qty'] as int?) ?? 1;
    final priceEur = (originalPriceCents / 100).toStringAsFixed(2);
    final actualEur = actualPriceCents != null
        ? (actualPriceCents / 100).toStringAsFixed(2)
        : null;

    final (icon, color, label, subtitle) = _statusMeta(
      status: status,
      actualName: actualName,
      actualEur: actualEur,
      originalEur: priceEur,
      qty: qty,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status == 'added' && actualName != null ? actualName : name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: status == 'unavailable'
                          ? Colors.grey.shade700
                          : color,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String, String) _statusMeta({
    required String status,
    required String? actualName,
    required String? actualEur,
    required String originalEur,
    required int qty,
  }) {
    switch (status) {
      case 'purchased':
        return (
          Icons.check_circle,
          AppColors.primary,
          'COMPRADO',
          '${qty}× · €$originalEur',
        );
      case 'unavailable':
        return (
          Icons.cancel,
          const Color(0xFFC62828),
          'INDISPONÍVEL',
          'Não disponível — €$originalEur creditados ao saldo',
        );
      case 'replaced':
        final byPart = actualName != null ? ' por "$actualName"' : '';
        final priceEur = actualEur ?? originalEur;
        return (
          Icons.swap_horiz,
          const Color(0xFF1A73E8),
          'SUBSTITUÍDO',
          'Substituído$byPart · €$priceEur',
        );
      case 'added':
        return (
          Icons.add_circle,
          AppColors.accent,
          'ADICIONADO',
          'Adicionado pelo estafeta · €${actualEur ?? "?"}',
        );
      default:
        return (
          Icons.radio_button_unchecked,
          Colors.grey.shade600,
          'PENDENTE',
          '${qty}× · €$originalEur',
        );
    }
  }
}
