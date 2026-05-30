// BLOCO 3.8 — Admin UI para reembolsos pendentes storeShopping v2.
//
// PT-BR (admin é PT-BR — decisão Danilo 2026-05-08).
// Tab 1 (Pendentes) é a TAB PRINCIPAL. Demais tabs (OCR flagged, CASH,
// Todos) são placeholder nesta versão mínima — serão expandidas em sessão
// futura conforme volume real de operação.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

class AdminReceiptsScreen extends StatefulWidget {
  const AdminReceiptsScreen({super.key});

  @override
  State<AdminReceiptsScreen> createState() => _AdminReceiptsScreenState();
}

class _AdminReceiptsScreenState extends State<AdminReceiptsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reembolsos / Talões'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.notifications_active), text: 'Pendentes'),
            Tab(icon: Icon(Icons.flag), text: 'OCR Flag'),
            Tab(icon: Icon(Icons.history), text: 'Histórico CASH'),
            Tab(icon: Icon(Icons.list), text: 'Todos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ReceiptsList(filter: _ReceiptFilter.pendingAdmin),
          _ReceiptsList(filter: _ReceiptFilter.ocrFlagged),
          _HistoricoTab(),
          _ReceiptsList(
              filter: _ReceiptFilter.all, paginated: true),
        ],
      ),
    );
  }
}

enum _ReceiptFilter { pendingAdmin, ocrFlagged, cashSettled, all }

class _ReceiptsList extends StatefulWidget {
  const _ReceiptsList({required this.filter, this.paginated = false});
  final _ReceiptFilter filter;
  final bool paginated;

  @override
  State<_ReceiptsList> createState() => _ReceiptsListState();
}

class _ReceiptsListState extends State<_ReceiptsList> {
  static const int _pageSize = 50;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _rows = [];
    });
    try {
      var q = Supabase.instance.client
          .from('order_receipts_v2')
          .select('id, order_id, photo_url, driver_typed_total_cents, '
              'ocr_extracted_total_cents, ocr_diff_cents, ocr_flagged, '
              'ocr_ran_at, reimbursement_status, reimbursement_amount_cents, '
              'reimbursement_admin_notes, created_at');
      switch (widget.filter) {
        case _ReceiptFilter.pendingAdmin:
          q = q.eq('reimbursement_status', 'pending_admin');
          break;
        case _ReceiptFilter.ocrFlagged:
          // Decisão TODO 5: ocr_flagged=true OU abs(diff_cents) > 100
          q = q.or('ocr_flagged.eq.true,ocr_diff_cents.gt.100,ocr_diff_cents.lt.-100');
          break;
        case _ReceiptFilter.cashSettled:
          q = q.eq('reimbursement_status', 'cash_settled');
          break;
        case _ReceiptFilter.all:
          break;
      }
      final pendingAscending = widget.filter == _ReceiptFilter.pendingAdmin;
      final from = append ? _rows.length : 0;
      final to = from + _pageSize - 1;
      final builder = q.order('created_at', ascending: pendingAscending);
      final data = widget.paginated
          ? await builder.range(from, to)
          : await builder;
      final fresh = List<Map<String, dynamic>>.from(data);
      if (mounted) {
        setState(() {
          _rows = append ? [..._rows, ...fresh] : fresh;
          _hasMore = widget.paginated && fresh.length == _pageSize;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Erro: $_error'));
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          'Nenhum talão neste filtro.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length + (widget.paginated && _hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _rows.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _load(append: true),
                  icon: const Icon(Icons.expand_more),
                  label: Text(_loading ? 'A carregar...' : 'Carregar mais 50'),
                ),
              ),
            );
          }
          return _ReceiptCard(
            row: _rows[i],
            onAfterAction: () => _load(),
          );
        },
      ),
    );
  }
}

// ─── Tab 3: Histórico com filtros ──────────────────────────────────────────

class _HistoricoTab extends StatefulWidget {
  const _HistoricoTab();

  @override
  State<_HistoricoTab> createState() => _HistoricoTabState();
}

class _HistoricoTabState extends State<_HistoricoTab> {
  DateTimeRange? _dateRange;
  String? _driverIdFilter;
  String _statusFilter = 'todos';
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;

  static const _statusOptions = {
    'todos': 'Todos',
    'admin_paid': 'Pago',
    'rejected': 'Rejeitado',
    'cash_settled': 'CASH',
  };

  @override
  void initState() {
    super.initState();
    _loadDrivers();
    _load();
  }

