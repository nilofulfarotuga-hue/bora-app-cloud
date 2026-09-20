import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import '../stores/order_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';

enum _Period { today, week, month }

class PartnerEarningsScreen extends StatefulWidget {
  const PartnerEarningsScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerEarningsScreen> createState() => _PartnerEarningsScreenState();
}

class _PartnerEarningsScreenState extends State<PartnerEarningsScreen> {
  _Period _period = _Period.week;

  // Reservas — créditos €2 do `restaurant_menu_credits`.
  int _reservationUsedCount = 0;
  int _reservationUsedCents = 0;
  int _reservationPendingCount = 0;
  int _reservationPendingCents = 0;
  bool _reservationsLoading = false;

  // F2 — fecho semanal do parceiro (read-only, transparência total).
  Map<String, dynamic>? _weeklyCloseout;
  bool _closeoutLoading = false;

  // Contas claras (20/09/2026): TODOS os números de dinheiro deste ecrã vêm
  // da RPC extrato_parceiro (order_financials = livro-razão = fecho). O Dart
  // deixou de calcular "subtotal − comissão" — dava 11,45 € onde a loja
  // recebe 10,90 €.
  Map<String, dynamic>? _extrato;
  bool _extratoLoading = false;
  String? _extratoErro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReservationCredits();
        _loadWeeklyCloseout();
        _loadExtrato();
      }
    });
  }

  int _diasDoPeriodo() {
    switch (_period) {
      case _Period.today:
        return 1;
      case _Period.week:
        return 7;
      case _Period.month:
        return 30;
    }
  }

  Future<void> _loadExtrato() async {
    if (!mounted) return;
    setState(() {
      _extratoLoading = true;
      _extratoErro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc(
        'extrato_parceiro',
        params: {
          'p_restaurant_id': widget.restaurant.id,
          'p_dias': _diasDoPeriodo(),
        },
      );
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] != true) throw Exception(m['error'] ?? 'extrato indisponível');
      if (!mounted) return;
      setState(() {
        _extrato = m;
        _extratoLoading = false;
      });
    } catch (e) {
      debugPrint('[PartnerEarnings] extrato_parceiro: $e');
      if (mounted) {
        setState(() {
          _extratoLoading = false;
          _extratoErro = e.toString();
        });
      }
    }
  }

  /// Valor por pedido vindo da RPC (fica para o parceiro), por id do pedido.
  Map<String, double> get _ficaPorPedido {
    final out = <String, double>{};
    for (final p in (_extrato?['pedidos'] as List? ?? const [])) {
      final m = p as Map;
      final c = (m['fica_para_o_parceiro_cents'] as num?)?.toDouble();
      final id = m['pedido_id'] as String?;
      if (id != null && c != null) out[id] = c / 100.0;
    }
    return out;
  }

  Future<void> _loadWeeklyCloseout() async {
    if (!mounted) return;
    setState(() => _closeoutLoading = true);
    try {
      final r = await Supabase.instance.client.rpc(
        'partner_my_weekly_closeout',
        params: {'p_restaurant_id': widget.restaurant.id},
      );
      if (!mounted) return;
      setState(() {
        _weeklyCloseout = r as Map<String, dynamic>?;
        _closeoutLoading = false;
      });
    } catch (e) {
      debugPrint('[PartnerEarnings] weekly closeout: $e');
      if (mounted) setState(() => _closeoutLoading = false);
    }
  }

  void _onPeriodChanged(_Period p) {
    setState(() => _period = p);
    _loadReservationCredits();
    _loadExtrato();
  }

  Future<void> _loadReservationCredits() async {
    if (!mounted) return;
    setState(() => _reservationsLoading = true);
    try {
      final start = _startOfPeriod(DateTime.now());
      final supabase = Supabase.instance.client;

      final usedRows = await supabase
          .from('restaurant_menu_credits')
          .select('amount_cents')
          .eq('restaurant_id', widget.restaurant.id)
          .gte('used_at', start.toIso8601String());

      final pendingRows = await supabase
          .from('restaurant_menu_credits')
          .select('amount_cents')
          .eq('restaurant_id', widget.restaurant.id)
          .filter('used_at', 'is', null);

      if (!mounted) return;
      final used = (usedRows as List).cast<Map<String, dynamic>>();
      final pending = (pendingRows as List).cast<Map<String, dynamic>>();
      setState(() {
        _reservationUsedCount = used.length;
        _reservationUsedCents = used.fold<int>(
            0, (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));
        _reservationPendingCount = pending.length;
        _reservationPendingCents = pending.fold<int>(
            0, (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));
        _reservationsLoading = false;
      });
    } catch (e) {
      debugPrint('[PartnerEarnings] _loadReservationCredits error: $e');
      if (mounted) setState(() => _reservationsLoading = false);
    }
  }

  /// Contas claras: o que fica para a loja em cada pedido vem do servidor
  /// (order_financials). Sem linha da RPC → 0 só para o gráfico; nunca se
  /// calcula aqui.
  double _partnerRevenue(OrderModel order) => _ficaPorPedido[order.id] ?? 0;

  DateTime _startOfPeriod(DateTime now) {
    switch (_period) {
      case _Period.today:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case _Period.month:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
    }
  }

  int _bucketCount() {
    switch (_period) {
      case _Period.today:
        return 1;
      case _Period.week:
        return 7;
      case _Period.month:
        return 30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final now = DateTime.now();
    final start = _startOfPeriod(now);

    final allOrders = orderStore
        .partnerOrdersForRestaurant(widget.restaurant.name)
        .where((o) => o.status == OrderStatus.delivered)
        .toList();

    final periodOrders = allOrders
        .where((o) => !o.createdAt.isBefore(start))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Totais do período: só da RPC (servidor soma). Sem RPC → "—" no ecrã.
    final totais = _extrato?['totais'] as Map?;
    final double? totalEarnings = totais == null
        ? null
        : ((totais['fica_para_o_parceiro_cents'] as num?)?.toDouble() ?? 0) /
            100.0;
    final double? totalCommission = totais == null
        ? null
        : ((totais['parte_bora_cents'] as num?)?.toDouble() ?? 0) / 100.0;
    final double? avgTicket =
        totais == null || totais['media_por_pedido_cents'] == null
            ? null
            : ((totais['media_por_pedido_cents'] as num).toDouble()) / 100.0;
    final pedidosRpc = (_extrato?['pedidos'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: const BoraSupportFab(),
      appBar: const BoraScreenAppBar(title: 'Ganhos'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            _PeriodSelector(
              value: _period,
              onChanged: _onPeriodChanged,
            ),
            const SizedBox(height: Spacing.lg),
            _HeroCard(
              amount: totalEarnings == null
                  ? null
                  : totalEarnings + _reservationUsedCents / 100.0,
              periodLabel: _periodLabel(_period),
              nota: _extratoErro != null
                  ? 'Sem ligação ao servidor: $_extratoErro'
                  : (_extratoLoading ? 'A carregar…' : null),
            ),
            const SizedBox(height: Spacing.lg),
            _KpiRow(
              ordersCount:
                  totais == null ? null : (totais['pedidos'] as num?)?.toInt(),
              avgTicket: avgTicket,
              commission: totalCommission,
              commissionSobre: totais == null
                  ? null
                  : 'sobre ${_eurPt(((totais['produtos_cents'] as num?)?.toDouble() ?? 0) / 100.0)} de produtos',
            ),
            const SizedBox(height: Spacing.lg),
            _ReservationsSection(
              loading: _reservationsLoading,
              usedCount: _reservationUsedCount,
              usedCents: _reservationUsedCents,
              pendingCount: _reservationPendingCount,
              pendingCents: _reservationPendingCents,
              periodLabel: _periodLabel(_period),
            ),
            const SizedBox(height: Spacing.xl),
            // F2 — fecho semanal (espelho do que o admin vê; só leitura).
            _WeeklyCloseoutSection(
              loading: _closeoutLoading,
              data: _weeklyCloseout,
              extrato: _extrato,
            ),
            const SizedBox(height: Spacing.xl),
            if (_period != _Period.today) ...[
              _EarningsChart(
                orders: periodOrders,
                buckets: _bucketCount(),
                startDate: start,
                revenue: _partnerRevenue,
              ),
              const SizedBox(height: Spacing.xl),
            ],
            // 2026-05-21 — A6: Top produtos vendidos + horário de pico.
            _TopProductsSection(orders: periodOrders),
            const SizedBox(height: Spacing.xl),
            _PeakHoursSection(orders: periodOrders),
            const SizedBox(height: Spacing.xl),
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 20, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Pedidos entregues (${totais == null ? '—' : pedidosRpc.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (_extrato == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    _extratoLoading
                        ? 'A carregar…'
                        : 'Sem ligação ao servidor — os pedidos aparecem assim que voltar.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else if (pedidosRpc.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Ainda não há pedidos entregues neste período.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...pedidosRpc.map((p) => _PedidoExtratoTile(pedido: p)),
          ],
        ),
      ),
    );
  }

  static String _eurPt(double v) =>
      '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  String _periodLabel(_Period p) {
    switch (p) {
      case _Period.today:
        return 'Hoje';
      case _Period.week:
        return 'Últimos 7 dias';
      case _Period.month:
        return 'Últimos 30 dias';
    }
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(context, 'Hoje', _Period.today),
        const SizedBox(width: 8),
        _chip(context, 'Semana', _Period.week),
        const SizedBox(width: 8),
        _chip(context, 'Mês', _Period.month),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, _Period p) {
    final selected = p == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(p),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard(
      {required this.amount, required this.periodLabel, this.nota});

  /// null = o servidor ainda não respondeu → mostra "—", nunca 0.
  final double? amount;
  final String periodLabel;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            amount == null
                ? '—'
                : '${amount!.toStringAsFixed(2).replaceAll('.', ',')} €',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nota ??
                'Fica para ti (já sem a parte da Bora) — números do servidor',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.ordersCount,
    required this.avgTicket,
    required this.commission,
    this.commissionSobre,
  });

  final int? ordersCount;
  final double? avgTicket;
  final double? commission;
  /// "sobre 61,26 € de produtos" — nunca "comissão" sem dizer sobre o quê.
  final String? commissionSobre;

  static String _eur(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _kpi(
            icon: Icons.shopping_bag_outlined,
            label: 'Pedidos',
            value: ordersCount == null ? '—' : '$ordersCount',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            icon: Icons.trending_up,
            label: 'Média por pedido',
            value: _eur(avgTicket),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpi(
            icon: Icons.percent,
            label: commissionSobre == null
                ? 'Parte da Bora'
                : 'Parte da Bora\n$commissionSobre',
            value: _eur(commission),
          ),
        ),
      ],
    );
  }

  Widget _kpi(
      {required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EarningsChart extends StatelessWidget {
  const _EarningsChart({
    required this.orders,
    required this.buckets,
    required this.startDate,
    required this.revenue,
  });

  final List<OrderModel> orders;
  final int buckets;
  final DateTime startDate;
  final double Function(OrderModel) revenue;

  @override
  Widget build(BuildContext context) {
    final daily = List<double>.filled(buckets, 0);
    for (final o in orders) {
      final day = DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day);
      final idx = day.difference(startDate).inDays;
      if (idx >= 0 && idx < buckets) {
        daily[idx] += revenue(o);
      }
    }
    final maxVal = daily.fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxVal <= 0 ? 10.0 : maxVal * 1.2;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets) return const SizedBox.shrink();
                  if (buckets == 7 || i % 5 == 0 || i == buckets - 1) {
                    final d = startDate.add(Duration(days: i));
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${d.day}/${d.month}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: daily[i],
                    color: AppColors.primary,
                    width: buckets == 7 ? 18 : 6,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Contas claras (20/09/2026): um pedido do extrato do parceiro, com os
/// quatro números que interessam e a parte da Bora "sobre o quê".
class _PedidoExtratoTile extends StatelessWidget {
  const _PedidoExtratoTile({required this.pedido});

  final Map<String, dynamic> pedido;

  static String _eur(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt();
    final abs = n.abs();
    return '${n < 0 ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
  }

  static String _pagamento(String? p) => switch (p) {
        'cash' => 'dinheiro',
        'mbway' => 'MB Way',
        'card' => 'cartão',
        _ => p ?? '',
      };

  @override
  Widget build(BuildContext context) {
    final cliente = (pedido['cliente'] as String?)?.trim().isNotEmpty ?? false
        ? pedido['cliente'] as String
        : 'Cliente';
    final hora = (pedido['quando_txt'] as String? ?? '');
    final pct = pedido['parte_bora_pct'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$hora · $cliente'
                  '${pedido['takeaway'] == true ? ' · levantamento' : ''}'
                  ' · ${_pagamento(pedido['pagamento'] as String?)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              Text(
                _eur(pedido['fica_para_o_parceiro_cents']),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _linha('O cliente pagou', _eur(pedido['cliente_pagou_cents'])),
          _linha('Produtos', _eur(pedido['produtos_cents'])),
          _linha('Entrega e taxas (cobradas pela Bora ao cliente)',
              _eur(pedido['entrega_e_taxas_cents'])),
          _linha(
              'Parte da Bora ${pedido['sobre_txt'] ?? ''}'
              '${pct == null ? '' : ' (${pct.toString().replaceAll('.', ',')} %)'}',
              _eur(pedido['parte_bora_cents'])),
          _linha('Fica para ti', _eur(pedido['fica_para_o_parceiro_cents']),
              bold: true),
          if (((pedido['recebido_pelo_parceiro_cents'] as num?) ?? 0) > 0)
            _linha('Recebeste em dinheiro (abate no fecho)',
                _eur(pedido['recebido_pelo_parceiro_cents'])),
        ],
      ),
    );
  }

  Widget _linha(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                      color: AppColors.textPrimary))),
          Text(v,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: AppColors.textPrimary)),
        ]),
      );
}

