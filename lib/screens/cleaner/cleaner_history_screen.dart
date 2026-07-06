import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/cleaning_models.dart';
import '../../stores/cleaner_store.dart';
import '../../widgets/bora/bora.dart';

/// LIMPEZA — histórico de serviços da profissional (concluídos + cancelados),
/// com detalhe. Paridade com o histórico de corridas do estafeta TVDE.
class CleanerHistoryScreen extends StatefulWidget {
  const CleanerHistoryScreen({super.key});

  @override
  State<CleanerHistoryScreen> createState() => _CleanerHistoryScreenState();
}

class _CleanerHistoryScreenState extends State<CleanerHistoryScreen> {
  late Future<List<CleaningBooking>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CleanerStore>().loadHistory();
  }

  Future<void> _refresh() async {
    setState(() => _future = context.read<CleanerStore>().loadHistory());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Histórico de serviços'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CleaningBooking>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('Ainda sem serviços concluídos.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: rows.length,
              itemBuilder: (_, i) => _HistoryCard(booking: rows[i]),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.booking});
  final CleaningBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final cancelled = b.status.isCancelled;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${two(b.scheduledAt.day)}/${two(b.scheduledAt.month)}/'
        '${b.scheduledAt.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cancelled
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.primaryWash,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(
              cancelled ? Icons.cancel : Icons.check_circle,
              color: cancelled ? AppColors.error : AppColors.primary,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b.typeLabel} · ${b.sizeLabel}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '$when · ${b.addressCity} · ${b.status.labelPt}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            cancelled
                ? (b.cancelFeeCents > 0
                    ? CleaningLabels.euro(
                        (b.cancelFeeCents * 85 / 100).round())
                    : '—')
                : CleaningLabels.euro(b.cleanerEarningsCents),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cancelled ? AppColors.textSubtle : AppColors.primary),
          ),
        ],
      ),
    );
  }
}
