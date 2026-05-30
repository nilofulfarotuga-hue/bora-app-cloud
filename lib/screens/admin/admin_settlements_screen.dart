import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// FASE 5 — Admin Settlements Screen
/// Lista todos os drivers com entregas na semana indicada + saldo + status.
/// Permite marcar PAGO (Bora→Driver), RECEBIDO (Driver→Bora), DISPUTA.
class AdminSettlementsScreen extends StatefulWidget {
  const AdminSettlementsScreen({super.key});

  @override
  State<AdminSettlementsScreen> createState() =>
      _AdminSettlementsScreenState();
}

class _AdminSettlementsScreenState extends State<AdminSettlementsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  // 0 = semana actual, -1 = anterior, etc.
  int _weekOffset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _anchorForOffset() {
    final now = DateTime.now();
    return now.add(Duration(days: 7 * _weekOffset));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Supabase.instance.client.rpc(
        'admin_list_settlements_for_week',
        params: {'p_week_start': _anchorForOffset().toIso8601String()},
      );
      if (!mounted) return;
      setState(() {
        _data = r as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _markStatus(
    Map<String, dynamic> settlement,
    String newStatus,
  ) async {
    String? payRef;
    String? notes;
    if (newStatus == 'paid' || newStatus == 'received') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(newStatus == 'paid'
              ? 'Marcar PAGO via MBWay'
              : 'Marcar RECEBIDO via MBWay'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Referência MBWay (opcional)',
              hintText: 'ex: 123456',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
      payRef = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
    } else if (newStatus == 'disputed') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Marcar disputa'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo da disputa (obrigatório)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
      notes = ctrl.text.trim();
      if (notes.isEmpty) return;
    }

    try {
      await Supabase.instance.client.rpc(
        'admin_set_settlement_status',
        params: {
          'p_settlement_id': settlement['settlement_id'],
          'p_new_status': newStatus,
          'p_payment_reference': payRef,
          'p_notes': notes,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Marcado como $newStatus')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  String _fmtEur(num? v) =>
      '€${(v ?? 0).toDouble().abs().toStringAsFixed(2)}';

  String _fmtRange() {
    if (_data == null) return '—';
    final ws = DateTime.tryParse(_data!['week_start'] as String? ?? '')
        ?.toLocal();
    final we =
        DateTime.tryParse(_data!['week_end'] as String? ?? '')?.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    if (ws == null || we == null) return '—';
    return '${pad(ws.day)}/${pad(ws.month)} → ${pad(we.day)}/${pad(we.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final settlements =
        (_data?['settlements'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Fechamento Semanal — Estafetas',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Week navigation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _weekOffset--);
                    _load();
                  },
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          _weekOffset == 0
                              ? 'Semana actual (em curso)'
                              : _weekOffset == -1
                                  ? 'Semana anterior'
                                  : 'Semana ${_weekOffset > 0 ? "+$_weekOffset" : _weekOffset}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text(_fmtRange(),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _weekOffset >= 0
                      ? null
                      : () {
                          setState(() => _weekOffset++);
                          _load();
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Erro: $_error'))
                    : settlements.isEmpty
                        ? const Center(
                            child: Text('Sem entregas nesta semana.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: settlements.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) =>
                                  _buildRow(settlements[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> s) {
    final direction = s['direction'] as String? ?? 'zero';
    final status = s['status'] as String? ?? 'pending';
    final net = (s['net_balance'] as num?)?.toDouble() ?? 0;
    final isPay = direction == 'bora_pays_driver';
    final isOwe = direction == 'driver_pays_bora';
    final mbway = s['mbway_phone'] as String?;
    final hasMbway = mbway != null && mbway.isNotEmpty;
    final statusColor = switch (status) {
      'paid' || 'received' => AppColors.success,
      'pending' => AppColors.warning,
      'disputed' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
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
                    (s['driver_name'] as String?) ?? '—',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s['total_deliveries'] ?? 0} entregas · '
              'Cash €${(s['total_cash_received'] as num?)?.toStringAsFixed(2) ?? "0.00"} · '
              'Earnings €${(s['total_earnings'] as num?)?.toStringAsFixed(2) ?? "0.00"}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  hasMbway ? mbway : 'MBWay não configurado',
                  style: TextStyle(
                      fontSize: 11,
                      color: hasMbway
                          ? AppColors.textSecondary
                          : AppColors.error,
                      fontWeight:
                          hasMbway ? FontWeight.w400 : FontWeight.w700),
                ),
              ],
            ),
            const Divider(color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isOwe
                        ? '➡️ Driver paga Bora ${_fmtEur(net)}'
                        : isPay
                            ? '⬅️ Bora paga driver ${_fmtEur(net)}'
                            : 'Saldo zero',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isOwe
                          ? Colors.orange.shade800
                          : isPay
                              ? Colors.green.shade800
                              : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (isPay)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: const Text('Marcar PAGO'),
                        onPressed: () => _markStatus(s, 'paid'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                  if (isOwe)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check_circle_outline,
                            size: 16),
                        label: const Text('Marcar RECEBIDO'),
                        onPressed: () => _markStatus(s, 'received'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  if (isPay || isOwe) const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade600),
                    tooltip: 'Disputa',
                    onPressed: () => _markStatus(s, 'disputed'),
                  ),
                ],
              ),
            ],
            if (s['payment_reference'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ref MBWay: ${s['payment_reference']}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (s['notes'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Notas: ${s['notes']}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