class _ReservationsSection extends StatelessWidget {
  const _ReservationsSection({
    required this.loading,
    required this.usedCount,
    required this.usedCents,
    required this.pendingCount,
    required this.pendingCents,
    required this.periodLabel,
  });

  final bool loading;
  final int usedCount;
  final int usedCents;
  final int pendingCount;
  final int pendingCents;
  final String periodLabel;

  String _euros(int cents) => '€${(cents / 100.0).toStringAsFixed(2)}';

  String _label(int n, String singular, String plural) =>
      n == 1 ? '1 $singular' : '$n $plural';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_seat,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Reservas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Row(
              label:
                  'Créditos usados ($periodLabel)',
              detail: _label(usedCount, 'reserva', 'reservas'),
              amount: _euros(usedCents),
              amountColor: AppColors.primary,
              hint: 'A receber no acerto semanal',
            ),
            const SizedBox(height: 10),
            _Row(
              label: 'Créditos pendentes',
              detail: _label(pendingCount, 'reserva', 'reservas'),
              amount: _euros(pendingCents),
              amountColor: AppColors.textSecondary,
              hint: 'Cliente ainda não usou no restaurante',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.detail,
    required this.amount,
    required this.amountColor,
    required this.hint,
  });

  final String label;
  final String detail;
  final String amount;
  final Color amountColor;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$detail · $hint',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// 2026-05-21 — A6: Top 5 produtos mais vendidos no período.
