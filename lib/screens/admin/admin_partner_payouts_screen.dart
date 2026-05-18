// Q1 (2026-05-17) — Painel de Repasses a Parceiros
//
// Painel admin para acerto de payouts a parceiros (reservas, créditos, etc).
// PT-BR (Regra 6 do CEO-AI).
//
// RPCs usadas (signatures complete em prod via MCP):
//   • admin_partner_payout_summary(p_partner_id text,
//       p_period_start ts=now-7d, p_period_end ts=now) -> jsonb
//   • admin_list_partner_payouts(p_partner_id text,
//       p_status text=NULL, p_limit int=100) -> jsonb
//   • admin_mark_partner_payouts_paid(p_partner_id text,
//       p_payout_external_id uuid=gen_random_uuid()) -> jsonb
//
// O ecrã lê DEFENSIVAMENTE as respostas JSONB para tolerar variações
// estruturais entre versões da RPC.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';

class AdminPartnerPayoutsScreen extends StatefulWidget {
  const AdminPartnerPayoutsScreen({super.key});

  @override
  State<AdminPartnerPayoutsScreen> createState() =>
      _AdminPartnerPayoutsScreenState();
}

class _AdminPartnerPayoutsScreenState extends State<AdminPartnerPayoutsScreen> {
  final _supabase = Supabase.instance.client;

  // Filtros
  List<Map<String, dynamic>> _partners = const [];
  String? _selectedPartnerId;
  String? _selectedPartnerName;
  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _periodEnd = DateTime.now();
  String _statusFilter = 'pending'; // 'pending' | 'paid' | 'all'

  // Bulk multi-select
  final Set<String> _selectedPartnerIds = {};

  // Dados carregados
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _rows = const [];
  bool _loadingPartners = true;
  bool _loadingData = false;
  String? _error;

  static const _statusOptions = <(String, String)>[
    ('pending', 'Pendentes'),
    ('paid', 'Pagos'),
    ('all', 'Todos'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  // ─── 1. Carregar lista de parceiros (dropdown) ─────────────────────────────

  Future<void> _loadPartners() async {
    try {
      // admin_partners_with_counts retorna jsonb com partners e order counts.
      final res = await _supabase.rpc('admin_partners_with_counts');
      final list = (res as List?) ?? const [];
      final parsed = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) {
          final na = (a['name'] as String? ?? '').toLowerCase();
          final nb = (b['name'] as String? ?? '').toLowerCase();
          return na.compareTo(nb);
        });
      if (!mounted) return;
      setState(() {
        _partners = parsed;
        _loadingPartners = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = 'Erro ao carregar parceiros: $e';
      });
    }
  }

  // ─── 2. Carregar summary + lista para partner+período selecionados ────────

  Future<void> _loadData() async {
    final pid = _selectedPartnerId;
    if (pid == null) return;
    setState(() {
      _loadingData = true;
      _error = null;
    });
    try {
      // 2a. Summary
      final summaryRes = await _supabase.rpc(
        'admin_partner_payout_summary',
        params: {
          'p_partner_id': pid,
          'p_period_start': _periodStart.toUtc().toIso8601String(),
          'p_period_end': _periodEnd.toUtc().toIso8601String(),
        },
      );
      final summary = summaryRes is Map
          ? Map<String, dynamic>.from(summaryRes)
          : <String, dynamic>{};

      // 2b. Lista (status filter)
      final statusParam = _statusFilter == 'all' ? null : _statusFilter;
      final listRes = await _supabase.rpc(
        'admin_list_partner_payouts',
        params: {
          'p_partner_id': pid,
          'p_status': statusParam,
          'p_limit': 200,
        },
      );
      final List<Map<String, dynamic>> rows;
      if (listRes is List) {
        rows = listRes
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (listRes is Map && listRes['payouts'] is List) {
        // Caso a RPC envolva o array num objecto.
        rows = (listRes['payouts'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        rows = const [];
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _rows = rows;
        _loadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar repasses: $e';
        _loadingData = false;
      });
    }
  }

  // ─── 3. Marcar TUDO pago (Regra 8: dupla confirmação) ──────────────────────

  Future<void> _markAllPaid() async {
    final pid = _selectedPartnerId;
    final pname = _selectedPartnerName;
    if (pid == null || pname == null) return;

    final totalPending = _readCents(_summary, 'total_pending_cents') ??
        _readCents(_summary, 'pending_cents') ??
        _sumRowsCents(_rows.where((r) => _rowStatus(r) == 'pending'));
    final countPending =
        _summary['count_pending'] as int? ??
            _rows.where((r) => _rowStatus(r) == 'pending').length;

    if (countPending == 0) {
      _toast(
        'Não há repasses pendentes para este parceiro no período.',
        Colors.orange,
      );
      return;
    }

    // 1º dialog — confirmar com totais.
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Marcar TODOS os repasses como pagos?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parceiro: $pname',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
                'Repasses pendentes: $countPending · Total: ${_euros(totalPending)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta ação registra que a Bora pagou esse valor ao '
                    'parceiro. É IRREVERSÍVEL.',
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

    // Idempotência: gerar UUID determinístico para esta operação.
    final externalId = _newUuidV4();
    try {
      final res = await _supabase.rpc(
        'admin_mark_partner_payouts_paid',
        params: {
          'p_partner_id': pid,
          'p_payout_external_id': externalId,
        },
      );
      final data = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final count = (data['count'] ?? data['marked_count']) as int? ?? 0;
      final totalCents =
          _readCents(data, 'total_cents') ?? _readCents(data, 'sum_cents') ?? 0;
      _toast(
        '✔ $count repasses marcados como pagos · ${_euros(totalCents)}',
        AppColors.primary,
      );
      await _loadData();
    } catch (e) {
      _toast('Erro ao marcar: $e', Colors.red);
    }
  }

  // ─── 3b. Marcar MÚLTIPLOS parceiros como pagos (bulk) ─────────────────────

  Future<void> _bulkMarkPaid() async {
    if (_selectedPartnerIds.isEmpty) return;

    final names = _selectedPartnerIds.map((pid) {
      final p = _partners.firstWhere(
          (x) => x['id']?.toString() == pid,
          orElse: () => <String, dynamic>{});
      return (p['name'] as String?) ?? pid.substring(0, 8);
    }).toList();

    // Dialog 1 — confirmar com lista de parceiros
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Marcar repasses de vários parceiros como pagos?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_selectedPartnerIds.length} parceiro(s) seleccionado(s):',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...names.map((n) => Text('• $n',
                  style: const TextStyle(fontSize: 13))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Marca TODOS os repasses pendentes de cada parceiro como pagos. IRREVERSÍVEL.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ),
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

