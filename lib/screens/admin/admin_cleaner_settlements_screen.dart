// Admin — Fechamento Semanal · Limpeza (vertical LIMPEZA).
//
// Espelha admin_appointments_payouts_screen.dart (beleza). PT-BR (Regra 6).
//
// RPCs usadas:
//   • admin_list_cleaner_settlements(p_cleaner_id uuid=NULL,
//       p_status text=NULL, p_limit int=200) -> jsonb array (+cleaner_name)
//   • admin_mark_cleaner_settlements_paid(p_cleaner_id uuid,
//       p_payout_external_id uuid=gen_random_uuid(),
//       p_payment_method text='mbway', p_payment_reference text=NULL)
//       -> {success, count, total_cents}
//   • admin_recompute_cleaner_week(p_cleaner_id uuid,
//       p_week_start timestamptz=NULL) -> jsonb (fecho recalculado)
//
// Lê DEFENSIVAMENTE as respostas JSONB para tolerar variações estruturais.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminCleanerSettlementsScreen extends StatefulWidget {
  const AdminCleanerSettlementsScreen({super.key});

  @override
  State<AdminCleanerSettlementsScreen> createState() =>
      _AdminCleanerSettlementsScreenState();
}

class _AdminCleanerSettlementsScreenState
    extends State<AdminCleanerSettlementsScreen> {
  final _supabase = Supabase.instance.client;

  // Filtro por profissional (null = todas).
  List<MapEntry<String, String>> _cleaners = const [];
  String? _selectedCleanerId;
  String _statusFilter = 'pending'; // 'pending' | 'paid' | 'all'

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const _statusOptions = <(String, String)>[
    ('pending', 'Pendentes'),
    ('paid', 'Pagos'),
    ('all', 'Todos'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─── Carregar fechos ────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusParam = _statusFilter == 'all' ? null : _statusFilter;
      final res = await _supabase.rpc(
        'admin_list_cleaner_settlements',
        params: {
          'p_cleaner_id': _selectedCleanerId,
          'p_status': statusParam,
          'p_limit': 200,
        },
      );
      final List<Map<String, dynamic>> rows;
      if (res is List) {
        rows = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (res is Map && res['settlements'] is List) {
        rows = (res['settlements'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        rows = const [];
      }

      // Lista de profissionais presentes (para o dropdown). Mantém todas vistas.
      final map = <String, String>{};
      for (final r in rows) {
        final id = r['cleaner_id']?.toString();
        if (id != null) {
          map[id] = (r['cleaner_name'] as String?) ?? id;
        }
      }
      for (final e in _cleaners) {
        map.putIfAbsent(e.key, () => e.value);
      }
      final list = map.entries.toList()
        ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _cleaners = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar repasses: $e';
        _loading = false;
      });
    }
  }

  // ─── Recalcular semana atual (cria/actualiza o fecho da semana em curso) ─────

  Future<void> _recomputeCurrentWeek() async {
    final cid = _selectedCleanerId;
    if (cid == null) {
      _toast('Selecione uma profissional para recalcular.', AppColors.warning);
      return;
    }
    await _recompute(cid, null);
  }

  // ─── Recalcular a semana de um fecho específico ─────────────────────────────

  Future<void> _recompute(String cleanerId, String? weekStartIso) async {
    setState(() => _busy = true);
    try {
      await _supabase.rpc(
        'admin_recompute_cleaner_week',
        params: {
          'p_cleaner_id': cleanerId,
          'p_week_start': weekStartIso,
        },
      );
      _toast('✔ Semana recalculada.', AppColors.primary);
      await _load();
    } catch (e) {
      _toast('Erro ao recalcular: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Marcar pago (Regra 8: dupla confirmação) ───────────────────────────────

  Future<void> _markPaid() async {
    final cid = _selectedCleanerId;
    if (cid == null) {
      _toast('Selecione uma profissional para marcar como paga.',
          AppColors.warning);
      return;
    }
    final cname = _cleaners
        .firstWhere((e) => e.key == cid, orElse: () => MapEntry(cid, cid))
        .value;

    final pendingRows =
        _rows.where((r) => _rowStatus(r) == 'pending' && _cleanerId(r) == cid);
    final totalPending = _sumNet(pendingRows);
    final countPending = pendingRows.length;

    if (countPending == 0) {
      _toast('Não há repasses pendentes para esta profissional.',
          AppColors.warning);
      return;
    }

    // 1º dialog — confirmar com totais.
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        title: const Text('Marcar repasses como pagos?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profissional: $cname',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: Spacing.xs),
            Text('Repasses pendentes: $countPending · '
                'Total: ${_euros(totalPending)}'),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Esta ação registra que a Bora pagou esse valor à '
                    'profissional de limpeza. É IRREVERSÍVEL.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (firstOk != true || !mounted) return;

    // 2º dialog — digitar "CONFIRMAR".
    final confirmText = await _askConfirmType(context, expected: 'CONFIRMAR');
    if (confirmText != true || !mounted) return;

    final externalId = _newUuidV4();
    setState(() => _busy = true);
    try {
      final res = await _supabase.rpc(
        'admin_mark_cleaner_settlements_paid',
        params: {
          'p_cleaner_id': cid,
          'p_payout_external_id': externalId,
          'p_payment_method': 'mbway',
          'p_payment_reference': externalId,
        },
      );
      final data =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final count = (data['count'] ?? data['marked_count']) as int? ?? 0;
      final totalCents = _readCents(data, 'total_cents') ?? 0;
      _toast('✔ $count repasses marcados como pagos · ${_euros(totalCents)}',
          AppColors.primary);
      await _load();
    } catch (e) {
      _toast('Erro ao marcar: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  String _euros(int cents) => '€${(cents / 100.0).toStringAsFixed(2)}';

  int? _readCents(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  int _net(Map<String, dynamic> r) =>
      (r['net_payout_cents'] as num?)?.toInt() ?? 0;

  int _sumNet(Iterable<Map<String, dynamic>> rows) =>
      rows.fold<int>(0, (s, r) => s + _net(r));

  String? _cleanerId(Map<String, dynamic> r) => r['cleaner_id']?.toString();

  String _rowStatus(Map<String, dynamic> r) =>
      (r['status'] as String?) ?? 'pending';

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  /// Random v4 UUID (pure Dart, sem package extra).
  String _newUuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int i, int n) => List.generate(
        n, (k) => b[i + k].toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 2)}-${hex(6, 2)}-${hex(8, 2)}-${hex(10, 6)}';
  }

  Future<bool?> _askConfirmType(BuildContext ctx,
      {required String expected}) async {
    final ctrl = TextEditingController();
    bool ok = false;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) => AlertDialog(
          title: const Text('Confirmação final'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Digite "$expected" para confirmar.'),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: expected,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setSt(() => ok = v.trim() == expected),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: ok ? () => Navigator.pop(dialogCtx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Fechamento Semanal — Limpeza',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilters(),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedCleanerId,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Profissional',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.sm),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas', style: TextStyle(fontSize: 13))),
                ..._cleaners.map((p) => DropdownMenuItem<String?>(
                      value: p.key,
                      child: Text(p.value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedCleanerId = v);
                _load();
              },
            ),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.sm),
              ),
              items: _statusOptions
                  .map((s) => DropdownMenuItem<String>(
                        value: s.$1,
                        child:
                            Text(s.$2, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _statusFilter = v);
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: Spacing.md),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildSummaryCard(),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final pending = _sumNet(_rows.where((r) => _rowStatus(r) == 'pending'));
    final paid = _sumNet(_rows.where((r) => _rowStatus(r) == 'paid'));
    final countPending = _rows.where((r) => _rowStatus(r) == 'pending').length;
    final countPaid = _rows.where((r) => _rowStatus(r) == 'paid').length;
    final canMark = _selectedCleanerId != null && countPending > 0 && !_busy;
    final canRecompute = _selectedCleanerId != null && !_busy;

    return Card(
      margin: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _stat('Pendentes', _euros(pending),
                      sub: '$countPending repasses', color: AppColors.warning),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _stat('Já pagos', _euros(paid),
                      sub: '$countPaid repasses', color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            FilledButton.icon(
              onPressed: canMark ? _markPaid : null,
              icon: const Icon(Icons.check_circle),
              label: Text(
                _selectedCleanerId == null
                    ? 'Selecione 1 profissional p/ marcar'
                    : countPending > 0
                        ? 'Marcar como pagos ($countPending)'
                        : 'Sem pendentes',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            OutlinedButton.icon(
              onPressed: canRecompute ? _recomputeCurrentWeek : null,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Recalcular semana atual'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String v, {String? sub, Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.xxs),
          Text(v,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color ?? AppColors.textPrimary,
              )),
          if (sub != null)
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle)),
        ],
      );

  Widget _buildList() {
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xxl),
          child: Text('Sem repasses neste filtro.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.xs),
      itemBuilder: (_, i) => _buildRow(_rows[i]),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final net = _net(r);
    final status = _rowStatus(r);
    final isPending = status == 'pending';
    final weekStart = r['week_start_at']?.toString();
    final weekEnd = r['week_end_at']?.toString();
    final jobs = (r['total_jobs'] as num?)?.toInt() ?? 0;
    final fee = (r['total_bora_fee_cents'] as num?)?.toInt() ?? 0;
    final paidAt = r['paid_at']?.toString();
    final cleanerName = r['cleaner_name'] as String?;
    final cid = _cleanerId(r);

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xxs),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm + 2, Spacing.sm, Spacing.sm + 2),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 48,
              decoration: BoxDecoration(
                color: isPending ? AppColors.warning : AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _euros(net),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.xs + 2, vertical: Spacing.xxs),
                        decoration: BoxDecoration(
                          color: isPending
                              ? AppColors.warning.withValues(alpha: 0.15)
                              : AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isPending ? 'PENDENTE' : status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isPending
                                ? AppColors.warning
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xxs),
                  if (cleanerName != null)
                    Text(cleanerName,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  Text(
                    'Semana ${_fmtDate(weekStart)} → ${_fmtDate(weekEnd)} · '
                    '$jobs serviços · taxa Bora ${_euros(fee)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (paidAt != null)
                    Text('Pago ${_fmtDateTime(paidAt)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSubtle)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.calculate_outlined, size: 20),
              tooltip: 'Recalcular esta semana',
              onPressed: (_busy || cid == null)
                  ? null
                  : () => _recompute(cid, weekStart),
            ),
          ],
        ),
      ),
    );
  }
}