  Future<void> _loadDrivers() async {
    try {
      final data = await Supabase.instance.client
          .from('drivers')
          .select('id, name')
          .order('name');
      if (mounted) {
        setState(() => _drivers = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {/* silent */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var q = Supabase.instance.client
          .from('order_receipts_v2')
          .select('id, order_id, photo_url, driver_typed_total_cents, '
              'ocr_extracted_total_cents, ocr_diff_cents, ocr_flagged, '
              'ocr_ran_at, reimbursement_status, reimbursement_amount_cents, '
              'reimbursement_admin_notes, created_at');

      if (_statusFilter == 'todos') {
        q = q.inFilter('reimbursement_status',
            ['admin_paid', 'rejected', 'cash_settled']);
      } else {
        q = q.eq('reimbursement_status', _statusFilter);
      }
      if (_dateRange != null) {
        q = q
            .gte('created_at', _dateRange!.start.toIso8601String())
            .lte('created_at', _dateRange!.end
                .add(const Duration(days: 1))
                .toIso8601String());
      }
      // Driver filter via JOIN orders: filtramos client-side por simplicidade
      final data = await q.order('created_at', ascending: false).limit(200);
      var rows = List<Map<String, dynamic>>.from(data);

      if (_driverIdFilter != null && _driverIdFilter!.isNotEmpty) {
        // Lookup driver assignments
        final orderIds = rows.map((r) => r['order_id'] as String).toList();
        if (orderIds.isNotEmpty) {
          final orders = await Supabase.instance.client
              .from('orders')
              .select('id, assigned_driver_id')
              .inFilter('id', orderIds);
          final keepIds = (orders as List)
              .where((o) => o['assigned_driver_id'] == _driverIdFilter)
              .map((o) => o['id'] as String)
              .toSet();
          rows = rows.where((r) => keepIds.contains(r['order_id'])).toList();
        }
      }

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _resetFilters() {
    setState(() {
      _dateRange = null;
      _driverIdFilter = null;
      _statusFilter = 'todos';
    });
    _load();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: AppColors.surface,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(
                  _dateRange == null
                      ? 'Período'
                      : '${_fmt(_dateRange!.start)} → ${_fmt(_dateRange!.end)}',
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  initialValue: _driverIdFilter,
                  decoration: const InputDecoration(
                    labelText: 'Entregador',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todos')),
                    ..._drivers.map((d) => DropdownMenuItem<String?>(
                          value: d['id'] as String,
                          child: Text((d['name'] as String?) ?? '—'),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() => _driverIdFilter = v);
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: _statusOptions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _statusFilter = v);
                    _load();
                  },
                ),
              ),
              TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Resetar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Erro: $_error'))
                  : _rows.isEmpty
                      ? Center(
                          child: Text('Sem resultados.',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _rows.length,
                            itemBuilder: (_, i) => _ReceiptCard(
                              row: _rows[i],
                              onAfterAction: _load,
                            ),
                          ),
                        ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _ReceiptCard extends StatefulWidget {
  const _ReceiptCard({required this.row, required this.onAfterAction});
  final Map<String, dynamic> row;
  final VoidCallback onAfterAction;

  @override
  State<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends State<_ReceiptCard> {
  bool _busy = false;
  late final Future<String?> _photoFuture;
  String? _driverMbway;
  String? _driverName;

  @override
  void initState() {
    super.initState();
    final rawUrl = (widget.row['photo_url'] as String?) ?? '';
    _photoFuture =
        rawUrl.isNotEmpty ? _getReceiptSignedUrl(rawUrl) : Future.value(null);
    _loadExtras();
  }

  Future<String?> _getReceiptSignedUrl(String photoUrl) async {
    try {
      if (photoUrl.startsWith('http')) return photoUrl;
      final clean = photoUrl.replaceFirst(RegExp(r'^receipts/'), '');
      return await Supabase.instance.client.storage
          .from('receipts')
          .createSignedUrl(clean, 3600);
    } catch (e) {
      debugPrint('[AdminReceipts] signed URL error: $e');
      return null;
    }
  }

  Future<void> _loadExtras() async {
    try {
      // Driver MBWay phone
      final orderId = widget.row['order_id'] as String;
      final ord = await Supabase.instance.client
          .from('orders')
          .select('assigned_driver_id')
          .eq('id', orderId)
          .maybeSingle();
      final driverId = ord?['assigned_driver_id'] as String?;
      if (driverId != null && driverId.isNotEmpty) {
        final d = await Supabase.instance.client
            .from('drivers')
            .select('name, mbway_phone')
            .eq('id', driverId)
            .maybeSingle();
        if (mounted) {
          setState(() {
            _driverName = d?['name'] as String?;
            _driverMbway = d?['mbway_phone'] as String?;
          });
        }
      }
    } catch (_) {/* silent */}
  }

  Future<void> _markPaid() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'admin_mark_receipt_paid',
        params: {
          'p_receipt_id': widget.row['id'],
          'p_admin_notes': 'Pago via MBWay (painel admin)',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marcado como pago ✅')),
        );
        widget.onAfterAction();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Rejeitar reembolso'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatório)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Confirmar rejeição'),
            ),
          ],
        );
      },
    );
    if (motivo == null || motivo.isEmpty) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'admin_reject_receipt',
        params: {'p_receipt_id': widget.row['id'], 'p_motivo': motivo},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reembolso rejeitado')),
        );
        widget.onAfterAction();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMbway() async {
    final phone = _driverMbway;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final status = row['reimbursement_status'] as String;
    final typedCents = (row['driver_typed_total_cents'] as int?) ?? 0;
    final ocrCents = row['ocr_extracted_total_cents'] as int?;
    final diffCents = row['ocr_diff_cents'] as int?;
    final flagged = row['ocr_flagged'] as bool? ?? false;
    final ocrRanAt = row['ocr_ran_at'] as String?;
    final orderId = row['order_id'] as String;
    final eur = (typedCents / 100).toStringAsFixed(2);

    return Card(
      color: flagged ? AppColors.error.withAlpha(15) : AppColors.card,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: flagged
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              side: BorderSide(color: AppColors.error.withAlpha(100), width: 1.5),
            )
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pedido #${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length).toUpperCase()}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (flagged) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('⚠️ OCR',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                ],
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _photoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 40,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final signedUrl = snapshot.data;
                if (signedUrl != null) {
                  return GestureDetector(
                    onTap: () => _showPhotoFullscreen(context, signedUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        signedUrl,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 40),
                      ),
                    ),
                  );
                }
                return Container(
                  height: 40,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('Sem foto',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.euro, size: 18),
                const SizedBox(width: 4),
                Text('Talão entregador: €$eur',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            _OcrRow(
              flagged: flagged,
              ocrCents: ocrCents,
              typedCents: typedCents,
              diffCents: diffCents,
              ocrRanAt: ocrRanAt,
            ),
            if (_driverName != null) ...[
              const SizedBox(height: 8),
              Text('Entregador: $_driverName',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              if (_driverMbway != null && _driverMbway!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone, size: 16),
                      const SizedBox(width: 4),
                      Text(_driverMbway!),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _openMbway,
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text('Abrir telefone'),
                      ),
                    ],
                  ),
                ),
            ],
            if (status == 'pending_admin') ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _markPaid,
                      icon: const Icon(Icons.check),
                      label: const Text('Marcar pago'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.close),
                    label: const Text('Rejeitar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
            if (status != 'pending_admin' &&
                row['reimbursement_admin_notes'] != null) ...[
              const SizedBox(height: 6),
              Text('Notas admin: ${row['reimbursement_admin_notes']}',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending_admin':
        color = AppColors.warning;
        label = 'PENDENTE';
        break;
      case 'admin_paid':
        color = AppColors.success;
        label = 'PAGO';
        break;
      case 'cash_settled':
        color = AppColors.info;
        label = 'CASH';
        break;
      case 'rejected':
        color = AppColors.error;
        label = 'REJEITADO';
        break;
      default:
        color = AppColors.textSecondary;
        label = status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  void _showPhotoFullscreen(BuildContext context, String signedUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(signedUrl),
        ),
      ),
    );
  }
}

