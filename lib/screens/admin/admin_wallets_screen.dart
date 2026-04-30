import 'package:flutter/material.dart';
import '../../services/wallet_service.dart';

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
      appBar: AppBar(title: const Text('Wallets')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
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
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 60),
                                Center(child: Text('Sem clientes com saldo.')),
                              ])
                            : ListView.builder(
                                itemCount: _rows.length,
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  return ListTile(
                                    title: Text(r.fullName ?? r.email),
                                    subtitle: Text(r.email),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('€${(r.freeBalanceCents / 100).toStringAsFixed(2)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
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
