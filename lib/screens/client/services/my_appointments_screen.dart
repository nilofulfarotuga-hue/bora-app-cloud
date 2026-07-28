import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/appointment_model.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'booking_flow_screen.dart';

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

  /// `appointment_reschedule_max_count` — para dizer ao cliente quantos
  /// reagendamentos lhe restam. Fallback 2 até a leitura chegar.
  int _rescheduleMaxCount = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = context.read<ServicesStore>();
      store.fetchMyAppointments();
      store.subscribeMyAppointments();
      final max = await store.fetchRescheduleMaxCount();
      if (mounted) setState(() => _rescheduleMaxCount = max);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      context.read<ServicesStore>().fetchMyAppointments();

  /// Detalhe da marcação em bottom sheet (padrão Fresha/Booksy — tap no card).
  void _showDetail(AppointmentModel a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      builder: (_) => _AppointmentDetailSheet(
        appointment: a,
        rescheduleMaxCount: _rescheduleMaxCount,
        onCancel: (a.isUpcoming && !a.isRescheduleOnly)
            ? () {
                Navigator.pop(context);
                _cancel(a);
              }
            : null,
        onReschedule: (a.isUpcoming && a.isRescheduleOnly)
            ? () {
                Navigator.pop(context);
                _reschedule(a);
              }
            : null,
      ),
    );
  }

  /// BLOCO E (2026-07-28) — abre o MESMO fluxo de marcação em modo
  /// reagendamento (serviço e profissional já fixos). Não cria marcação nova
  /// nem toca no Stripe: no fim é só `client_reschedule_appointment`.
  Future<void> _reschedule(AppointmentModel a) async {
    final store = context.read<ServicesStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final provider = await store.fetchProviderDetail(a.providerId);
      if (!mounted || provider == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível abrir o reagendamento.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
      await navigator.push<bool>(MaterialPageRoute(
        builder: (_) => BookingFlowScreen(provider: provider, rescheduleOf: a),
      ));
      if (mounted) await _refresh();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// Cancela marcação via RPC. Aviso especial se faltarem <24h.
  Future<void> _cancel(AppointmentModel a) async {
    final hoursUntil =
        a.scheduledAt.difference(DateTime.now()).inMinutes / 60.0;
    final lessThan24h = hoursUntil < 24.0;
    final depositEur = (a.depositCents / 100).toStringAsFixed(2);
    // BLOCO B: em modo `full` o cobrado é o valor total, não um sinal.
    final noun = a.isFullPaymentMode ? 'o valor pago' : 'o sinal';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar marcação?'),
        // Sessão 2026-06-11 — regra exata visível ANTES de confirmar
        // (business_rules: >24h refund total; <24h sinal retido).
        content: Text(
          lessThan24h
              ? 'Faltam ${hoursUntil.toStringAsFixed(1)}h para a marcação '
                  '(menos de 24 horas).\n\nRegra: $noun de €$depositEur '
                  'NÃO é reembolsado.'
              : 'Faltam ${hoursUntil.toStringAsFixed(1)}h para a marcação '
                  '(mais de 24 horas).\n\nRegra: reembolso TOTAL de $noun '
                  'de €$depositEur (5–10 dias úteis no cartão).',
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
    } on RescheduleOnlyException catch (e) {
      // BLOCO E: caminho antigo (ou política mudada entretanto). Em vez de um
      // erro seco, encaminha para o reagendamento.
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.accent,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Reagendar',
            textColor: Colors.white,
            onPressed: () => _reschedule(a),
          ),
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
                        rescheduleMaxCount: _rescheduleMaxCount,
                        onTap: () => _showDetail(a),
                        // BLOCO E: em `reschedule_only` o cliente não cancela
                        // uma marcação paga — reagenda.
                        onCancel:
                            a.isRescheduleOnly ? null : () => _cancel(a),
                        onReschedule:
                            a.isRescheduleOnly ? () => _reschedule(a) : null,
                      ),
                    ),
                    _AppointmentList(
                      appointments: store.pastAppointments,
                      onRefresh: _refresh,
                      emptyIcon: Icons.history,
                      emptyText: 'Sem marcações anteriores',
                      buildCard: (a) => _AppointmentCard(
                        appointment: a,
                        onTap: () => _showDetail(a),
                      ),
                    ),
                    _AppointmentList(
                      appointments: store.cancelledAppointments,
                      onRefresh: _refresh,
                      emptyIcon: Icons.cancel_outlined,
                      emptyText: 'Nenhuma marcação cancelada',
                      buildCard: (a) => _AppointmentCard(
                        appointment: a,
                        onTap: () => _showDetail(a),
                      ),
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
  const _AppointmentCard({
    required this.appointment,
    this.onTap,
    this.onCancel,
    this.onReschedule,
    this.rescheduleMaxCount = 2,
  });

  final AppointmentModel appointment;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;
  final int rescheduleMaxCount;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final providerName =
        (a.providerName != null && a.providerName!.isNotEmpty)
            ? a.providerName!
            : 'Barbearia';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
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
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      '€${(a.servicePriceCents / 100).toStringAsFixed(2)}'
                      ' • ${_depositLabel(a)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (a.wasRescheduled && a.originalScheduledAt != null) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        'Reagendada · era '
                        '${_formatDateTimePt(a.originalScheduledAt!.toLocal())}',
                        style: const TextStyle(
                          fontSize: 11.5,
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
          // BLOCO E — texto de apoio da política "só reagendamento".
          if (onReschedule != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _rescheduleHint(a, rescheduleMaxCount),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (onCancel != null || onReschedule != null) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: onReschedule != null
                  ? TextButton.icon(
                      onPressed: onReschedule,
                      icon: const Icon(Icons.event_repeat, size: 18),
                      label: const Text('Reagendar'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary),
                    )
                  : TextButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancelar'),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.error),
                    ),
            ),
          ],
          ],
        ),
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

