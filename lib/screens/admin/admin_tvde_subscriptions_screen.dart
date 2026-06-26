import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — Assinaturas (conceder / ver).
///
/// Concede uma assinatura a um cliente via `admin_grant_subscription(client,
/// plano)` (já existia — Fase 1). Lista as assinaturas via
/// `admin_tvde_subscriptions_list()` (RPC admin read-only, aditivo).
/// O cliente é escolhido reaproveitando `admin_list_clients` (busca já existente).
/// Idioma: PT-BR.
class AdminTvdeSubscriptionsScreen extends StatefulWidget {
  const AdminTvdeSubscriptionsScreen({super.key});

  @override
  State<AdminTvdeSubscriptionsScreen> createState() =>
      _AdminTvdeSubscriptionsScreenState();
}

class _AdminTvdeSubscriptionsScreenState
    extends State<AdminTvdeSubscriptionsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res =
        await Supabase.instance.client.rpc('admin_tvde_subscriptions_list');
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _grantFlow() async {
    final client = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ClientPickerDialog(),
    );
    if (client == null || !mounted) return;

    final plan = await showDialog<String>(
      context: context,
      builder: (ctx) => _PlanPickerDialog(
        clientLabel: (client['bora_name'] as String?)?.trim().isNotEmpty == true
            ? client['bora_name'] as String
            : (client['email'] as String? ?? 'cliente'),
      ),
    );
    if (plan == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_grant_subscription', params: {
        'p_client_id': client['user_id'],
        'p_plan': plan,
      });
      if (!mounted) return;
      _toast('Assinatura "$plan" concedida.', AppColors.primary);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _toast(humanizeAdminRpcError(e), AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Assinaturas — Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _busy ? null : _grantFlow,
        icon: const Icon(Icons.card_membership, color: Colors.white),
        label: const Text('Conceder assinatura',
            style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
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
                        Text('Erro:\n${snap.error}',
                            textAlign: TextAlign.center),
                      ],
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Sem assinaturas ainda.\n'
                            'Toca em "Conceder assinatura" para começar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _SubCard(data: rows[i]),
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

class _SubCard extends StatelessWidget {
  const _SubCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final active = data['active'] == true;
    final name = (data['client_name'] as String?)?.trim();
    final email = (data['client_email'] as String?) ?? '—';
    final plan = (data['plan'] as String?) ?? '—';
    final total = (data['rides_total'] as num?)?.toInt() ?? 0;
    final used = (data['rides_used'] as num?)?.toInt() ?? 0;
    final daily = (data['daily_included'] as num?)?.toInt() ?? 0;
    final price = (data['price_cents'] as num?)?.toInt() ?? 0;
    final endsAt = data['ends_at'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (name != null && name.isNotEmpty) ? name : email,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (active ? AppColors.primary : AppColors.textSubtle)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(active ? 'Ativa' : 'Inativa',
                      style: TextStyle(
                          color:
                              active ? AppColors.primary : AppColors.textSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Plano: ${_planLabel(plan)} · €${(price / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total == 0 ? 0 : (used / total).clamp(0, 1).toDouble(),
              backgroundColor: AppColors.textSubtle.withValues(alpha: 0.15),
              color: AppColors.primary,
              minHeight: 6,
            ),
            const SizedBox(height: 6),
            Text(
              'Corridas usadas: $used / $total · $daily/dia incluídas · '
              'termina ${_fmtDate(endsAt)}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Busca + escolhe um cliente (reaproveita `admin_list_clients`).
class _ClientPickerDialog extends StatefulWidget {
  const _ClientPickerDialog();

  @override
  State<_ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<_ClientPickerDialog> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_list_clients',
          params: {
            'p_search': _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
            'p_limit': 30,
          });
      final list = (res as List?) ?? const [];
      setState(() {
        _results = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Escolher cliente'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Buscar nome / email / telefone',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(child: Text('Sem resultados.'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final c = _results[i];
                            final name = (c['bora_name'] as String?)?.trim();
                            final email = (c['email'] as String?) ?? '—';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                  (name != null && name.isNotEmpty)
                                      ? name
                                      : email,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(email,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _PlanPickerDialog extends StatelessWidget {
  const _PlanPickerDialog({required this.clientLabel});
  final String clientLabel;

  @override
  Widget build(BuildContext context) {
    const plans = {
      'semanal': 'Semanal — 14 corridas (7 dias)',
      'quinzenal': 'Quinzenal — 30 corridas (15 dias)',
      'mensal': 'Mensal — 60 corridas (30 dias)',
    };
    return AlertDialog(
      title: Text('Plano para $clientLabel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: plans.entries
            .map((e) => ListTile(
                  leading: const Icon(Icons.card_membership,
                      color: AppColors.primary),
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  onTap: () => Navigator.pop(context, e.key),
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

String _planLabel(String p) => switch (p) {
      'semanal' => 'Semanal',
      'quinzenal' => 'Quinzenal',
      'mensal' => 'Mensal',
      _ => p,
    };

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
