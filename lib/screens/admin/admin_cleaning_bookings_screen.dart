import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Limpeza doméstica — Admin: todas as reservas de limpeza.
/// Filtros por estado/pesquisa, cancelar (admin_cancel_cleaning) e
/// reagendar (admin_reschedule_cleaning). Idioma: PT-BR.
class AdminCleaningBookingsScreen extends StatefulWidget {
  const AdminCleaningBookingsScreen({super.key});

  @override
  State<AdminCleaningBookingsScreen> createState() =>
      _AdminCleaningBookingsScreenState();
}

class _AdminCleaningBookingsScreenState
    extends State<AdminCleaningBookingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  String? _statusFilter;
  final _searchCtrl = TextEditingController();

  static const _statusLabels = <String, String>{
    'scheduled': 'Agendada',
    'accepted': 'Confirmada',
    'on_the_way': 'A caminho',
    'in_progress': 'Em andamento',
    'done': 'Aguarda cliente',
    'completed': 'Concluída',
    'cancelled_client': 'Cancelada (cliente)',
    'cancelled_cleaner': 'Cancelada (profissional)',
    'cancelled_no_cleaner': 'Cancelada (sem profissional)',
  };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res =
        await Supabase.instance.client.rpc('admin_list_cleanings', params: {
      'p_status': _statusFilter,
      'p_search':
          _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    });
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

  Future<void> _cancel(Map<String, dynamic> b) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar esta limpeza?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Cancelamento administrativo: sem taxa para o cliente. '
                'Cliente e profissional são notificados.'),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Cancelar limpeza')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => Supabase.instance.client.rpc('admin_cancel_cleaning',
            params: {'p_booking_id': b['id'], 'p_reason': reasonCtrl.text}),
        'Limpeza cancelada.');
  }

  /// Conversa da limpeza (read-only + audit via admin_list_cleaning_messages).
  Future<void> _viewChat(Map<String, dynamic> b) async {
    List<Map<String, dynamic>> msgs = const [];
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_cleaning_messages', params: {'p_booking_id': b['id']});
      msgs = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conversa (só leitura)'),
        content: SizedBox(
          width: double.maxFinite,
          child: msgs.isEmpty
              ? const Text('Sem mensagens nesta limpeza.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in msgs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: m['sender_role'] == 'client'
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: m['sender_role'] == 'client'
                                  ? AppColors.surface
                                  : AppColors.primaryWash,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['sender_role'] == 'client'
                                      ? 'Cliente'
                                      : 'Profissional',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSubtle),
                                ),
                                Text('${m['message'] ?? ''}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _reschedule(Map<String, dynamic> b) async {
    final current =
        DateTime.tryParse(b['scheduled_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    final newAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _run(() => Supabase.instance.client.rpc('admin_reschedule_cleaning',
            params: {
          'p_booking_id': b['id'],
          'p_new_scheduled_at': newAt.toUtc().toIso8601String(),
        }),
        'Limpeza reagendada.');
  }

  Future<void> _run(Future<dynamic> Function() fn, String successMsg) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg), backgroundColor: AppColors.primary));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Limpezas',
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar por estado',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _refresh();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Todas')),
              for (final e in _statusLabels.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por e-mail, profissional, endereço ou ID…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _refresh();
                  },
                ),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
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
                          child: Text('Nenhuma limpeza neste filtro.',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _BookingCard(
                      data: rows[i],
                      busy: _busy,
                      statusLabels: _statusLabels,
                      onCancel: () => _cancel(rows[i]),
                      onReschedule: () => _reschedule(rows[i]),
                      onViewChat: () => _viewChat(rows[i]),
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

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.data,
    required this.busy,
    required this.statusLabels,
    required this.onCancel,
    required this.onReschedule,
    required this.onViewChat,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final Map<String, String> statusLabels;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onViewChat;

  String _euro(dynamic cents) =>
      '€${(((cents as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? '';
    final active = const [
      'scheduled', 'accepted', 'on_the_way', 'in_progress'
    ].contains(status);
    final type = switch (data['cleaning_type']) {
      'deep' => 'Profunda',
      'post_works' => 'Pós-obras',
      _ => 'Standard',
    };
    final size = data['pricing_mode'] == 'hourly'
        ? '${data['hours'] ?? 0}h por hora'
        : switch (data['home_size']) {
            't0_t1' => 'T0/T1',
            't2' => 'T2',
            't3' => 'T3',
            't4plus' => 'T4+',
            _ => '—',
          };
    final payment = switch (data['payment_method']) {
      'card' => 'Cartão',
      'mbway' => 'MB Way',
      _ => 'Dinheiro',
    };

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$type · $size',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                _StatusChip(
                    label: statusLabels[status] ?? status,
                    active: active,
                    cancelled: status.startsWith('cancelled')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtDate(data['scheduled_at'])} · ${_euro(data['total_cents'])} · $payment '
              '(${data['payment_status'] ?? '—'})',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            Text(
              'Cliente: ${data['client_email'] ?? '—'}\n'
              'Profissional: ${data['cleaner_name'] ?? 'por atribuir'}\n'
              '${data['address_street'] ?? ''}, ${data['address_city'] ?? ''} '
              '${data['address_postal'] ?? ''}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
            if ((data['recurrence'] as String? ?? 'single') != 'single')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Recorrência: ${data['recurrence'] == 'weekly' ? 'semanal' : 'quinzenal'}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onViewChat,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Ver conversa'),
              ),
            ),
            if (active) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReschedule,
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: const Text('Reagendar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onCancel,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.active,
    required this.cancelled,
  });
  final String label;
  final bool active;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final color = cancelled
        ? AppColors.error
        : active
            ? AppColors.primary
            : AppColors.textSubtle;
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

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