// Agrega CartItem.name (case-insensitive) por quantidade somada.
class _TopProductsSection extends StatelessWidget {
  const _TopProductsSection({required this.orders});

  final List<OrderModel> orders;

  List<MapEntry<String, int>> _aggregate() {
    final tally = <String, int>{};
    final displayName = <String, String>{};
    for (final o in orders) {
      for (final item in o.items) {
        final key = item.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        tally[key] = (tally[key] ?? 0) + item.quantity;
        displayName.putIfAbsent(key, () => item.name.trim());
      }
    }
    final entries = tally.entries
        .map((e) => MapEntry(displayName[e.key] ?? e.key, e.value))
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final top = _aggregate();
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.trending_up, size: 20, color: AppColors.textPrimary),
              SizedBox(width: 8),
              Text(
                'Produtos mais vendidos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (top.isEmpty)
            const Text(
              'Sem vendas neste período.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ...top.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final name = entry.value.key;
              final qty = entry.value.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: idx == 1
                          ? Colors.amber.shade700
                          : Colors.grey.shade400,
                      child: Text(
                        '$idx',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '$qty un.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// 2026-05-21 — A6: Horário de pico — pedidos por hora do dia (0–23).
class _PeakHoursSection extends StatelessWidget {
  const _PeakHoursSection({required this.orders});

  final List<OrderModel> orders;

  List<int> _hourlyCounts() {
    final counts = List<int>.filled(24, 0);
    for (final o in orders) {
      final h = o.createdAt.toLocal().hour;
      counts[h] += 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final counts = _hourlyCounts();
    final maxCount = counts.fold<int>(0, (a, b) => b > a ? b : a);
    final peakHour =
        counts.indexOf(maxCount).clamp(0, 23);

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.access_time, size: 20, color: AppColors.textPrimary),
              SizedBox(width: 8),
              Text(
                'Horário de pico',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            maxCount == 0
                ? 'Sem pedidos neste período.'
                : 'Hora mais movimentada: ${peakHour.toString().padLeft(2, '0')}:00 — $maxCount pedido${maxCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (h) {
                final c = counts[h];
                final ratio = maxCount == 0 ? 0.0 : c / maxCount;
                final isPeak = c == maxCount && c > 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: (60 * ratio).clamp(2.0, 60.0),
                          decoration: BoxDecoration(
                            color: isPeak
                                ? Colors.orange.shade700
                                : Colors.green.shade600.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (h % 4 == 0)
                          Text(
                            '${h.toString().padLeft(2, '0')}h',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                          )
                        else
                          const SizedBox(height: 9),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── F2: Fecho semanal do parceiro (read-only) ────────────────────────────────
// "Esta semana: X pedidos, €Y brutos, €Z a receber da Bora" + últimas semanas
// com o estado marcado pelo admin (Aberto/Fechado/Pago). Transparência total.
class _WeeklyCloseoutSection extends StatelessWidget {
  const _WeeklyCloseoutSection(
      {required this.loading, required this.data, this.extrato});

  final bool loading;
  final Map<String, dynamic>? data;
  /// Contas claras: transferido / por transferir com datas (RPC extrato_parceiro).
  final Map<String, dynamic>? extrato;

  static String _eurC(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt().abs();
    return '${n ~/ 100},${(n % 100).toString().padLeft(2, '0')} €';
  }

  static String _dataPt(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year}';
  }

  String _eur(num? v) => '€${(v ?? 0).toDouble().abs().toStringAsFixed(2)}';

  String _statusLabel(String? s) => switch (s) {
        'pending' => 'Aberto',
        'closed' => 'Fechado',
        'paid' => 'Pago',
        'received' => 'Recebido',
        'disputed' => 'Em análise',
        _ => '—',
      };

  @override
  Widget build(BuildContext context) {
    final current = data?['current_week'] as Map<String, dynamic>?;
    final history =
        (data?['history'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined,
                  size: 20, color: AppColors.textPrimary),
              SizedBox(width: 8),
              Text(
                'Fecho semanal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ))
          else if (current == null)
            const Text(
              'Sem dados ainda — o fecho aparece aqui após as primeiras vendas.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else ...[
            Text(
              'Esta semana: ${current['total_orders'] ?? 0} pedidos · '
              '${_eur(current['gross_sales'] as num?)} brutos',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Parte da Bora: ${_eur(current['commission_total'] as num?)} '
              'sobre ${_eur(current['gross_sales'] as num?)} de vendas · '
              'fica para ti ${_eur(current['partner_share'] as num?)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              (current['direction'] == 'partner_pays_bora')
                  ? 'A entregar à Bora: ${_eur(current['net_balance'] as num?)}'
                  : 'A receber da Bora: ${_eur(current['net_balance'] as num?)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: (current['direction'] == 'partner_pays_bora')
                    ? Colors.orange.shade800
                    : AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'A Bora fecha a semana todas as segundas e transfere após o fecho.',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (extrato != null) ...[
              const Divider(height: 20, color: AppColors.divider),
              Row(children: [
                const Expanded(
                    child: Text('Já transferido',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
                Text(
                  '${_eurC((extrato!['transferido'] as Map?)?['total_cents'])}'
                  '${(extrato!['transferido'] as Map?)?['ultimo_em'] != null ? ' · último a ${_dataPt((extrato!['transferido'] as Map)['ultimo_em'] as String?)}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Expanded(
                    child: Text('Por transferir',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
                Text(
                  '${_eurC((extrato!['por_transferir'] as Map?)?['total_cents'])}'
                  ' (${(extrato!['por_transferir'] as Map?)?['semanas'] ?? 0} semana(s))',
                  style: const TextStyle(fontSize: 12),
                ),
              ]),
              if ((((extrato!['por_transferir'] as Map?)?['a_entregar_a_bora_cents'] as num?) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    const Expanded(
                        child: Text('A entregar à Bora',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700))),
                    Text(_eurC((extrato!['por_transferir'] as Map)['a_entregar_a_bora_cents']),
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              if ((extrato!['stripe'] as Map?)?['transferencias_activas'] == false)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Transferências automáticas (Stripe) desligadas — os pagamentos saem por MB Way / transferência, marcados pela Bora.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
            ],
            if (history.isNotEmpty) ...[
              const Divider(height: 20, color: AppColors.divider),
              const Text(
                'Semanas anteriores',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              for (final h in history.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _weekLabel(h['week_start'] as String?),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      ),
                      Text(
                        '${_eur(h['net_balance'] as num?)} · ${_statusLabel(h['status'] as String?)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _weekLabel(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    String pad(int n) => n.toString().padLeft(2, '0');
    final end = d.add(const Duration(days: 6));
    return '${pad(d.day)}/${pad(d.month)} – ${pad(end.day)}/${pad(end.month)}';
  }
}
