import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/appointment_model.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Vertical Serviços — "As Minhas Marcações".
/// 3 tabs: Próximas / Passadas / Canceladas. Cancelar com aviso se <24h.
/// Espelha o padrão de ClientReservationsScreen (cancel via RPC; reembolso
/// é tratado server-side, sem refund Stripe client-side).
class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<ServicesStore>();
      store.fetchMyAppointments();
      store.subscribeMyAppointments();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      context.read<ServicesStore>().fetchMyAppointments();

  /// Cancela marcação via RPC. Aviso especial se faltarem <24h.
  Future<void> _cancel(AppointmentModel a) async {
    final hoursUntil =
        a.scheduledAt.difference(DateTime.now()).inMinutes / 60.0;
    final lessThan24h = hoursUntil < 24.0;
    final depositEur = (a.depositCents / 100).toStringAsFixed(2);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar marcação?'),
        content: Text(
          lessThan24h
              ? 'Faltam apenas ${hoursUntil.toStringAsFixed(1)}h (<24h). '
                  'O sinal de €$depositEur pode não ser reembolsado.'
              : 'Faltam ${hoursUntil.toStringAsFixed(1)}h. '
                  'Reembolso do sinal de €$depositEur em 5–10 dias.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: lessThan24h ? AppColors.error : null,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lessThan24h
                ? 'Cancelar (posso perder €$depositEur)'
                : 'Cancelar com reembolso'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final willRefund =
          await context.read<ServicesStore>().cancelAppointment(a.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(willRefund
              ? 'Marcação cancelada. Reembolso a caminho.'
              : 'Marcação cancelada.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'As minhas marcações'),
      body: Column(
        children: [
          Material(
            color: AppColors.primaryDeep,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Próximas'),
                Tab(text: 'Passadas'),
                Tab(text: 'Canceladas'),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ServicesStore>(
              builder: (context, store, _) {
                if (store.loadingAppointments &&
                    store.myAppointments.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (store.appointmentsError != null &&
                    store.myAppointments.isEmpty) {
                  return _ErrorState(
                    message: store.appointmentsError!,
                    onRetry: _refresh,
                  );
                }
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _AppointmentList(
                      appointments: store.upcomingAppointments,
                      onRefresh: _refresh,
                      emptyIcon: Icons.event_available,
                      emptyText:
                          'Ainda não tens marcações\nExplora serviços e marca a tua!',
                      buildCard: (a) => _AppointmentCard(
                        appointment: a,
                        onCancel: () => _cancel(a),
                      ),
                    ),
                    _AppointmentList(
                      appointments: store.pastAppointments,
                      onRefresh: _refresh,
                      emptyIcon: Icons.history,
                      emptyText: 'Sem marcações anteriores',
                      buildCard: (a) => _AppointmentCard(appointment: a),
                    ),
                    _AppointmentList(
                      appointments: store.cancelledAppointments,
                      onRefresh: _refresh,
                      emptyIcon: Icons.cancel_outlined,
                      emptyText: 'Nenhuma marcação cancelada',
                      buildCard: (a) => _AppointmentCard(appointment: a),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.appointments,
    required this.onRefresh,
    required this.emptyText,
    required this.emptyIcon,
    required this.buildCard,
  });

  final List<AppointmentModel> appointments;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final IconData emptyIcon;
  final Widget Function(AppointmentModel) buildCard;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: appointments.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(emptyIcon, size: 56, color: AppColors.textSubtle),
                        const SizedBox(height: Spacing.lg),
                        Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              itemCount: appointments.length,
              itemBuilder: (_, i) => buildCard(appointments[i]),
            ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, this.onCancel});

  final AppointmentModel appointment;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final providerName =
        (a.providerName != null && a.providerName!.isNotEmpty)
            ? a.providerName!
            : 'Barbearia';
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProviderThumb(photoUrl: a.providerPhotoUrl),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (a.serviceName != null) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        a.serviceName!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      _formatDateTimePt(a.scheduledAt.toLocal()),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (a.staffName != null) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        'com ${a.staffName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSubtle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusBadge(appointment: a),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDateTimePt(DateTime dt) {
    const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    const months = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final wd = weekdays[(dt.weekday - 1).clamp(0, 6)];
    final mo = months[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${dt.day} $mo • $hh:$mm';
  }
}

class _ProviderThumb extends StatelessWidget {
  const _ProviderThumb({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ThumbFallback(),
                loadingBuilder: (_, child, prog) =>
                    prog == null ? child : const _ThumbFallback(),
              )
            : const _ThumbFallback(),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.content_cut, color: AppColors.primary, size: 26),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.appointment});
  final AppointmentModel appointment;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(appointment);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  static (String, Color) _resolve(AppointmentModel a) {
    if (a.isCompleted) return ('Concluída', AppColors.primary);
    if (a.isNoShow) return ('Faltou', AppColors.error);
    if (a.isCancelled) return ('Cancelada', Colors.grey);
    if (a.isConfirmed) return ('Confirmada', AppColors.success);
    if (a.isPendingPayment) return ('Aguarda pagamento', AppColors.accent);
    return (a.status, Colors.grey);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
