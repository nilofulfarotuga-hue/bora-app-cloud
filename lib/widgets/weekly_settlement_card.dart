import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FASE 4 — Cartão semanal de settlement do estafeta.
/// Mostra resumo da semana actual (segunda → domingo Lisbon), detalhe por
/// pedido, histórico semanas anteriores e configuração MBWay.
class WeeklySettlementCard extends StatefulWidget {
  const WeeklySettlementCard({super.key});

  @override
  State<WeeklySettlementCard> createState() => _WeeklySettlementCardState();
}

class _WeeklySettlementCardState extends State<WeeklySettlementCard> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<dynamic> _orders = const [];
  List<dynamic> _history = const [];
  String? _mbwayPhone;

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
      final r = await Supabase.instance.client
          .rpc('get_driver_current_week_summary');
      if (!mounted) return;
      final data = r as Map<String, dynamic>;
      setState(() {
        _summary = data['summary'] as Map<String, dynamic>?;
        _orders = (data['orders'] as List?) ?? const [];
        _history = (data['history'] as List?) ?? const [];
        _mbwayPhone = data['mbway_phone'] as String?;
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

  Future<void> _editMbway() async {
    final ctrl = TextEditingController(text: _mbwayPhone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MBWay para settlements'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número MBWay',
            hintText: '+351 912 345 678',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await Supabase.instance.client
          .rpc('update_driver_mbway_phone', params: {'p_phone': result});
      if (!mounted) return;
      setState(() => _mbwayPhone = result.isEmpty ? null : result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MBWay actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  String _fmtEur(num? v) =>
      '€${(v ?? 0).toDouble().toStringAsFixed(2)}';

  String _fmtDateRange(Map<String, dynamic> s) {
    final ws = DateTime.tryParse(s['week_start'] as String? ?? '')?.toLocal();
    final we = DateTime.tryParse(s['week_end'] as String? ?? '')?.toLocal();
    if (ws == null || we == null) return '';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(ws.day)}/${pad(ws.month)} → ${pad(we.day)}/${pad(we.month)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Erro ao carregar settlement: $_error',
                  style: TextStyle(color: Colors.red.shade800)),
              TextButton(onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_summary == null) return const SizedBox.shrink();

    final s = _summary!;
    final net = (s['net_balance'] as num?)?.toDouble() ?? 0;
    final direction = s['direction'] as String? ?? 'zero';
    final isPay = direction == 'bora_pays_driver';
    final isOwe = direction == 'driver_pays_bora';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Resumo semana actual ────────────────────────────────────────
        Card(
          color: isOwe ? Colors.orange.shade50 : Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Esta semana',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(_fmtDateRange(s),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 12),
                _row('Entregas', '${s['total_deliveries'] ?? 0}'),
                _row('Ganhos brutos', _fmtEur(s['total_earnings'] as num?)),
                _row('Cash recebido (cliente)',
                    _fmtEur(s['total_cash_received'] as num?)),
                _row('Tokens convertidos',
                    _fmtEur(s['tokens_converted_value'] as num?)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isOwe
                          ? '💸 A entregar à Bora'
                          : isPay
                              ? '💚 A receber'
                              : 'Saldo',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _fmtEur(net.abs()),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isOwe
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                if (isOwe || isPay) ...[
                  const SizedBox(height: 4),
                  Text(
                    isOwe
                        ? 'Vais pagar via MBWay segunda-feira'
                        : 'Bora vai transferir segunda-feira',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
                const SizedBox(height: 12),
                // MBWay config
                InkWell(
                  onTap: _editMbway,
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _mbwayPhone == null || _mbwayPhone!.isEmpty
                              ? 'Configurar MBWay (obrigatório)'
                              : 'MBWay: $_mbwayPhone',
                          style: TextStyle(
                            fontSize: 13,
                            color: _mbwayPhone == null
                                ? Colors.red.shade700
                                : Colors.black87,
                            fontWeight: _mbwayPhone == null
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit_outlined, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Detalhe por pedido ──────────────────────────────────────────
        if (_orders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Detalhe por pedido',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final o in _orders) _buildOrderRow(o as Map),
                ],
              ),
            ),
          ),
        ],

        // ── Histórico ───────────────────────────────────────────────────
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Histórico (${_history.length})',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            children: [
              for (final h in _history) _buildHistoryRow(h as Map),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOrderRow(Map o) {
    final method = o['payment_method'] as String? ?? '';
    final isCash = method == 'cash';
    final finalTotal = (o['finalTotal'] as num?)?.toDouble() ?? 0;
    final earnings = (o['driver_earnings'] as num?)?.toDouble() ?? 0;
    final net = (o['net_per_order'] as num?)?.toDouble() ?? 0;
    final dt = DateTime.tryParse(o['delivered_at'] as String? ?? '')
        ?.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final when = dt == null
        ? '—'
        : '${pad(dt.day)}/${pad(dt.month)} ${pad(dt.hour)}:${pad(dt.minute)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(when, style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              Text(isCash ? '💵 Cash' : '💳 Card',
                  style: const TextStyle(fontSize: 11)),
              const Spacer(),
              Text('Total ${_fmtEur(finalTotal)}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Ganhei: ${_fmtEur(earnings)}'
            '${isCash ? "  Cash recebido: ${_fmtEur(finalTotal)}" : ""}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            net >= 0
                ? 'Acerto: +${_fmtEur(net)} (Bora deve)'
                : 'Acerto: −${_fmtEur(-net)} (devo à Bora)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: net >= 0 ? Colors.green.shade800 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(Map h) {
    final ws = DateTime.tryParse(h['week_start_at'] as String? ?? '')
        ?.toLocal();
    final we = DateTime.tryParse(h['week_end_at'] as String? ?? '')?.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final range = (ws == null || we == null)
        ? '—'
        : '${pad(ws.day)}/${pad(ws.month)} → ${pad(we.day)}/${pad(we.month)}';
    final net = (h['net_balance'] as num?)?.toDouble() ?? 0;
    final status = h['status'] as String? ?? 'pending';
    final color = switch (status) {
      'paid' || 'received' => Colors.green.shade700,
      'pending' => Colors.orange.shade700,
      'disputed' => Colors.red.shade700,
      _ => Colors.grey.shade700,
    };
    return ListTile(
      dense: true,
      leading: Icon(Icons.receipt_outlined, size: 18, color: color),
      title: Text(range, style: const TextStyle(fontSize: 13)),
      subtitle: Text('${h['total_deliveries']} entregas · saldo ${_fmtEur(net)}',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(status.toUpperCase(),
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
