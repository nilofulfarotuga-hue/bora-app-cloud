import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../stores/cleaning_store.dart';
import '../../../utils/hora_lisboa.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/selo_serie_limpeza.dart';
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
      final store = context.read<CleaningStore>();
      await store.loadMyBookings();
      if (mounted) setState(() => _loading = false);
      // S3 (01/11/2026): "Semanal · próxima: …" nos cartões das séries.
      store.carregarSeries();
    });
  }

  /// Volta a ler as limpezas e as séries (ao regressar de outro ecrã).
  Future<void> _recarregar() async {
    if (!mounted) return;
    final store = context.read<CleaningStore>();
    await store.loadMyBookings();
    await store.carregarSeries();
  }

  void _openWizard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CleaningWizardScreen()),
    ).then((_) => _recarregar());
  }

  /// "Marcar de novo" (04/10): mesmo serviço, morada e profissional.
  void _bookAgain(CleaningBooking b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CleaningWizardScreen(repeatOf: b)),
    ).then((_) => _recarregar());
  }

  void _openTracking(CleaningBooking b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CleaningTrackingScreen(booking: b)),
    ).then((_) => _recarregar());
  }

  /// S3: o selo do cartão. Ativas: "Semanal · próxima: 08/11 10:00" (ou
  /// "Série parada"); histórico: só "Semanal"; única: nenhum.
  ({String texto, bool parada})? _seloSerie(
      CleaningStore store, CleaningBooking b,
      {required bool ativa}) {
    final gid = b.recurrenceGroupId;
    if (!b.isRecurring) return null;
    if (!ativa || gid == null) {
      return (texto: b.recurrenceLabel.tr, parada: false);
    }
    final serie = store.serieEmCache(gid) ?? SerieEstado.desconhecido;
    if (serie.parada) return (texto: 'Série parada'.tr, parada: true);
    return (
      texto: linhaSerieLimpeza(
          b,
          b.proximaDaSerie(store.bookings, serie.proxima,
              agora: DateTime.now())),
      parada: false,
    );
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
                        _BookingCard(
                          booking: b,
                          selo: _seloSerie(store, b, ativa: true),
                          onTap: () => _openTracking(b),
                        ),
                      const SizedBox(height: Spacing.md),
                    ],
                    if (past.isNotEmpty) ...[
                      _SectionLabel('Histórico'.tr),
                      for (final b in past)
                        _BookingCard(
                          booking: b,
                          selo: _seloSerie(store, b, ativa: false),
                          onTap: () => _openTracking(b),
                          onBookAgain: () => _bookAgain(b),
                        ),
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
  const _BookingCard({
    required this.booking,
    required this.onTap,
    this.onBookAgain,
    this.selo,
  });
  final CleaningBooking booking;
  final VoidCallback onTap;
  final VoidCallback? onBookAgain;

  /// S3: "Semanal · próxima: 08/11 10:00" / "Série parada" (null = única).
  final ({String texto, bool parada})? selo;

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
    // Hora de Lisboa, nunca a do telemóvel (01/11/2026: era a única linha
    // da limpeza ainda no fuso do aparelho).
    final l = paredeLisboa(b.scheduledAt);
    final when = '${two(l.day)}/${two(l.month)} às '
        '${two(l.hour)}:${two(l.minute)}';
    final selo = this.selo;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      InkWell(
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
                      '$when · ${CleaningLabels.euro(b.totalCents)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    if (selo != null) ...[
                      const SizedBox(height: 4),
                      SeloLimpeza(
                        selo.texto,
                        key: Key('limpeza_selo_serie_${b.id}'),
                        icone:
                            selo.parada ? Icons.event_busy : Icons.repeat,
                        apagado: selo.parada,
                      ),
                    ],
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
          if (onBookAgain != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onBookAgain,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('Marcar de novo'.tr),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
