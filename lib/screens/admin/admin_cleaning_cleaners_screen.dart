import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/admin_other_role_badge.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../widgets/private_bucket_image.dart';
import '_admin_rpc_errors.dart';

/// Limpeza doméstica — Admin: profissionais de limpeza.
/// Aprovar/recusar candidaturas, suspender/reativar, editar raio/ativo e
/// acertar o caixa semanal (15% das limpezas em dinheiro). Idioma: PT-BR.
class AdminCleaningCleanersScreen extends StatefulWidget {
  const AdminCleaningCleanersScreen({super.key});

  @override
  State<AdminCleaningCleanersScreen> createState() =>
      _AdminCleaningCleanersScreenState();
}

class _AdminCleaningCleanersScreenState
    extends State<AdminCleaningCleanersScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  String? _statusFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_list_cleaners', params: {'p_status': _statusFilter});
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

  Future<void> _review(Map<String, dynamic> c, String action) async {
    final needsReason = action == 'reject' || action == 'suspend';
    final reasonCtrl = TextEditingController();
    final (title, verb) = switch (action) {
      'approve' => ('Aprovar profissional?', 'Aprovar'),
      'reject' => ('Recusar candidatura?', 'Recusar'),
      'suspend' => ('Suspender profissional?', 'Suspender'),
      _ => ('Reativar profissional?', 'Reativar'),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${c['name']} será notificada da decisão.'),
            if (needsReason) ...[
              const SizedBox(height: Spacing.md),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: action == 'approve' || action == 'reactivate'
                      ? AppColors.primary
                      : AppColors.error),
              child: Text(verb)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_review_cleaner', params: {
              'p_cleaner_id': c['id'],
              'p_action': action,
              'p_reason': reasonCtrl.text,
            }),
        'Decisão registrada.');
  }

  Future<void> _editCleaner(Map<String, dynamic> c) async {
    var radius = ((c['service_radius_km'] as num?)?.toDouble() ?? 10)
        .clamp(5.0, 50.0);
    var isActive = c['is_active'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Editar ${c['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Raio: ${radius.round()} km')),
                  Switch(
                    value: isActive,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                  Text(isActive ? 'Ativa' : 'Pausada',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              Slider(
                value: radius,
                min: 5,
                max: 50,
                divisions: 9,
                activeColor: AppColors.primary,
                label: '${radius.round()} km',
                onChanged: (v) => setDialogState(() => radius = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_update_cleaner', params: {
              'p_cleaner_id': c['id'],
              'p_service_radius_km': radius,
              'p_is_active': isActive,
            }),
        'Profissional atualizada.');
  }

  Future<void> _settleCash(Map<String, dynamic> c) async {
    final due = ((c['cash_bora_due_cents'] as num?)?.toInt() ?? 0) / 100;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acertar caixa?'),
        content: Text(
            'Confirma que ${c['name']} entregou os '
            '€${due.toStringAsFixed(2)} de comissão das limpezas em dinheiro. '
            'As reservas passam para "cash_settled".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Confirmar acerto')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_cleaning_mark_cash_settled',
            params: {'p_cleaner_id': c['id']}),
        'Caixa acertado.');
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
        title: 'Profissionais de limpeza',
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pending', child: Text('Pendentes')),
              PopupMenuItem(value: 'approved', child: Text('Aprovadas')),
              PopupMenuItem(value: 'suspended', child: Text('Suspensas')),
              PopupMenuItem(value: 'rejected', child: Text('Recusadas')),
              PopupMenuItem(value: null, child: Text('Todas')),
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
                          child: Text('Nenhuma profissional neste filtro.',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _CleanerCard(
                      data: rows[i],
                      busy: _busy,
                      onReview: (action) => _review(rows[i], action),
                      onEdit: () => _editCleaner(rows[i]),
                      onSettleCash: () => _settleCash(rows[i]),
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

class _CleanerCard extends StatelessWidget {
  const _CleanerCard({
    required this.data,
    required this.busy,
    required this.onReview,
    required this.onEdit,
    required this.onSettleCash,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final void Function(String action) onReview;
  final VoidCallback onEdit;
  final VoidCallback onSettleCash;

  @override
  Widget build(BuildContext context) {
    final status = (data['approval_status'] as String?) ?? 'pending';
    final rating = (data['rating_avg'] as num?)?.toDouble() ?? 0;
    final ratingsCount = (data['ratings_count'] as num?)?.toInt() ?? 0;
    final lateCancels = (data['late_cancels_30d'] as num?)?.toInt() ?? 0;
    final cashDue = (data['cash_bora_due_cents'] as num?)?.toInt() ?? 0;
    final earned = (data['completed_total_cents'] as num?)?.toInt() ?? 0;
    final flagged = data['flagged_low_rating'] == true;

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
                _AvatarThumb(photoUrl: data['photo_url'] as String?),
                const SizedBox(width: 10),
                Expanded(
                  child: Text((data['name'] as String?) ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                _StatusChip(status: status),
              ],
            ),
            // MULTI-PAPEL: sinaliza se esta candidata já é entregador/motorista.
            Align(
              alignment: Alignment.centerLeft,
              child: AdminOtherRoleBadge(
                userId: data['user_id'] as String?,
                show: OtherRole.driver,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${data['phone'] ?? '—'} · ${data['email'] ?? '—'}'
              '${(data['nif'] as String?)?.isNotEmpty == true ? ' · NIF ${data['nif']}' : ''}\n'
              'Base: ${(data['base_address'] as String?)?.isNotEmpty == true ? data['base_address'] : '—'} '
              '· raio ${(data['service_radius_km'] as num?)?.round() ?? 10} km '
              '· ${data['is_active'] == true ? 'ativa' : 'pausada'}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
            if ((data['bio'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('"${data['bio']}"',
                    style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 4),
            Text(
              '${ratingsCount > 0 ? '★ ${rating.toStringAsFixed(1)} ($ratingsCount) · ' : ''}'
              '${(data['cleanings_done'] as num?)?.toInt() ?? 0} limpezas · '
              'ganhou €${(earned / 100).toStringAsFixed(2)}'
              '${lateCancels > 0 ? ' · $lateCancels canc. tardios/30d' : ''}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (flagged)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('⚠️ Nota média baixa nos últimos 10 serviços',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600)),
              ),
            if (cashDue > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '💶 Caixa a acertar: €${(cashDue / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700)),
              ),
            _DocsRow(docs: data['docs']),
            _MaterialsRow(docs: data['docs']),
            _AvailabilityRow(cleanerId: data['id']?.toString() ?? ''),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'pending') ...[
                  FilledButton.icon(
                    onPressed: busy ? null : () => onReview('approve'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aprovar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onReview('reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Recusar'),
                  ),
                ],
                if (status == 'approved') ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Editar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onReview('suspend'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    icon: const Icon(Icons.pause, size: 18),
                    label: const Text('Suspender'),
                  ),
                  if (cashDue > 0)
                    FilledButton.icon(
                      onPressed: busy ? null : onSettleCash,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning),
                      icon: const Icon(Icons.point_of_sale, size: 18),
                      label: const Text('Acertar caixa'),
                    ),
                ],
                if (status == 'suspended' || status == 'rejected')
                  FilledButton.icon(
                    onPressed: busy ? null : () => onReview('reactivate'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reativar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura da foto de perfil (bucket público `avatars`).
class _AvatarThumb extends StatelessWidget {
  const _AvatarThumb({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl ?? '';
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primaryWash,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? const Icon(Icons.person_outline, color: AppColors.primary)
          : null,
    );
  }
}

/// Linha de documentos KYC (paths no bucket privado `cleaner-documents`).
/// Abre preview assinado via PrivateBucketImage.
class _DocsRow extends StatelessWidget {
  const _DocsRow({required this.docs});
  final dynamic docs;

  Map<String, dynamic> get _map =>
      docs is Map ? Map<String, dynamic>.from(docs as Map) : const {};

  static const _labels = {
    'id_doc': 'Documento de ID',
    'address_proof': 'Comprovativo de morada',
  };

  @override
  Widget build(BuildContext context) {
    final entries = _map.entries
        .where((e) => (e.value as String?)?.isNotEmpty == true)
        .toList();
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('⚠️ Sem documentos anexados',
            style: TextStyle(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w600)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in entries)
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_labels[e.key] ?? e.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: PrivateBucketImage(
                            urlOrPath: 'cleaner-documents/${e.value}',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: Text(_labels[e.key] ?? e.key),
            ),
        ],
      ),
    );
  }
}

/// Materiais obrigatórios confirmados na candidatura (lidos de `docs`).
class _MaterialsRow extends StatelessWidget {
  const _MaterialsRow({required this.docs});
  final dynamic docs;

  @override
  Widget build(BuildContext context) {
    final map = docs is Map ? Map<String, dynamic>.from(docs as Map) : const {};
    final ok = map['materials_ok'] == true;
    final list = (map['materials_list'] as List?)?.cast<String>() ?? const [];
    if (!ok && list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('⚠️ Materiais não confirmados',
            style: TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w600)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '🧹 Materiais confirmados${list.isNotEmpty ? ': ${list.join(', ')}' : ''}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Disponibilidade semanal da profissional (admin — read-only via RPC).
class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({required this.cleanerId});
  final String cleanerId;

  static const _weekdaysPt = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

  Future<void> _open(BuildContext context) async {
    List<Map<String, dynamic>> slots = const [];
    try {
      final res = await Supabase.instance.client.rpc(
          'admin_cleaner_availability',
          params: {'p_cleaner_id': cleanerId});
      slots = (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(humanizeAdminRpcError(e))));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disponibilidade semanal'),
        content: slots.isEmpty
            ? const Text('Sem disponibilidade marcada.')
            : SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in slots)
                      Text(
                        '${_weekdaysPt[(s['weekday'] as num).toInt() % 7]}: '
                        '${(s['start_time'] as String).substring(0, 5)}–'
                        '${(s['end_time'] as String).substring(0, 5)}',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cleanerId.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _open(context),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          icon: const Icon(Icons.event_available, size: 16),
          label: const Text('Ver disponibilidade'),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, txt) = switch (status) {
      'approved' => (AppColors.primary, 'Aprovada'),
      'rejected' => (AppColors.error, 'Recusada'),
      'suspended' => (AppColors.error, 'Suspensa'),
      _ => (AppColors.accent, 'Pendente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(txt,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
