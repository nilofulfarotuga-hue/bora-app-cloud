import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Histórico de corridas do passageiro.
class TvdeRidesHistoryScreen extends StatefulWidget {
  const TvdeRidesHistoryScreen({super.key});

  @override
  State<TvdeRidesHistoryScreen> createState() => _TvdeRidesHistoryScreenState();
}

class _TvdeRidesHistoryScreenState extends State<TvdeRidesHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvdeStore>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rides = context.watch<TvdeStore>().history;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'As minhas corridas'),
      body: rides.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: rides.length,
              separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
              itemBuilder: (_, i) => _RideTile(ride: rides[i]),
            ),
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});
  final TvdeRide ride;

  @override
  Widget build(BuildContext context) {
    final d = ride.createdAt;
    final date = d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryWash,
            child: Icon(
              ride.isFinished
                  ? Icons.check
                  : (ride.isCancelled ? Icons.close : Icons.directions_car),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text('$date · ${ride.statusLabel}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSubtle)),
              ],
            ),
          ),
          Text('€${(ride.displayFareCents / 100).toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 56, color: AppColors.textSubtle),
          const SizedBox(height: Spacing.md),
          Text('Ainda não tens corridas.',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
