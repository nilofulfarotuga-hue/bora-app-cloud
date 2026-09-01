import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/wallet_service.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/pay_debt_modal.dart';

import '../l10n/tr.dart';

/// Wallet History — lista de transactions do utilizador (saldo livre + tokens).
class WalletHistoryScreen extends StatefulWidget {
  const WalletHistoryScreen({super.key, this.highlightOrderId});

  /// T2.4: when provided, the wallet transactions list highlights txs related
  /// to this order (top-pinned + filter button).
  final String? highlightOrderId;

  @override
  State<WalletHistoryScreen> createState() => _WalletHistoryScreenState();
}

class _WalletHistoryScreenState extends State<WalletHistoryScreen> {
  WalletBalance? _balance;
  bool _loading = true;
  String? _error;

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
      final b = await WalletService.instance.getBalance();
      if (mounted) setState(() => _balance = b);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Não foi possível carregar o saldo. Tenta de novo.'.tr);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Saldo Bora'.tr),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                  ])
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final b = _balance!;
    final isNeg = b.isNegative;
    final isBlocked = b.isBlocked;
    final cardColor = isNeg ? Colors.red.shade50 : Colors.green.shade50;
    final iconColor = isNeg ? Colors.red.shade700 : Colors.green;
    final subtitle = isBlocked
        ? 'BLOQUEADO — regulariza para fazeres pedidos'.tr
        : (isNeg
            ? 'Saldo devedor — descontado na próxima compra'.tr
            : 'Livre, nunca expira');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card saldo livre (Sessão 3B: vermelho se negativo)
        Card(
          color: cardColor,
          child: ListTile(
            leading: Icon(Icons.account_balance_wallet, color: iconColor),
            title: Text('Saldo Bora'.tr),
            subtitle: Text(subtitle,
                style: TextStyle(
                  color: isNeg ? Colors.red.shade900 : null,
                  fontWeight: isBlocked ? FontWeight.w700 : null,
                )),
            trailing: Text(b.freeFormatted,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isNeg ? Colors.red.shade700 : null)),
          ),
        ),
        // BUG #1 frontend (§54 / 2026-05-12) — botão "Pagar dívida agora" + guard Stripe €0.50
        if (isNeg) ...[
          const SizedBox(height: 8),
          if (b.debtCents >= 50)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final paid = await showDialog<bool>(
                    context: context,
                    builder: (_) => PayDebtModal(debtCents: b.debtCents),
                  );
                  if (paid == true && mounted) {
                    await _load();
                  }
                },
                icon: const Icon(Icons.payment),
                label: Text('Pagar dívida agora (€{0})'.trArgs([(b.debtCents / 100).toStringAsFixed(2)])),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Dívida menor que €0.50 — será cobrada no próximo pedido.'.tr,
                style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
        ],
        const SizedBox(height: 8),
        // Card tokens
        Card(
          color: Colors.amber.shade50,
          child: ListTile(
            leading: const Icon(Icons.toll, color: Colors.amber),
            title: Text('Tokens'.tr),
            subtitle: Text('Até 50% desconto no checkout · ≈€{0}'.trArgs([(b.tokensValueCents / 100).toStringAsFixed(2)])),
            trailing: Text('${b.tokensBalance}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('Histórico recente'.tr,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (b.lastTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Sem movimentos ainda.'.tr)),
          )
        else
          ...b.lastTransactions.map(_txTile),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Saldo não reembolsável em dinheiro.'.tr,
            style: const TextStyle(fontSize: 11, color: Colors.black45),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _txTile(WalletTx tx) {
    final color = tx.isCredit ? Colors.green : Colors.red;
    final sign = tx.isCredit ? '+' : '';
    // Sessão 3B: ícone distinto por kind (default: arrow up/down)
    IconData icon;
    Color iconCol = color;
    switch (tx.kind) {
      case 'settlement':
        icon = Icons.swap_horiz;
        iconCol = Colors.deepPurple;
        break;
      case 'forgive':
        icon = Icons.favorite;
        iconCol = Colors.pink;
        break;
      case 'adjustment':
        icon = Icons.edit;
        iconCol = Colors.orange;
        break;
      case 'debit':
        icon = Icons.shopping_basket;
        iconCol = Colors.red.shade700;
        break;
      case 'refund_credit_free':
      case 'refund_credit_tokens':
        icon = Icons.undo;
        iconCol = Colors.green.shade700;
        break;
      case 'admin_grant':
        icon = Icons.card_giftcard;
        iconCol = Colors.green;
        break;
      case 'admin_revoke':
        icon = Icons.remove_circle_outline;
        iconCol = Colors.red.shade700;
        break;
      case 'cashback':
        icon = Icons.savings;
        iconCol = Colors.green;
        break;
      case 'referral':
        icon = Icons.group;
        iconCol = Colors.blue;
        break;
      // BUG #1 backend (§53) — taxa de cancelamento
      case 'cancel_fee_debit':
        icon = Icons.cancel_schedule_send;
        iconCol = Colors.red.shade700;
        break;
      default:
        icon = tx.isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    }
    final balanceLine = tx.balanceAfterCents != null
        ? '\nSaldo após: €{0}'.trArgs([(tx.balanceAfterCents! / 100).toStringAsFixed(2)])
        : '';
    return ListTile(
      leading: Icon(icon, color: iconCol),
      title: Text(tx.kindLabel),
      subtitle: Text(
        '${tx.reason}\n${_fmtDate(tx.createdAt)}$balanceLine',
        maxLines: 4,
      ),
      isThreeLine: true,
      trailing: Text(
        '$sign€${(tx.amountCents.abs() / 100).toStringAsFixed(2)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2,'0')}-${l.day.toString().padLeft(2,'0')} '
        '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
  }
}
