import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin/admin_driver_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista (TVDE) — Motoristas de passageiros (gerir / banir).
///
/// Lista os motoristas com `vehicle_type = 'carro_passageiros'` via
/// `admin_tvde_drivers_list()` (RPC admin read-only, aditivo) e usa o
/// mecanismo de gestão de motoristas que JÁ existe (`AdminDriverService`:
/// `admin_ban_driver` / `admin_reactivate_driver`) — sem reinventar.
/// Idioma: PT-BR.
class AdminTvdeDriversScreen extends StatefulWidget {
  const AdminTvdeDriversScreen({super.key});

  @override
  State<AdminTvdeDriversScreen> createState() => _AdminTvdeDriversScreenState();
}

class _AdminTvdeDriversScreenState extends State<AdminTvdeDriversScreen> {
  final _svc = AdminDriverService();
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_tvde_drivers_list');
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

  Future<void> _ban(Map<String, dynamic> d) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Banir ${d['name'] ?? 'motorista'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Banir tira o motorista de circulação (deixa de receber corridas). '
              'Escreve o motivo (fica no histórico):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Motivo (mínimo 3 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Banir'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.length < 3) {
      _toast('Motivo tem de ter pelo menos 3 caracteres.', AppColors.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await _svc.banDriver(
        driverId: d['id'].toString(),
        reasonCode: 'other',
        reason: reason,
      );
      if (!mounted) return;
      _toast('Motorista banido.', AppColors.primary);
      await _refresh();
    } on AdminDriverException catch (e) {
      if (!mounted) return;
      _toast(e.message, AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reactivate(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reativar ${d['name'] ?? 'motorista'}'),
        content: const Text(
            'Vai limpar o banimento (o motorista volta a poder receber corridas).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.reactivateDriver(
        driverId: d['id'].toString(),
        note: 'Reativado pelo painel Bora Motorista',
      );
      if (!mounted) return;
      _toast('Motorista reativado.', AppColors.primary);
      await _refresh();
    } on AdminDriverException catch (e) {
      if (!mounted) return;
      _toast(e.message, AppColors.error);
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
        title: 'Motoristas — Passageiros',
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
                            'Nenhum motorista de passageiros ainda.\n'
                            '(São os estafetas com veículo "Carro — Passageiros".)',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _DriverCard(
                      data: rows[i],
                      busy: _busy,
                      onBan: _ban,
                      onReactivate: _reactivate,
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

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.data,
    required this.busy,
    required this.onBan,
    required this.onReactivate,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) onBan;
  final Future<void> Function(Map<String, dynamic>) onReactivate;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.trim();
    final phone = (data['phone'] as String?)?.trim();
    final online = data['is_online'] == true;
    final banned = data['is_banned'] == true;
    final approval = (data['approval_status'] as String?) ?? 'pending';
    final rating = (data['rating'] as num?)?.toDouble();
    final ratingsCount = (data['ratings_count'] as num?)?.toInt() ?? 0;
    final balance = (data['tvde_balance'] as num?)?.toDouble() ?? 0;
    final active = (data['active_rides'] as num?)?.toInt() ?? 0;
    final total = (data['total_rides'] as num?)?.toInt() ?? 0;
    final banReason = (data['ban_reason'] as String?)?.trim();
    // [TVDE P0 2026-07-02] telemetria de elegibilidade — diagnóstico rápido
    // de "cliente não acha motorista" sem abrir o banco.
    final heartbeatAt = DateTime.tryParse(
        (data['last_heartbeat_at'] as String?) ?? '');
    final locationAt = DateTime.tryParse(
        (data['location_updated_at'] as String?) ?? '');
    final hasToken = data['has_fcm_token'] == true;

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
                CircleAvatar(
                  radius: 6,
                  backgroundColor:
                      online ? AppColors.primary : AppColors.textSubtle,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (name != null && name.isNotEmpty) ? name : '(sem nome)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                if (banned)
                  const _Tag(label: 'Banido', color: AppColors.error)
                else
                  _ApprovalTag(status: approval),
              ],
            ),
            const SizedBox(height: 8),
            if (phone != null && phone.isNotEmpty)
              _line(Icons.phone_outlined, phone),
            _line(Icons.circle, online ? 'Online agora' : 'Offline',
                color: online ? AppColors.primary : AppColors.textSubtle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(
                    icon: Icons.star,
                    label: rating == null
                        ? 'Sem avaliação'
                        : '${rating.toStringAsFixed(1)} ($ratingsCount)'),
                _Pill(icon: Icons.local_taxi, label: '$active em curso'),
                _Pill(icon: Icons.done_all, label: '$total concluídas'),
                _Pill(
                  icon: Icons.account_balance_wallet,
                  label: 'Deve ao Bora: €${balance.toStringAsFixed(2)}',
                  color: balance > 0 ? AppColors.accent : AppColors.primary,
                ),
                _Pill(
                  icon: Icons.favorite,
                  label: 'Heartbeat: ${_ago(heartbeatAt)}',
                  color: _freshColor(heartbeatAt),
                ),
                _Pill(
                  icon: Icons.gps_fixed,
                  label: 'GPS: ${_ago(locationAt)}',
                  color: _freshColor(locationAt),
                ),
                _Pill(
                  icon: hasToken
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  label: hasToken ? 'Push OK' : 'Sem token push',
                  color: hasToken ? AppColors.primary : AppColors.error,
                ),
              ],
            ),
            if (banned && banReason != null && banReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Motivo do banimento: $banReason',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error)),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: banned
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: busy ? null : () => onReactivate(data),
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('Reativar'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error),
                      onPressed: busy ? null : () => onBan(data),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Banir'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// "agora" / "há Xmin" / "há Xh" / '—' quando nunca houve sinal.
  static String _ago(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 48) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }

  /// Verde = fresco (elegível), laranja = a envelhecer, vermelho = morto.
  static Color _freshColor(DateTime? t) {
    if (t == null) return AppColors.error;
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inSeconds <= 90) return AppColors.primary;
    if (diff.inMinutes <= 10) return AppColors.warning;
    return AppColors.error;
  }

  Widget _line(IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.textSubtle;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ApprovalTag extends StatelessWidget {
  const _ApprovalTag({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Aprovado', AppColors.primary),
      'rejected' => ('Rejeitado', AppColors.error),
      _ => ('Pendente', AppColors.warning),
    };
    return _Tag(label: label, color: color);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
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
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}
