import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/cleaning_models.dart';
import '../../stores/cleaner_store.dart';
import '../../widgets/bora/bora.dart';

/// LIMPEZA — ganhos da profissional (RPC cleaner_earnings_summary).
/// 85% + produtos; em dinheiro, os 15% da Bora ficam por entregar no
/// acerto semanal (cash_bora_due_cents).
class CleanerEarningsScreen extends StatefulWidget {
  const CleanerEarningsScreen({super.key});

  @override
  State<CleanerEarningsScreen> createState() => _CleanerEarningsScreenState();
}

class _CleanerEarningsScreenState extends State<CleanerEarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CleanerStore>().loadEarnings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleanerStore>();
    final e = store.earnings;
    int cents(String key) => (e[key] as num?)?.toInt() ?? 0;
    int count(String key) => (e[key] as num?)?.toInt() ?? 0;
    final rating = (e['rating_avg'] as num?)?.toDouble() ?? 0;
    final ratingsCount = (e['ratings_count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Os meus ganhos'),
      body: RefreshIndicator(
        onRefresh: () => context.read<CleanerStore>().loadEarnings(),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            _BigCard(
              title: 'Esta semana',
              value: CleaningLabels.euro(cents('week_cents')),
              subtitle: '${count('week_count')} limpezas concluídas',
              highlighted: true,
            ),
            const SizedBox(height: Spacing.md),
            _BigCard(
              title: 'Total ganho',
              value: CleaningLabels.euro(cents('total_cents')),
              subtitle: '${count('total_count')} limpezas desde o início',
            ),
            const SizedBox(height: Spacing.md),
            if (cents('cash_bora_due_cents') > 0) ...[
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: AppColors.warning),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A entregar à Bora: '
                            '${CleaningLabels.euro(cents('cash_bora_due_cents'))}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          const Text(
                            'Comissão de 15% das limpezas pagas em dinheiro '
                            '— acerta no fecho semanal.',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (ratingsCount > 0)
              _BigCard(
                title: 'Avaliação',
                value: '★ ${rating.toStringAsFixed(1)}',
                subtitle: '$ratingsCount avaliações de clientes',
              ),
            const SizedBox(height: Spacing.lg),
            const Text(
              'Recebes 85% do valor de cada limpeza + 100% da taxa de '
              'produtos quando os levas. Pagamentos online são libertados '
              'quando o cliente confirma a limpeza.',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.highlighted = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primaryWash : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
            color: highlighted ? AppColors.primary : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: Spacing.xs),
          Text(value,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
