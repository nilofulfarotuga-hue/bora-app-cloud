import 'package:flutter/material.dart';
import '../services/wallet_service.dart';

/// Wallet History — lista de transactions do utilizador (saldo livre + tokens).
class WalletHistoryScreen extends StatefulWidget {
  const WalletHistoryScreen({super.key});
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
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saldo Bora')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ])
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final b = _balance!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card saldo livre
        Card(
          color: Colors.green.shade50,
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Colors.green),
            title: const Text('Saldo Bora'),
            subtitle: const Text('Livre, nunca expira'),
            trailing: Text('€${(b.freeCents / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        // Card tokens
        Card(
          color: Colors.amber.shade50,
          child: ListTile(
            leading: const Icon(Icons.toll, color: Colors.amber),
            title: const Text('Tokens'),
            subtitle: Text('Até 50% desconto no checkout · ≈€${(b.tokensValueCents / 100).toStringAsFixed(2)}'),
            trailing: Text('${b.tokensBalance}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('Histórico recente',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (b.lastTransactions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Sem movimentos ainda.')),
          )
        else
          ...b.lastTransactions.map(_txTile),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Saldo não reembolsável em dinheiro.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _txTile(WalletTx tx) {
    final color = tx.isCredit ? Colors.green : Colors.red;
    final sign = tx.isCredit ? '+' : '';
    return ListTile(
      leading: Icon(tx.isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: color),
      title: Text(tx.kindLabel),
      subtitle: Text(
        '${tx.reason}\n${_fmtDate(tx.createdAt)}',
        maxLines: 3,
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
