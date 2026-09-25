import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista (TVDE) — Dívidas de dinheiro dos motoristas.
///
/// Quando a corrida é paga **em dinheiro**, o motorista recebe o valor todo em
/// mão e fica a dever à Bora a parte da plataforma. O `tvde_finish_ride` acumula
/// essa parte em `tvde_driver_balances.balance` (em EUROS, não cents).
///
/// Lê a tabela diretamente — a policy `tvde_driver_bal_select` já permite
/// `is_admin()`. Read-only por decisão: **liquidar** uma dívida mexe em dinheiro
/// real e precisa de uma RPC dedicada no backend (ainda não existe).
/// Idioma: PT-BR.
class AdminTvdeDriverDebtsScreen extends StatefulWidget {
  const AdminTvdeDriverDebtsScreen({super.key});

  @override
  State<AdminTvdeDriverDebtsScreen> createState() =>
      _AdminTvdeDriverDebtsScreenState();
}

class _AdminTvdeDriverDebtsScreenState
    extends State<AdminTvdeDriverDebtsScreen> {
  late Future<List<_DriverDebt>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_DriverDebt>> _load() async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('tvde_driver_balances')
        .select('driver_id, balance, updated_at')
        .order('balance', ascending: false);

    final rows = (res as List?) ?? const [];
    final balances = rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (balances.isEmpty) return const [];

    // Nomes/telefones numa 2.ª query (evita depender de uma FK declarada entre
    // tvde_driver_balances e drivers).
    final ids = balances.map((b) => b['driver_id'].toString()).toList();
    final Map<String, Map<String, dynamic>> byId = {};
    try {
      final drv =
          await sb.from('drivers').select('id, name, phone').inFilter('id', ids);
      for (final d in ((drv as List?) ?? const []).whereType<Map>()) {
        byId[d['id'].toString()] = Map<String, dynamic>.from(d);
      }
    } catch (_) {
      // Sem nomes ainda dá para gerir pelo id — não falha o ecrã por isso.
    }

    return balances.map((b) {
      final id = b['driver_id'].toString();
      final d = byId[id];
      return _DriverDebt(
        driverId: id,
        name: (d?['name'] as String?)?.trim(),
        phone: d?['phone'] as String?,
        balanceEur: (b['balance'] as num?)?.toDouble() ?? 0,
        updatedAt: b['updated_at'],
      );
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  List<_DriverDebt> _filter(List<_DriverDebt> all) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((d) =>
            (d.name ?? '').toLowerCase().contains(q) ||
            (d.phone ?? '').toLowerCase().contains(q) ||
            d.driverId.toLowerCase().contains(q))
        .toList();
  }

  /// Exporta o resumo para a área de transferência (CSV simples) — auditoria.
  Future<void> _export(List<_DriverDebt> rows) async {
    final buffer = StringBuffer('driver_id;nome;telefone;divida_eur;atualizado\n');
    for (final d in rows) {
      buffer.writeln('${d.driverId};${d.name ?? ''};${d.phone ?? ''};'
          '${d.balanceEur.toStringAsFixed(2)};${d.updatedAt ?? ''}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${rows.length} linha(s) copiadas em CSV.'),
      backgroundColor: AppColors.primary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Dívidas em dinheiro — Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<_DriverDebt>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.error_outline,
                    size: 44, color: AppColors.error),
                const SizedBox(height: 12),
                Text('Erro:\n${snap.error}', textAlign: TextAlign.center),
              ],
            );
          }
          final all = snap.data ?? const <_DriverDebt>[];
          final rows = _filter(all);
          final totalEur =
              all.fold<double>(0, (sum, d) => sum + d.balanceEur);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                _TotalBanner(totalEur: totalEur, count: all.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          decoration: const InputDecoration(
                            hintText: 'Buscar nome / telefone / id',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Exportar CSV',
                        onPressed: rows.isEmpty ? null : () => _export(rows),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 100),
                            Center(
                              child: Text(
                                'Nenhum motorista com dívida em aberto.',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: rows.length,
                          itemBuilder: (_, i) => _DebtCard(debt: rows[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverDebt {
  const _DriverDebt({
    required this.driverId,
    required this.name,
    required this.phone,
    required this.balanceEur,
    required this.updatedAt,
  });

  final String driverId;
  final String? name;
  final String? phone;
  final double balanceEur;
  final dynamic updatedAt;
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.totalEur, required this.count});
  final double totalEur;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total a receber dos motoristas',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('€${totalEur.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 2),
          Text('$count motorista(s) com saldo em aberto',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debt});
  final _DriverDebt debt;

  @override
  Widget build(BuildContext context) {
    final name = debt.name;
    final title = (name != null && name.isNotEmpty) ? name : debt.driverId;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: const Icon(Icons.account_balance_wallet_outlined,
            color: AppColors.primary),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          '${debt.phone ?? 'sem telefone'}\n'
          'Atualizado ${_fmtDateTime(debt.updatedAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
        ),
        isThreeLine: true,
        trailing: Text(
          '€${debt.balanceEur.toStringAsFixed(2)}',
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.error),
        ),
      ),
    );
  }
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
