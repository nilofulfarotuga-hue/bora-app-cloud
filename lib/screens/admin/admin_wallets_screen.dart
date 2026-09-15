import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../services/wallet_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminWalletsScreen extends StatefulWidget {
  const AdminWalletsScreen({super.key});
  @override
  State<AdminWalletsScreen> createState() => _AdminWalletsScreenState();
}

class _AdminWalletsScreenState extends State<AdminWalletsScreen> {
  final _searchCtrl = TextEditingController();
  List<AdminWalletRow> _rows = const [];
  bool _loading = true;
  String? _error;
  // Sessão 3B
  bool _onlyNegative = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await WalletService.instance.adminList(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        limit: 200,
      );
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grantOrRevoke(AdminWalletRow row, {required bool grant}) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(grant ? 'Atribuir saldo livre' : 'Retirar saldo livre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(row.email),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor (€)'),
            ),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    final eur = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (eur == null || eur <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor inválido')));
      }
      return;
    }
    final cents = (eur * 100).round();
    final reason = reasonCtrl.text.trim();
    if (reason.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Motivo obrigatório (3+ chars)')));
      }
      return;
    }
    try {
      if (grant) {
        await WalletService.instance.adminGrantFree(userId: row.userId, amountCents: cents, reason: reason);
      } else {
        await WalletService.instance.adminRevokeFree(userId: row.userId, amountCents: cents, reason: reason);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operação OK')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Wallets'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Procurar por email ou nome',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                  IconButton(
                    tooltip: 'Exportar negativos CSV',
                    icon: const Icon(Icons.download),
                    onPressed: _exportNegativeCsv,
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _onlyNegative,
                onChanged: (v) => setState(() => _onlyNegative = v),
                title: const Text('Apenas saldo negativo',
                    style: TextStyle(fontSize: 13)),
                secondary: Icon(Icons.warning_amber,
                    color: Colors.red.shade700, size: 20),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 60),
                                Center(child: Text('Sem clientes com saldo.')),
                              ])
                            : Builder(builder: (_) {
                                final filtered = _onlyNegative
                                    ? _rows.where((r) => r.freeBalanceCents < 0).toList()
                                    : List<AdminWalletRow>.from(_rows);
                                // Sessão 3B: ordenar negativos primeiro (mais negativo)
                                filtered.sort((a, b) =>
                                    a.freeBalanceCents.compareTo(b.freeBalanceCents));
                                if (filtered.isEmpty) {
                                  return ListView(children: const [
                                    SizedBox(height: 60),
                                    Center(child: Text('Sem clientes a mostrar.')),
                                  ]);
                                }
                                return ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final r = filtered[i];
                                    final isNeg = r.freeBalanceCents < 0;
                                    return ListTile(
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(r.fullName ?? r.email),
                                          ),
                                          if (isNeg) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade700,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'EM DÍVIDA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text(r.email),
                                      leading: isNeg
                                          ? Icon(Icons.warning_amber,
                                              color: Colors.red.shade700)
                                          : null,
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('€${(r.freeBalanceCents / 100).toStringAsFixed(2)}',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isNeg ? Colors.red.shade700 : null)),
                                          Text('${r.tokensBalance} tokens',
                                              style: const TextStyle(fontSize: 11, color: Colors.amber)),
                                        ],
                                      ),
                                      onTap: () => showModalBottomSheet(
                                        context: context,
                                        builder: (_) => SafeArea(
                                          child: Wrap(
                                            children: [
                                              ListTile(
                                                leading: const Icon(Icons.add, color: Colors.green),
                                                title: const Text('Atribuir saldo livre'),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _grantOrRevoke(r, grant: true);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(Icons.remove, color: Colors.red),
                                                title: const Text('Retirar saldo livre'),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _grantOrRevoke(r, grant: false);
                                                },
                                              ),
                                              if (isNeg)
                                                ListTile(
                                                  leading: Icon(Icons.favorite,
                                                      color: Colors.pink.shade400),
                                                  title: const Text('Perdoar dívida'),
                                                  subtitle: Text(
                                                      'Liquida €${(-r.freeBalanceCents / 100).toStringAsFixed(2)}'),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    _forgiveDebt(r);
                                                  },
                                                ),
                                              ListTile(
                                                leading: const Icon(Icons.list_alt, color: Colors.blue),
                                                title: const Text('Ver transactions'),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _showUserTransactions(r);
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }),
                      ),
          ),
        ],
      ),
    );
  }

  // Sessão 3B: perdoar dívida (admin_forgive_wallet_debt RPC).
  Future<void> _forgiveDebt(AdminWalletRow row) async {
    if (row.freeBalanceCents >= 0) return;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Perdoar dívida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.email),
            const SizedBox(height: 4),
            Text(
              'Saldo actual: €${(row.freeBalanceCents / 100).toStringAsFixed(2)}',
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'A wallet vai a 0. Esta acção é irreversível.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo (obrigatório)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade400),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Perdoar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final reason = reasonCtrl.text.trim();
    if (reason.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Motivo obrigatório (3+ chars)')));
      }
      return;
    }
    // Q2 (2026-05-17) — Regra 8: confirmação dupla em mov. de dinheiro real.
    if (!mounted) return;
    final confirmCtrl = TextEditingController();
    bool confirmOk = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Confirmação final'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vai perdoar €${(-row.freeBalanceCents / 100).toStringAsFixed(2)} '
                'a ${row.email}. A Bora absorve o prejuízo.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text('Digite "CONFIRMAR" para prosseguir:'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'CONFIRMAR',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    setSt(() => confirmOk = v.trim() == 'CONFIRMAR'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade400),
              onPressed: confirmOk ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Perdoar'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (confirmed != true) return;
    try {
      final cents = await WalletService.instance.adminForgiveDebt(
          userId: row.userId, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Dívida perdoada: €${(cents / 100).toStringAsFixed(2)}')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text('Erro: $e')));
      }
    }
  }

  // Sessão 3B: exporta CSV de wallets negativas.
  Future<void> _exportNegativeCsv() async {
    final negs = _rows.where((r) => r.freeBalanceCents < 0).toList()
      ..sort((a, b) => a.freeBalanceCents.compareTo(b.freeBalanceCents));
    if (negs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sem wallets negativas para exportar.')));
      }
      return;
    }
    final headers = ['user_id', 'email', 'full_name', 'balance_eur', 'last_tx_at'];
    final rows = negs
        .map((r) => [
              r.userId,
              r.email,
              r.fullName ?? '',
              (r.freeBalanceCents / 100).toStringAsFixed(2),
              r.lastTxAt?.toIso8601String() ?? '',
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_wallets_negativas_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Wallets negativas $stamp',
    );
  }

  // T5.3: modal com todas wallet_transactions de 1 user + CSV.
  Future<void> _showUserTransactions(AdminWalletRow row) async {
    String kind = 'all';
    Future<List<Map<String, dynamic>>> fetch() async {
      final res = await Supabase.instance.client
          .rpc('admin_user_wallet_transactions', params: {
        'p_user_id': row.userId,
        'p_kind': kind == 'all' ? null : kind,
        'p_limit': 200,
      });
      return (res as List).cast<Map<String, dynamic>>();
    }

    var txs = await fetch();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: Text(row.email,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Export CSV',
                    onPressed: () async {
                      final headers = ['id', 'created_at', 'amount_cents',
                                       'kind', 'reason', 'related_order_id'];
                      final rows = txs
                          .map((t) => [
                                t['id'] ?? '', t['created_at'] ?? '',
                                t['amount_cents'] ?? '', t['kind'] ?? '',
                                t['reason'] ?? '', t['related_order_id'] ?? '',
                              ])
                          .toList();
                      final stamp = DateTime.now().toIso8601String().substring(0, 10);
                      await AdminExportService.instance.exportCsv(
                        filename: 'bora_wallet_${row.email}_$stamp.csv',
                        headers: headers,
                        rows: rows,
                        subject: 'Bora — Wallet ${row.email}',
                      );
                    },
                  ),
                ]),
              ),
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: ['all', 'cashback', 'order_payment', 'admin_grant',
                             'admin_revoke', 'refund_credit_free', 'referral']
                      .map((k) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(k, style: const TextStyle(fontSize: 11)),
                              selected: kind == k,
                              onSelected: (_) async {
                                kind = k;
                                txs = await fetch();
                                setM(() {});
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: txs.isEmpty
                    ? const Center(child: Text('Sem transactions.'))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: txs.length,
                        itemBuilder: (_, i) {
                          final t = txs[i];
                          final cents = (t['amount_cents'] as num?)?.toInt() ?? 0;
                          final isCredit = cents > 0;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isCredit ? Icons.add_circle : Icons.remove_circle,
                              color: isCredit ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            title: Text(t['kind'] as String? ?? ''),
                            subtitle: Text(
                                '${t['reason'] ?? ''}\n${(t['created_at'] as String?)?.substring(0, 16) ?? ''}'),
                            isThreeLine: true,
                            trailing: Text(
                              '${isCredit ? '+' : ''}€${(cents / 100).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
