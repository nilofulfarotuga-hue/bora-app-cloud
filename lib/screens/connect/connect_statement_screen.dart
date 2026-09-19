import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// "Extrato" — Stripe Connect Express, Fase 1 (2026-08-06).
///
/// Lê a RPC `get_statement` (o servidor resolve o dono pelo JWT — o ecrã nunca
/// envia ids). Mostra as linhas do período + totais e exporta PDF com o mesmo
/// detalhe. Enquanto `stripe_connect_enabled=false` funciona na mesma, com o
/// rodapé "Pagamento ainda por transferência bancária."
class ConnectStatementScreen extends StatefulWidget {
  const ConnectStatementScreen({super.key});

  @override
  State<ConnectStatementScreen> createState() => _ConnectStatementScreenState();
}

enum _Period { today, week, month }

class _ConnectStatementScreenState extends State<ConnectStatementScreen> {
  _Period _period = _Period.week;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic> _totals = {};
  bool _connectEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final to = startOfDay.add(const Duration(days: 1));
    switch (_period) {
      case _Period.today:
        return (startOfDay, to);
      case _Period.week:
        // Semana começa na segunda-feira.
        final monday = startOfDay.subtract(Duration(days: now.weekday - 1));
        return (monday, to);
      case _Period.month:
        return (DateTime(now.year, now.month, 1), to);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _range();
      final res = await Supabase.instance.client.rpc('get_statement', params: {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      setState(() {
        _lines = ((map['lines'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totals = map['totals'] is Map
            ? Map<String, dynamic>.from(map['totals'])
            : {};
        _connectEnabled = map['connect_enabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o extrato. Tenta novamente.';
        _loading = false;
      });
      debugPrint('[ConnectStatement] load error: $e');
    }
  }

  String _euro(num? cents) {
    final v = (cents ?? 0) / 100.0;
    return '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String _dateShort(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  String _kindLabel(String kind) => switch (kind) {
        'sale' => 'Venda',
        'commission' => 'Comissão Bora',
        'stripe_fee' => 'Taxa de pagamento',
        'payout' => 'Pagamento',
        'adjustment' => 'Acerto',
        _ => kind,
      };

  IconData _kindIcon(String kind) => switch (kind) {
        'sale' => Icons.shopping_bag_outlined,
        'commission' => Icons.percent,
        'stripe_fee' => Icons.credit_card,
        'payout' => Icons.account_balance,
        'adjustment' => Icons.tune,
        _ => Icons.receipt_long,
      };

  String get _periodLabel => switch (_period) {
        _Period.today => 'Hoje',
        _Period.week => 'Esta semana',
        _Period.month => 'Este mês',
      };

  Future<void> _exportPdf() async {
    final rows = _lines
        .map((l) => [
              _dateShort(l['occurred_at'] as String?),
              (l['description'] ?? '').toString(),
              _kindLabel((l['kind'] ?? '').toString()),
              (l['reference'] ?? '').toString(),
              _euro(l['amount_cents'] as num?),
            ])
        .toList();
    rows.add(['', '', '', 'Total vendido', _euro(_totals['sold_cents'] as num?)]);
    rows.add(['', '', '', 'Comissão Bora', '-${_euro(_totals['commission_cents'] as num?)}']);
    rows.add(['', '', '', 'Taxas de pagamento', '-${_euro(_totals['stripe_fee_cents'] as num?)}']);
    rows.add(['', '', '', 'Líquido', _euro(_totals['net_cents'] as num?)]);
    await AdminExportService.instance.exportPdfTable(
      title: 'Extrato Bora',
      subtitle: _periodLabel,
      headers: const ['Data', 'Descrição', 'Tipo', 'Ref.', 'Valor'],
      rows: rows,
      filename: 'extrato_bora.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Extrato',
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportar PDF',
            onPressed: _loading || _lines.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_Period>(
              segments: const [
                ButtonSegment(value: _Period.today, label: Text('Hoje')),
                ButtonSegment(value: _Period.week, label: Text('Esta semana')),
                ButtonSegment(value: _Period.month, label: Text('Este mês')),
              ],
              selected: {_period},
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.error)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_lines.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: Text(
                                      'Sem movimentos neste período.',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Card(
                                child: Column(
                                  children: [
                                    for (final l in _lines) _lineTile(l),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            _totalsCard(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _lineTile(Map<String, dynamic> l) {
    final amount = (l['amount_cents'] as num?) ?? 0;
    final kind = (l['kind'] ?? '').toString();
    final ref = (l['reference'] ?? '').toString();
    return ListTile(
      dense: true,
      leading: Icon(_kindIcon(kind), color: AppColors.primary),
      title: Text((l['description'] ?? '').toString()),
      subtitle: Text(
        '${_dateShort(l['occurred_at'] as String?)} · ${_kindLabel(kind)}'
        '${ref.isNotEmpty ? ' · $ref' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '${amount >= 0 ? '+' : ''}${_euro(amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: amount >= 0 ? AppColors.success : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _totalsCard() {
    final lastPayout = _totals['last_payout_at'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Totais — $_periodLabel',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _totalRow('Total vendido', _euro(_totals['sold_cents'] as num?)),
            _totalRow('Comissão Bora',
                '- ${_euro(_totals['commission_cents'] as num?)}'),
            _totalRow('Taxas de pagamento',
                '- ${_euro(_totals['stripe_fee_cents'] as num?)}'),
            if (((_totals['adjustment_cents'] as num?) ?? 0) != 0)
              _totalRow(
                  'Acertos', _euro(_totals['adjustment_cents'] as num?)),
            const Divider(),
            _totalRow('Líquido', _euro(_totals['net_cents'] as num?),
                bold: true),
            const SizedBox(height: 8),
            if (lastPayout != null)
              Text(
                'Pago pela Stripe ✅ a ${_dateShort(lastPayout)}',
                style: const TextStyle(
                    color: AppColors.success, fontWeight: FontWeight.w600),
              ),
            if (!_connectEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Pagamento ainda por transferência bancária.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