/// BLOCO E (2026-07-28) — texto de apoio da política "só reagendamento".
/// Quando resta 1 (ou 0) reagendamento, avisa explicitamente.
String _rescheduleHint(AppointmentModel a, int maxCount) {
  final left = (maxCount - a.rescheduleCount).clamp(0, maxCount);
  const base = 'Não podes vir? Reagenda para outro dia — o valor que pagaste '
      'fica reservado para a tua marcação.';
  if (left == 0) return 'Já não podes reagendar esta marcação.';
  if (left == 1) return '$base\nPodes reagendar mais 1 vez.';
  return base;
}

/// Estado do sinal em PT-PT (valores reais da coluna deposit_status).
/// BLOCO B (2026-07-28): em `booking_payment_mode = 'full'` o que foi cobrado
/// NÃO é um sinal — é o valor total do serviço. Chamar-lhe "sinal" mentia ao
/// cliente ("restante na barbearia" quando já não há restante nenhum).
String _depositLabel(AppointmentModel a) {
  final eur = (a.depositCents / 100).toStringAsFixed(2);
  final noun = a.isFullPaymentMode ? 'Total €$eur' : 'Sinal €$eur';
  switch (a.depositStatus) {
    case 'paid':
      return '$noun pago';
    case 'pending':
      return '$noun pendente';
    case 'refunded':
      return '$noun reembolsado';
    case 'retained':
      return '$noun retido';
    case 'waived':
      return a.isFullPaymentMode ? 'Sem pagamento' : 'Sem sinal';
    default:
      return noun;
  }
}

/// Sessão 2026-06-11 — detalhe da marcação ao tocar no card (padrão
/// Fresha/Booksy). Cancelar disponível só em marcações futuras.
class _AppointmentDetailSheet extends StatelessWidget {
  const _AppointmentDetailSheet({
    required this.appointment,
    this.onCancel,
    this.onReschedule,
    this.rescheduleMaxCount = 2,
  });

  final AppointmentModel appointment;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;
  final int rescheduleMaxCount;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final providerName =
        (a.providerName != null && a.providerName!.isNotEmpty)
            ? a.providerName!
            : 'Barbearia';
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.md,
        bottom: Spacing.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              _ProviderThumb(photoUrl: a.providerPhotoUrl),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  providerName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusBadge(appointment: a),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          const Divider(),
          _DetailRow(
            icon: Icons.content_cut,
            label: 'Serviço',
            value: a.serviceName ?? '—',
          ),
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Profissional',
            value: a.staffName ?? 'Qualquer profissional',
          ),
          _DetailRow(
            icon: Icons.schedule,
            label: 'Data e hora',
            value:
                _AppointmentCard._formatDateTimePt(a.scheduledAt.toLocal()),
          ),
          _DetailRow(
            icon: Icons.timer_outlined,
            label: 'Duração',
            value: '${a.durationMinutes} min',
          ),
          _DetailRow(
            icon: Icons.payments_outlined,
            label: 'Preço total',
            value: '€${(a.servicePriceCents / 100).toStringAsFixed(2)}',
          ),
          _DetailRow(
            icon: Icons.savings_outlined,
            label: a.isFullPaymentMode ? 'Pago pela app' : 'Sinal',
            value: _depositLabel(a),
          ),
          if (a.wasRescheduled && a.originalScheduledAt != null)
            _DetailRow(
              icon: Icons.event_repeat,
              label: 'Reagendada',
              value: 'Horário original: '
                  '${_AppointmentCard._formatDateTimePt(a.originalScheduledAt!.toLocal())}',
            ),
          if (a.clientNotes != null && a.clientNotes!.isNotEmpty)
            _DetailRow(
              icon: Icons.notes_outlined,
              label: 'Notas',
              value: a.clientNotes!,
            ),
          if (a.isCancelled &&
              a.cancelReason != null &&
              a.cancelReason!.isNotEmpty)
            _DetailRow(
              icon: Icons.cancel_outlined,
              label: 'Cancelamento',
              value: a.cancelReason!,
            ),
          if (onReschedule != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              _rescheduleHint(a, rescheduleMaxCount),
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReschedule,
                icon: const Icon(Icons.event_repeat, size: 18),
                label: const Text('Reagendar marcação'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: Spacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar marcação'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSubtle),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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
