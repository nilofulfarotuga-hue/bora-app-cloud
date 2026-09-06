import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/business_rules.dart' show BRTokens;
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminDriverPaymentsScreen extends StatefulWidget {
  const AdminDriverPaymentsScreen({super.key});

  @override
  State<AdminDriverPaymentsScreen> createState() =>
      _AdminDriverPaymentsScreenState();
}

class _AdminDriverPaymentsScreenState extends State<AdminDriverPaymentsScreen> {
  bool _loading = true;

  List<Map<String, dynamic>> _weeklyEarnings = [];
  // driver_id -> euros convertidos esta semana
  Map<String, double> _weeklyConversions = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _weekStart() {
    final now = DateTime.now().toUtc();
    final weekday = now.weekday;
    return DateTime.utc(now.year, now.month, now.day - (weekday - 1));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;

      final weeklyRaw =
          await supabase.from('v_driver_weekly_earnings').select();
      _weeklyEarnings = List<Map<String, dynamic>>.from(weeklyRaw);

      final weekStart = _weekStart();
      final conversions = await supabase
          .from('driver_transactions')
          .select('driver_id, amount')
          .eq('type', 'token_conversion')
          .gte('created_at', weekStart.toIso8601String());

      final map = <String, double>{};
      for (final row in (conversions as List)) {
        final id = row['driver_id'] as String?;
        final amt = (row['amount'] as num?)?.toDouble() ?? 0;
        if (id == null) continue;
        map[id] = (map[id] ?? 0) + amt;
      }
      _weeklyConversions = map;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pagamentos — Estafetas',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(
                    title: 'Resumo Semanal',
                    count: _weeklyEarnings.length,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pagamento semanal automático. Total = ganhos + conversões de tokens.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (_weeklyEarnings.isEmpty)
                    _emptyCard('Nenhum dado disponível.')
                  else
                    ..._weeklyEarnings.map(
                      (r) => _WeeklyCard(
                        data: r,
                        conversionsEur:
                            _weeklyConversions[r['driver_id'] as String?] ??
                                0.0,
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _emptyCard(String msg) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Text(msg, style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.data, required this.conversionsEur});

  final Map<String, dynamic> data;
  final double conversionsEur;

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ??
        data['driver_name'] as String? ??
        data['driver_id'] as String? ??
        '—';
    final deliveries = data['deliveries_count'] ?? data['deliveries'] ?? 0;
    final earnings =
        ((data['weekly_earnings'] ?? data['earnings'] ?? 0) as num).toDouble();
    final balance =
        ((data['balance'] ?? data['current_balance'] ?? 0) as num).toDouble();
    final iban = data['iban'] as String? ?? '—';

    final tokensConverted = (conversionsEur / BRTokens.TOKEN_VALUE_EUR).round();
    final totalToPay = earnings + conversionsEur;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniStat(label: 'Entregas', value: '$deliveries'),
                const SizedBox(width: 14),
                _MiniStat(
                    label: 'Ganhos semana',
                    value: '€${earnings.toStringAsFixed(2)}'),
                const SizedBox(width: 14),
                _MiniStat(
                  label: 'Conversões tokens',
                  value:
                      '€${conversionsEur.toStringAsFixed(2)}\n($tokensConverted tokens)',
                  valueColor: Colors.orange.shade800,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total a pagar',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '€${totalToPay.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.account_balance,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'IBAN: $iban',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Text(
                  'Saldo DB: €${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}
