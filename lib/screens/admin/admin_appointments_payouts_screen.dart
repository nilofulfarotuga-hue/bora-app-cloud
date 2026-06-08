// Admin — Fechamento Semanal · Barbearias (vertical Serviços).
//
// Espelha admin_partner_payouts_screen.dart. PT-BR (Regra 6 do CEO-AI).
//
// RPCs usadas:
//   • admin_list_appointment_payouts(p_provider_id text=NULL,
//       p_status text=NULL, p_limit int=200) -> jsonb array (+provider_name)
//   • admin_mark_appointment_payouts_paid(p_provider_id text,
//       p_payout_external_id uuid=gen_random_uuid())
//       -> {success, count, total_cents}
//
// O ecrã lê DEFENSIVAMENTE as respostas JSONB para tolerar variações
// estruturais entre versões da RPC.

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAppointmentsPayoutsScreen extends StatefulWidget {
  const AdminAppointmentsPayoutsScreen({super.key});

  @override
  State<AdminAppointmentsPayoutsScreen> createState() =>
      _AdminAppointmentsPayoutsScreenState();
}

class _AdminAppointmentsPayoutsScreenState
    extends State<AdminAppointmentsPayoutsScreen> {
  final _supabase = Supabase.instance.client;

  // Filtro por barbearia (null = todas).
  List<MapEntry<String, String>> _providers = const [];
  String? _selectedProviderId;
  String _statusFilter = 'pending'; // 'pending' | 'paid' | 'all'

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
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

  // ─── Carregar payouts (lista completa, filtro em memória p/ providers) ─────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusParam = _statusFilter == 'all' ? null : _statusFilter;
      final res = await _supabase.rpc(
        'admin_list_appointment_payouts',
        params: {
          'p_provider_id': _selectedProviderId,
          'p_status': statusParam,
          'p_limit': 200,
        },
      );
      final List<Map<String, dynamic>> rows;
      if (res is List) {
        rows = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else if (res is Map && res['payouts'] is List) {
        rows = (res['payouts'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        rows = const [];
      }

      // Lista de barbearias presentes (para o dropdown). Mantém todas vistas.
      final provMap = <String, String>{};
      for (final r in rows) {
        final id = r['provider_id']?.toString();
        if (id != null) {
          provMap[id] = (r['provider_name'] as String?) ?? id;
        }
      }
      // Preserva providers já conhecidos mesmo se o filtro actual não os trouxe.
      for (final e in _providers) {
        provMap.putIfAbsent(e.key, () => e.value);
      }
      final provList = provMap.entries.toList()
        ..sort((a, b) =>
            a.value.toLowerCase().compareTo(b.value.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _providers = provList;
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

  // ─── Marcar pago (Regra 8: dupla confirmação) ──────────────────────────────

  Future<void> _markPaid() async {
    final pid = _selectedProviderId;
    if (pid == null) {
      _toast('Selecione uma barbearia para marcar como paga.',
          AppColors.warning);
      return;
    }
    final pname = _providers
            .firstWhere((e) => e.key == pid,
                orElse: () => MapEntry(pid, pid))
            .value;

    final pendingRows =
        _rows.where((r) => _rowStatus(r) == 'pending' && _providerId(r) == pid);
    final totalPending = _sumNet(pendingRows);
    final countPending = pendingRows.length;

    if (countPending == 0) {
      _toast('Não há repasses pendentes para esta barbearia.',
          AppColors.warning);
      return;
    }

    // 1º dialog — confirmar com totais.
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        title: const Text('Marcar repasses como pagos?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Barbearia: $pname',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: Spacing.xs),
            Text(
                'Repasses pendentes: $countPending · Total: ${_euros(totalPending)}'),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Esta ação registra que a Bora pagou esse valor à '
                    'barbearia. É IRREVERSÍVEL.',
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
    try {
      final res = await _supabase.rpc(
        'admin_mark_appointment_payouts_paid',
        params: {
          'p_provider_id': pid,
          'p_payout_external_id': externalId,
        },
      );
      final data =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final count = (data['count'] ?? data['marked_count']) as int? ?? 0;
      final totalCents = _readCents(data, 'total_cents') ??
          _readCents(data, 'sum_cents') ??
          0;
      _toast(
        '✔ $count repasses marcados como pagos · ${_euros(totalCents)}',
        AppColors.primary,
      );
      await _load();
    } catch (e) {
      _toast('Erro ao marcar: $e', AppColors.error);
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

  String? _providerId(Map<String, dynamic> r) => r['provider_id']?.toString();

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

  /// Random v4 UUID (pure Dart, no extra package).
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
        title: 'Fechamento Semanal — Barbearias',
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
              initialValue: _selectedProviderId,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Barbearia',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.sm),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas', style: TextStyle(fontSize: 13))),
                ..._providers.map((p) => DropdownMenuItem<String?>(
                      value: p.key,
                      child: Text(p.value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    )),
              ],
              onChanged: (v) {
                setState(() => _selectedProviderId = v);
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
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
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
        _buildChart(),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final pending = _sumNet(_rows.where((r) => _rowStatus(r) == 'pending'));
    final paid = _sumNet(_rows.where((r) => _rowStatus(r) == 'paid'));
    final countPending = _rows.where((r) => _rowStatus(r) == 'pending').length;
    final countPaid = _rows.where((r) => _rowStatus(r) == 'paid').length;
    final canMark = _selectedProviderId != null && countPending > 0;

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
                      sub: '$countPending repasses',
                      color: AppColors.warning),
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
                _selectedProviderId == null
                    ? 'Selecione 1 barbearia p/ marcar'
                    : countPending > 0
                        ? 'Marcar como pagos ($countPending)'
                        : 'Sem pendentes',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(44),
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

  /// Gráfico: receita Bora (booking fees + corte do sinal) por semana.
  Widget _buildChart() {
    // Agrega por week_start_at.
    final byWeek = <String, int>{};
    for (final r in _rows) {
      final wk = r['week_start_at']?.toString();
      if (wk == null) continue;
      final fees = (r['bora_booking_fees_cents'] as num?)?.toInt() ?? 0;
      final cut = (r['bora_deposit_cut_cents'] as num?)?.toInt() ?? 0;
      byWeek[wk] = (byWeek[wk] ?? 0) + fees + cut;
    }
    if (byWeek.isEmpty) return const SizedBox.shrink();
    final weeks = byWeek.keys.toList()..sort();
    // Mostra no máximo as últimas 8 semanas.
    final shown = weeks.length > 8 ? weeks.sublist(weeks.length - 8) : weeks;
    final maxY = shown
        .map((w) => byWeek[w]!)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();
    if (maxY == 0) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.md, Spacing.sm, Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receita Bora por semana',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: Spacing.md),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY * 1.2,
                  barGroups: [
                    for (var i = 0; i < shown.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: byWeek[shown[i]]!.toDouble(),
                            color: AppColors.primary,
                            width: 18,
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= shown.length) {
                            return const SizedBox();
                          }
                          final lbl = _fmtDate(shown[i]);
                          // dd/MM apenas.
                          return Padding(
                            padding: const EdgeInsets.only(top: Spacing.xs),
                            child: Text(
                              lbl.length >= 5 ? lbl.substring(0, 5) : lbl,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 34),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    final count = (r['total_appointments'] as num?)?.toInt() ?? 0;
    final paidAt = r['paid_at']?.toString();
    final providerName = r['provider_name'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xxs),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm + 2, Spacing.md, Spacing.sm + 2),
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
                          isPending ? 'PENDENTE' : 'PAGO',
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
                  if (providerName != null)
                    Text(providerName,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  Text(
                    'Semana ${_fmtDate(weekStart)} → ${_fmtDate(weekEnd)} · $count marcações',
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
          ],
        ),
      ),
    );
  }
}