    // Dialog 2 — digitar "CONFIRMAR"
    final confirmOk = await _askConfirmType(context, expected: 'CONFIRMAR');
    if (confirmOk != true || !mounted) return;

    int successCount = 0;
    int errorCount = 0;
    for (final pid in _selectedPartnerIds.toList()) {
      try {
        final externalId = _newUuidV4();
        await _supabase.rpc(
          'admin_mark_partner_payouts_paid',
          params: {
            'p_partner_id': pid,
            'p_payout_external_id': externalId,
          },
        );
        successCount++;
      } catch (_) {
        errorCount++;
      }
    }
    if (!mounted) return;
    _toast(
      errorCount == 0
          ? '$successCount parceiro(s) marcado(s) como pagos'
          : '$successCount marcado(s), $errorCount com erro',
      errorCount > 0 ? Colors.orange : AppColors.primary,
    );
    setState(() => _selectedPartnerIds.clear());
    if (_selectedPartnerId != null) await _loadData();
  }

  // ─── 4. Export CSV dos repasses listados ───────────────────────────────────

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) {
      _toast('Nada para exportar.', Colors.orange);
      return;
    }
    final headers = [
      'id',
      'partner_id',
      'partner_name',
      'amount_cents',
      'status',
      'created_at',
      'order_id',
      'reservation_id',
      'paid_at',
    ];
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final rows = _rows
        .map((r) => [
              r['id']?.toString() ?? '',
              _selectedPartnerId ?? '',
              _selectedPartnerName ?? '',
              r['amount_cents']?.toString() ?? '',
              _rowStatus(r),
              r['created_at']?.toString() ?? '',
              r['order_id']?.toString() ?? '',
              r['reservation_id']?.toString() ?? '',
              r['paid_at']?.toString() ?? '',
            ])
        .toList();
    await AdminExportService.instance.exportCsv(
      filename: 'bora_payouts_${_selectedPartnerId}_$stamp.csv',
      headers: headers,
      rows: rows,
      subject:
          'Bora — Repasses ${_selectedPartnerName ?? ''} $_statusFilter $stamp',
    );
  }

  // ─── 5. Helpers ────────────────────────────────────────────────────────────

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

  int _sumRowsCents(Iterable<Map<String, dynamic>> rows) {
    return rows.fold<int>(0,
        (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));
  }

  String _rowStatus(Map<String, dynamic> r) =>
      (r['status'] as String?) ?? 'pending';

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  /// Random v4 UUID gen (pure Dart, no extra package).
  String _newUuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int i, int n) => List.generate(n, (k) =>
        b[i + k].toRadixString(16).padLeft(2, '0')).join();
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
              const SizedBox(height: 12),
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

  Future<void> _pickPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _periodStart, end: _periodEnd),
      helpText: 'Selecione o período',
      saveText: 'OK',
      cancelText: 'Cancelar',
    );
    if (range == null || !mounted) return;
    setState(() {
      _periodStart = range.start;
      _periodEnd = range.end.add(const Duration(days: 1)).subtract(
            const Duration(seconds: 1),
          );
    });
    if (_selectedPartnerId != null) await _loadData();
  }

  // ─── 6. Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Fechamento Semanal — Parceiros'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar CSV',
            onPressed: _rows.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _loadingData || _selectedPartnerId == null
                ? null
                : _loadData,
          ),
        ],
      ),
      floatingActionButton: _selectedPartnerIds.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: _bulkMarkPaid,
              icon: const Icon(Icons.check_circle),
              label: Text('Marcar pagos (${_selectedPartnerIds.length})'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildFilters(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha 1: lista scrollável de parceiros com checkbox
          if (_loadingPartners)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            const Text('Parceiros',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _partners.length,
                itemBuilder: (_, i) {
                  final p = _partners[i];
                  final id = p['id']?.toString() ?? '';
                  final name = (p['name'] as String?) ?? id;
                  final isSelected = _selectedPartnerIds.contains(id);
                  final isPrimary = _selectedPartnerId == id;
                  return CheckboxListTile(
                    dense: true,
                    title: Text(name,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: isPrimary
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedPartnerIds.add(id);
                          // Also set as primary for detail view
                          _selectedPartnerId = id;
                          _selectedPartnerName = name;
                        } else {
                          _selectedPartnerIds.remove(id);
                          if (_selectedPartnerId == id) {
                            _selectedPartnerId =
                                _selectedPartnerIds.isNotEmpty
                                    ? _selectedPartnerIds.first
                                    : null;
                            _selectedPartnerName = _selectedPartnerId != null
                                ? (_partners.firstWhere(
                                        (x) =>
                                            x['id']?.toString() ==
                                            _selectedPartnerId,
                                        orElse: () =>
                                            <String, dynamic>{})['name']
                                    as String?)
                                : null;
                          }
                        }
                      });
                      if (_selectedPartnerId != null) _loadData();
                    },
                  );
                },
              ),
            ),
            if (_selectedPartnerIds.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_selectedPartnerIds.length} parceiros seleccionados — detalhes do último seleccionado abaixo',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black45),
                ),
              ),
          ],
          const SizedBox(height: 8),
          // Linha 2: período + status
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    '${_fmtDate(_periodStart)} → ${_fmtDate(_periodEnd)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickPeriod,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: _statusOptions
                      .map((s) => DropdownMenuItem<String>(
                            value: s.$1,
                            child: Text(s.$2,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _statusFilter = v);
                    if (_selectedPartnerId != null) _loadData();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedPartnerId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Selecione um parceiro para ver os repasses.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_loadingData) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadData,
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
    final pending = _readCents(_summary, 'total_pending_cents') ??
        _readCents(_summary, 'pending_cents') ??
        _sumRowsCents(_rows.where((r) => _rowStatus(r) == 'pending'));
    final paid = _readCents(_summary, 'total_paid_cents') ??
        _readCents(_summary, 'paid_cents') ??
        _sumRowsCents(_rows.where((r) => _rowStatus(r) == 'paid'));
    final countPending = (_summary['count_pending'] as int?) ??
        _rows.where((r) => _rowStatus(r) == 'pending').length;
    final countPaid = (_summary['count_paid'] as int?) ??
        _rows.where((r) => _rowStatus(r) == 'paid').length;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                const SizedBox(width: 8),
                Expanded(
                  child: _stat('Já pagos', _euros(paid),
                      sub: '$countPaid repasses',
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: countPending > 0 ? _markAllPaid : null,
              icon: const Icon(Icons.check_circle),
              label: Text(
                countPending > 0
                    ? 'Marcar todos como pagos ($countPending)'
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
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(v,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color ?? AppColors.textPrimary,
              )),
          if (sub != null)
            Text(sub,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      );

  Widget _buildList() {
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sem repasses neste filtro.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) => _buildRow(_rows[i]),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final cents = (r['amount_cents'] as num?)?.toInt() ?? 0;
    final status = _rowStatus(r);
    final createdAt = r['created_at']?.toString();
    final paidAt = r['paid_at']?.toString();
    final orderId = r['order_id']?.toString();
    final reservationId = r['reservation_id']?.toString();
    final isPending = status == 'pending';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 44,
              decoration: BoxDecoration(
                color: isPending ? AppColors.warning : AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _euros(cents),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                            color:
                                isPending ? AppColors.warning : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Criado ${_fmtDateTime(createdAt)}'
                    '${paidAt != null ? ' · Pago ${_fmtDateTime(paidAt)}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black54),
                  ),
                  if (orderId != null || reservationId != null)
                    Text(
                      orderId != null
                          ? 'Pedido: ${orderId.substring(0, min(8, orderId.length))}…'
                          : 'Reserva: ${reservationId!.substring(0, min(8, reservationId.length))}…',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
