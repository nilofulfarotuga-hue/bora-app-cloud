import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';

/// M2 (2026-06-12) — "O meu fecho semanal" do parceiro. SÓ LEITURA, PT-PT.
/// Transparência total: o parceiro vê o que a Bora vê, zero ações.
///
/// Duas variantes (estruturas de backend diferentes):
/// - [PartnerWeeklyCloseoutCard] — restaurantes/lojas parceiras, via RPC
///   `partner_my_weekly_closeout(p_restaurant_id)` (current_week calculado
///   ao momento + histórico de partner_weekly_settlements, 8 semanas).
/// - [ProviderWeeklyPayoutCard] — vertical Serviços/Barbearias, via SELECT
///   direto a `appointment_payouts` (RLS own-read; valores em cents).

String _euros(num v) =>
    '€${v.toDouble().abs().toStringAsFixed(2).replaceAll('.', ',')}';

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}';
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

/// "€X a receber da Bora" (verde) / "€X a entregar à Bora" (laranja) /
/// "Sem saldo esta semana" (cinza).
(String, Color) _netLabel(String direction, double net) {
  if (direction.startsWith('bora_pays')) {
    return ('${_euros(net)} a receber da Bora', AppColors.primary);
  }
  if (direction.endsWith('_pays_bora')) {
    return ('${_euros(net)} a entregar à Bora', AppColors.accent);
  }
  return ('Sem saldo esta semana', AppColors.textSecondary);
}

String _statusPt(String? status) => switch (status) {
      'pending' => 'Pendente',
      'paid' => 'Pago',
      'received' => 'Recebido',
      'disputed' => 'Em análise',
      _ => status ?? '',
    };

// ─── Restaurantes / lojas parceiras ─────────────────────────────────────────

class PartnerWeeklyCloseoutCard extends StatefulWidget {
  const PartnerWeeklyCloseoutCard({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<PartnerWeeklyCloseoutCard> createState() =>
      _PartnerWeeklyCloseoutCardState();
}

class _PartnerWeeklyCloseoutCardState extends State<PartnerWeeklyCloseoutCard> {
  late Future<Map<String, dynamic>> _future;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'partner_my_weekly_closeout',
      params: {'p_restaurant_id': widget.restaurantId},
    );
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          // Falha silenciosa — cartão informativo não pode partir o dashboard.
          return const SizedBox.shrink();
        }
        final data = snap.data!;
        final current = data['current_week'] is Map
            ? Map<String, dynamic>.from(data['current_week'] as Map)
            : <String, dynamic>{};
        final history = data['history'] is List
            ? (data['history'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];

        final orders = _num(current['total_orders']).toInt();
        final gross = _num(current['gross_sales']);
        final net = _num(current['net_balance']);
        final direction = (current['direction'] as String?) ?? 'zero';
        final (netText, netColor) = _netLabel(direction, net);

        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg)),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: Spacing.xs),
                    Text('O meu fecho semanal',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Esta semana (${_fmtDate(current['week_start']?.toString())}'
                  ' → ${_fmtDate(current['week_end']?.toString())}): '
                  '$orders pedido${orders == 1 ? '' : 's'} · '
                  '${_euros(gross)} brutos',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(netText,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: netColor)),
                const Text(
                  'O fecho é feito todas as segundas-feiras.',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xs),
                  InkWell(
                    onTap: () =>
                        setState(() => _showHistory = !_showHistory),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showHistory
                              ? 'Esconder semanas anteriores'
                              : 'Ver semanas anteriores (${history.length})',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                        Icon(
                          _showHistory
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  if (_showHistory) ...[
                    const Divider(height: Spacing.lg),
                    ...history.map(_historyLine),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _historyLine(Map<String, dynamic> h) {
    final orders = _num(h['total_orders']).toInt();
    final net = _num(h['net_balance']);
    final direction = (h['direction'] as String?) ?? 'zero';
    final (netText, netColor) = _netLabel(direction, net);
    final status = _statusPt(h['status']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Semana ${_fmtDate(h['week_start']?.toString())} → '
              '${_fmtDate(h['week_end']?.toString())} · '
              '$orders pedido${orders == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          Text(netText,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: netColor)),
          if (status.isNotEmpty) ...[
            const SizedBox(width: Spacing.xs),
            Text('· $status',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle)),
          ],
        ],
      ),
    );
  }
}

// ─── Serviços / Barbearias (appointment_payouts, valores em cents) ──────────

class ProviderWeeklyPayoutCard extends StatefulWidget {
  const ProviderWeeklyPayoutCard({super.key, required this.providerId});

  final String providerId;

  @override
  State<ProviderWeeklyPayoutCard> createState() =>
      _ProviderWeeklyPayoutCardState();
}

class _ProviderWeeklyPayoutCardState extends State<ProviderWeeklyPayoutCard> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('appointment_payouts')
        .select(
            'week_start_at, week_end_at, total_appointments, total_service_revenue_cents, net_payout_cents, direction, status, paid_at')
        .eq('provider_id', widget.providerId)
        .order('week_start_at', ascending: false)
        .limit(8);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final rows = snap.data ?? const [];
        if (snap.hasError || rows.isEmpty) return const SizedBox.shrink();

        final latest = rows.first;
        final history = rows.skip(1).toList();
        final count = _num(latest['total_appointments']).toInt();
        final revenue = _num(latest['total_service_revenue_cents']) / 100.0;
        final net = _num(latest['net_payout_cents']) / 100.0;
        final direction = (latest['direction'] as String?) ?? 'zero';
        final (netText, netColor) = _netLabel(direction, net);
        final status = _statusPt(latest['status']?.toString());

        return Card(
          margin: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xxs),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg)),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: Spacing.xs),
                    Text('O meu fecho semanal',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Último fecho (${_fmtDate(latest['week_start_at']?.toString())}'
                  ' → ${_fmtDate(latest['week_end_at']?.toString())}): '
                  '$count marcaç${count == 1 ? 'ão' : 'ões'} · '
                  '${_euros(revenue)} em serviços',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(netText,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: netColor)),
                    ),
                    if (status.isNotEmpty)
                      Text(status,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSubtle)),
                  ],
                ),
                const Text(
                  'O fecho é feito todas as segundas-feiras.',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textSubtle),
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xs),
                  InkWell(
                    onTap: () =>
                        setState(() => _showHistory = !_showHistory),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showHistory
                              ? 'Esconder semanas anteriores'
                              : 'Ver semanas anteriores (${history.length})',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                        Icon(
                          _showHistory
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  if (_showHistory) ...[
                    const Divider(height: Spacing.lg),
                    ...history.map(_historyLine),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _historyLine(Map<String, dynamic> h) {
    final count = _num(h['total_appointments']).toInt();
    final net = _num(h['net_payout_cents']) / 100.0;
    final direction = (h['direction'] as String?) ?? 'zero';
    final (netText, netColor) = _netLabel(direction, net);
    final status = _statusPt(h['status']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Semana ${_fmtDate(h['week_start_at']?.toString())} → '
              '${_fmtDate(h['week_end_at']?.toString())} · '
              '$count marcaç${count == 1 ? 'ão' : 'ões'}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          Text(netText,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: netColor)),
          if (status.isNotEmpty) ...[
            const SizedBox(width: Spacing.xs),
            Text('· $status',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle)),
          ],
        ],
      ),
    );
  }
}