// ─── Widget OCR status ──────────────────────────────────────────────────────

class _OcrRow extends StatelessWidget {
  const _OcrRow({
    required this.flagged,
    required this.ocrCents,
    required this.typedCents,
    required this.diffCents,
    required this.ocrRanAt,
  });

  final bool flagged;
  final int? ocrCents;
  final int typedCents;
  final int? diffCents;
  final String? ocrRanAt;

  @override
  Widget build(BuildContext context) {
    // OCR ainda não correu
    if (ocrRanAt == null) {
      return Row(children: [
        const Icon(Icons.sync, size: 16, color: AppColors.textSubtle),
        const SizedBox(width: 6),
        const Text('OCR a processar...',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 13)),
      ]);
    }

    // OCR correu mas não conseguiu ler valor
    if (ocrCents == null) {
      return Row(children: [
        const Icon(Icons.help_outline, size: 16, color: AppColors.textSubtle),
        const SizedBox(width: 6),
        const Text('OCR: não conseguiu ler',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 13)),
      ]);
    }

    final ocrEur = (ocrCents! / 100).toStringAsFixed(2);
    final typedEur = (typedCents / 100).toStringAsFixed(2);
    final diffEur = diffCents != null
        ? (diffCents!.abs() / 100).toStringAsFixed(2)
        : null;

    // OCR flagged — diferença > 50 cents
    if (flagged) {
      return Row(children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'OCR: €$ocrEur  (digitado: €$typedEur'
            '${diffEur != null ? " — diferença: €$diffEur" : ""})',
            style: const TextStyle(
                color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ]);
    }

    // OCR OK
    return Row(children: [
      const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
      const SizedBox(width: 6),
      Text('OCR: €$ocrEur ✓',
          style: const TextStyle(
              color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}
