import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — No-shows (corridas canceladas com taxa cobrada).
///
/// Lista as corridas em que o cliente NÃO apareceu / cancelou tarde e uma taxa
/// foi cobrada (cancel_fee_cents). O motorista recebe €3,50 fixo (driver_earn_cents)
/// e o resto fica para a Bora (bora_cut_cents). O admin pode REVERTER um no-show
/// (ex.: erro, disputa) via `tvde_admin_revert_noshow`.
///
/// Lê `admin_list_tvde_noshows()` (RPC admin read-only) e escreve via
/// `tvde_admin_revert_noshow(p_ride_id, p_reason)`.
/// Idioma: PT-BR (termos técnicos explicados entre parênteses).
class AdminTvdeNoShowsScreen extends StatefulWidget {
  const AdminTvdeNoShowsScreen({super.key});

  @override
  State<AdminTvdeNoShowsScreen> createState() => _AdminTvdeNoShowsScreenState();
}

class _AdminTvdeNoShowsScreenState extends State<AdminTvdeNoShowsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_list_tvde_noshows');
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

  Future<void> _revert(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    final origin = (row['origin_label'] as String?)?.trim() ?? '—';
    final dest = (row['dest_label'] as String?)?.trim() ?? '—';
    final reasonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverter no-show'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vai REVERTER o no-show de "$origin → $dest" (cancela a taxa cobrada ao cliente e o pagamento do motorista deste no-show).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final reason = reasonCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('tvde_admin_revert_noshow', params: {
        'p_ride_id': id,
        'p_reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      _toast('No-show revertido — $origin → $dest', AppColors.primary);
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
        title: 'No-shows — Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
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
                    return _ErrorState(
                        message: '${snap.error}', onRetry: _refresh);
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Nenhum no-show registado.',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _NoShowCard(
                      data: rows[i],
                      busy: _busy,
                      onRevert: _revert,
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

class _NoShowCard extends StatelessWidget {
  const _NoShowCard({
    required this.data,
    required this.busy,
    required this.onRevert,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) onRevert;

  @override
  Widget build(BuildContext context) {
    final origin = (data['origin_label'] as String?)?.trim() ?? '—';
    final dest = (data['dest_label'] as String?)?.trim() ?? '—';
    final reason = (data['cancel_reason'] as String?)?.trim();
    final driverId = _short(data['driver_id']);
    final clientId = _short(data['client_id']);

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
            // ── Rota ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.route, size: 18, color: AppColors.textSubtle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$origin → $dest',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Dinheiro ──
            _line(Icons.person, 'Cobrado ao cliente: ${_eur(data['cancel_fee_cents'])}'),
            _line(Icons.local_taxi, 'Motorista: ${_eur(data['driver_earn_cents'])}'),
            _line(Icons.business, 'Bora: ${_eur(data['bora_cut_cents'])}'),
            _line(Icons.calendar_today_outlined,
                'Data: ${_fmtDate(data['updated_at'])}'),
            if (reason != null && reason.isNotEmpty)
              _line(Icons.info_outline, 'Motivo: $reason'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(icon: Icons.local_taxi, label: 'Motorista: $driverId'),
                _Pill(icon: Icons.person_outline, label: 'Cliente: $clientId'),
              ],
            ),
            const SizedBox(height: 12),
            // ── Ação ──
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: busy ? null : () => onRevert(data),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Reverter'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(dynamic id) {
    final s = id?.toString() ?? '';
    if (s.isEmpty) return '—';
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  static String _eur(dynamic cents) {
    final c = (cents as num?)?.toDouble() ?? 0;
    return '€${(c / 100).toStringAsFixed(2)}';
  }

  static Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textSubtle),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const c = AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('Erro ao carregar:\n$message', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ),
      ],
    );
  }
}

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
