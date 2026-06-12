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
  // F2: fechos dos PARCEIROS + totais da Bora na mesma semana.
  Map<String, dynamic>? _partnerData;
  Map<String, dynamic>? _boraTotals;
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
      final anchor = _anchorForOffset().toIso8601String();
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase.rpc('admin_list_settlements_for_week',
            params: {'p_week_start': anchor}),
        supabase.rpc('admin_list_partner_settlements_for_week',
            params: {'p_week_start': anchor}),
        supabase.rpc('admin_weekly_bora_totals',
            params: {'p_week_start': anchor}),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _partnerData = results[1] as Map<String, dynamic>;
        _boraTotals = results[2] as Map<String, dynamic>;
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

  /// F2 — muda o estado do fecho de um PARCEIRO. "FECHAR SEMANA" (closed)
  /// exige dupla confirmação (regra do Danilo).
  Future<void> _markPartnerStatus(
    Map<String, dynamic> settlement,
    String newStatus,
  ) async {
    String? payRef;
    String? notes;
    if (newStatus == 'closed') {
      final name = settlement['partner_name'] ?? '—';
      final ok1 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fechar a semana?'),
          content: Text(
              'Vai marcar o fecho de "$name" como FECHADO. Os valores deixam '
              'de ser recalculados automaticamente. Continuar?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuar')),
          ],
        ),
      );
      if (ok1 != true || !mounted) return;
      final ok2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmação final'),
          content: const Text('Tem certeza? Esta ação fica no audit log.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('FECHAR SEMANA')),
          ],
        ),
      );
      if (ok2 != true || !mounted) return;
    } else if (newStatus == 'paid' || newStatus == 'received') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(newStatus == 'paid'
              ? 'Marcar PAGO ao parceiro'
              : 'Marcar RECEBIDO do parceiro'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Referência da transferência (opcional)',
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
      if (ok != true || !mounted) return;
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
      if (ok != true || !mounted) return;
      notes = ctrl.text.trim();
      if (notes.isEmpty) return;
    }

    try {
      await Supabase.instance.client.rpc(
        'admin_set_partner_settlement_status',
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
    final partnerSettlements = (_partnerData?['settlements'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Fechos Semanais',
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
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (_boraTotals != null) ...[
                              _buildBoraTotalsCard(),
                              const SizedBox(height: 12),
                            ],
                            const _SectionHeader(
                                icon: Icons.delivery_dining,
                                label: 'Estafetas'),
                            if (settlements.isEmpty)
                              const _EmptyHint(
                                  'Sem entregas de estafetas nesta semana.')
                            else
                              for (final s in settlements) ...[
                                _buildRow(s),
                                const SizedBox(height: 8),
                              ],
                            const SizedBox(height: 12),
                            const _SectionHeader(
                                icon: Icons.storefront, label: 'Parceiros'),
                            if (partnerSettlements.isEmpty)
                              const _EmptyHint(
                                  'Sem vendas de parceiros nesta semana.')
                            else
                              for (final s in partnerSettlements) ...[
                                _buildPartnerRow(s),
                                const SizedBox(height: 8),
                              ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// F2 — Totais da Bora na semana (PT-BR didático).
  Widget _buildBoraTotalsCard() {
    final t = _boraTotals!;
    double n(String k) => (t[k] as num?)?.toDouble() ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💰 Totais da Bora nesta semana',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '${t['orders_count'] ?? 0} pedidos entregues · '
            'Receita total ${_fmtEur(n('orders_revenue'))}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Comissões ganhas ${_fmtEur(n('platform_commissions'))} · '
            'Taxas de serviço ${_fmtEur(n('service_fees'))} · '
            'Entregas ${_fmtEur(n('delivery_fees'))} · '
            'Sacos ${_fmtEur(n('bag_fees'))}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (n('appointment_deposits') > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Sinais de marcações ${_fmtEur(n('appointment_deposits'))}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// F2 — Card de fecho semanal de um PARCEIRO.
  /// Estados: Aberto (pending) → FECHAR SEMANA → Fechado (closed) →
  /// Pago/Recebido. Detalhe expandível em linguagem simples.
  Widget _buildPartnerRow(Map<String, dynamic> s) {
    final direction = s['direction'] as String? ?? 'zero';
    final status = s['status'] as String? ?? 'pending';
    final net = (s['net_balance'] as num?)?.toDouble() ?? 0;
    final isPay = direction == 'bora_pays_partner';
    final isOwe = direction == 'partner_pays_bora';
    final cashKept = (s['cash_kept_by_partner'] as num?)?.toDouble() ?? 0;
    final statusColor = switch (status) {
      'paid' || 'received' => AppColors.success,
      'closed' => AppColors.info,
      'pending' => AppColors.warning,
      'disputed' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    final statusLabel = switch (status) {
      'pending' => 'ABERTO',
      'closed' => 'FECHADO',
      'paid' => 'PAGO',
      'received' => 'RECEBIDO',
      'disputed' => 'DISPUTA',
      _ => status.toUpperCase(),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  (s['partner_name'] as String?) ?? '—',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: statusColor,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              isPay
                  ? '⬅️ Bora transfere ${_fmtEur(net)} ao parceiro'
                  : isOwe
                      ? '➡️ Parceiro deve ${_fmtEur(net)} à Bora'
                      : 'Saldo zero',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isPay
                    ? Colors.green.shade800
                    : isOwe
                        ? Colors.orange.shade800
                        : Colors.grey,
              ),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${s['total_orders'] ?? 0} pedidos entregues\n'
                'Vendas brutas: ${_fmtEur((s['gross_sales'] as num?) ?? 0)}\n'
                'Comissão Bora: ${_fmtEur((s['commission_total'] as num?) ?? 0)}\n'
                'Parte do parceiro: ${_fmtEur((s['partner_share'] as num?) ?? 0)}'
                '${cashKept > 0 ? '\nDinheiro já recebido pelo parceiro (cash na loja): ${_fmtEur(cashKept)} — entra ao contrário' : ''}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, height: 1.5),
              ),
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('FECHAR SEMANA'),
                  onPressed: () => _markPartnerStatus(s, 'closed'),
                ),
              ),
            ],
            if (status == 'closed') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (isPay)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: const Text('Marcar PAGO'),
                        onPressed: () => _markPartnerStatus(s, 'paid'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                  if (isOwe)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Marcar RECEBIDO'),
                        onPressed: () => _markPartnerStatus(s, 'received'),
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
                    onPressed: () => _markPartnerStatus(s, 'disputed'),
                  ),
                ],
              ),
            ],
            if (s['payment_reference'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Ref: ${s['payment_reference']}',
                    style: const TextStyle(fontSize: 11)),
              ),
            if (s['notes'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Notas: ${s['notes']}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ),
          ],
        ),
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

// ── F2: cabeçalho de secção (Estafetas / Parceiros) ───────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style:
              const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}
