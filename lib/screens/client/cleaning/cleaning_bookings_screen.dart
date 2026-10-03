import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../stores/cleaning_store.dart';
import '../../../widgets/bora/bora.dart';
import 'cleaning_tracking_screen.dart';
import 'cleaning_wizard_screen.dart';

import '../../../l10n/tr.dart';

/// LIMPEZA — entrada da categoria (tile da home): as minhas limpezas
/// (ativas + histórico) + CTA para agendar uma nova.
class CleaningBookingsScreen extends StatefulWidget {
  const CleaningBookingsScreen({super.key});

  @override
  State<CleaningBookingsScreen> createState() => _CleaningBookingsScreenState();
}

class _CleaningBookingsScreenState extends State<CleaningBookingsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<CleaningStore>().loadMyBookings();
      if (mounted) setState(() => _loading = false);
    });
  }

  void _openWizard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CleaningWizardScreen()),
    ).then((_) {
      if (mounted) context.read<CleaningStore>().loadMyBookings();
    });
  }

  void _openTracking(CleaningBooking b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CleaningTrackingScreen(booking: b)),
    ).then((_) {
      if (mounted) context.read<CleaningStore>().loadMyBookings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleaningStore>();
    final active = store.activeBookings;
    final past = store.pastBookings;

    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Limpeza da casa'.tr),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : store.bookings.isEmpty
              ? _EmptyState(onSchedule: _openWizard)
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    if (active.isNotEmpty) ...[
                      _SectionLabel('Ativas'.tr),
                      for (final b in active)
                        _BookingCard(booking: b, onTap: () => _openTracking(b)),
                      const SizedBox(height: Spacing.md),
                    ],
                    if (past.isNotEmpty) ...[
                      _SectionLabel('Histórico'.tr),
                      for (final b in past)
                        _BookingCard(booking: b, onTap: () => _openTracking(b)),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
      floatingActionButton: store.bookings.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openWizard,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text('Agendar limpeza'.tr),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSchedule});
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.primaryWash,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cleaning_services,
                  size: 48, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'A tua casa a brilhar'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Profissionais de limpeza verificadas, preço fechado à cabeça e pagamento só depois de confirmares o serviço.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: 'Agendar limpeza'.tr,
            icon: Icons.event_available,
            onPressed: onSchedule,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary)),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onTap});
  final CleaningBooking booking;
  final VoidCallback onTap;

  Color get _statusColor {
    if (booking.status.isCancelled) return AppColors.error;
    if (booking.status == CleaningStatus.completed) {
      return AppColors.textSecondary;
    }
    if (booking.status == CleaningStatus.done) return AppColors.warning;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${two(b.scheduledAt.day)}/${two(b.scheduledAt.month)} às '
        '${two(b.scheduledAt.hour)}:${two(b.scheduledAt.minute)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Container(
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
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Icon(Icons.cleaning_services,
                    color: AppColors.primary),
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
                      '$when · ${CleaningLabels.euro(b.totalCents)}'
                      '${b.isRecurring ? ' · ${b.recurrenceLabel}' : ''}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Text(
                  b.status.labelPt,
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
