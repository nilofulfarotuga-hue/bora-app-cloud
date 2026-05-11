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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          indicatorColor: AppColors.accent,
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
          _ReceiptsList(filter: _ReceiptFilter.cashSettled),
          _ReceiptsList(filter: _ReceiptFilter.all),
        ],
      ),
    );
  }
}

enum _ReceiptFilter { pendingAdmin, ocrFlagged, cashSettled, all }

class _ReceiptsList extends StatefulWidget {
  const _ReceiptsList({required this.filter});
  final _ReceiptFilter filter;

  @override
  State<_ReceiptsList> createState() => _ReceiptsListState();
}

class _ReceiptsListState extends State<_ReceiptsList> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
              'reimbursement_status, reimbursement_amount_cents, '
              'reimbursement_admin_notes, created_at');
      switch (widget.filter) {
        case _ReceiptFilter.pendingAdmin:
          q = q.eq('reimbursement_status', 'pending_admin');
          break;
        case _ReceiptFilter.ocrFlagged:
          q = q.eq('ocr_flagged', true);
          break;
        case _ReceiptFilter.cashSettled:
          q = q.eq('reimbursement_status', 'cash_settled');
          break;
        case _ReceiptFilter.all:
          break;
      }
      final data = await q.order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(data);
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
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (_, i) => _ReceiptCard(
          row: _rows[i],
          onAfterAction: _load,
        ),
      ),
    );
  }
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
  String? _signedPhotoUrl;
  String? _driverMbway;
  String? _driverName;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      // Signed URL para foto
      final path = (widget.row['photo_url'] as String?) ?? '';
      if (path.isNotEmpty) {
        final clean = path.replaceFirst(RegExp(r'^receipts/'), '');
        final signed = await Supabase.instance.client.storage
            .from('receipts')
            .createSignedUrl(clean, 60 * 10);
        if (mounted) setState(() => _signedPhotoUrl = signed);
      }
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
    final orderId = row['order_id'] as String;
    final eur = (typedCents / 100).toStringAsFixed(2);

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.symmetric(vertical: 6),
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
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            if (_signedPhotoUrl != null)
              GestureDetector(
                onTap: () => _showPhotoFullscreen(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _signedPhotoUrl!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 40),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.euro, size: 18),
                const SizedBox(width: 4),
                Text('Talão estafeta: €$eur',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            if (ocrCents != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'OCR: €${(ocrCents / 100).toStringAsFixed(2)}'
                  '${diffCents != null ? "  (diff: €${(diffCents / 100).toStringAsFixed(2)})" : ""}'
                  '${flagged ? "  ⚠️" : ""}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (_driverName != null) ...[
              const SizedBox(height: 8),
              Text('Estafeta: $_driverName',
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

  void _showPhotoFullscreen(BuildContext context) {
    if (_signedPhotoUrl == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(_signedPhotoUrl!),
        ),
      ),
    );
  }
}
