import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/appointment_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Agenda do parceiro (vertical Serviços). Vista Hoje (default) + Semana.
///
/// Cores de estado: Confirmada=verde, Concluída=cinza, Cancelada=riscado,
/// Bloqueado=laranja. Ações por card via RPCs do store.
class PartnerAgendaScreen extends StatefulWidget {
  const PartnerAgendaScreen({super.key});

  @override
  State<PartnerAgendaScreen> createState() => _PartnerAgendaScreenState();
}

class _PartnerAgendaScreenState extends State<PartnerAgendaScreen> {
  bool _weekView = false;
  late Future<List<AppointmentModel>> _future;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppointmentModel>> _load() {
    final store = context.read<PartnerAppointmentsStore>();
    if (_weekView) {
      final now = DateTime.now();
      return store.fetchAgenda(
        from: now,
        to: now.add(const Duration(days: 6)),
      );
    }
    return store.fetchAgenda(day: DateTime.now());
  }

  void _refresh() => setState(() => _future = _load());

  void _setView(bool week) {
    if (_weekView == week) return;
    setState(() {
      _weekView = week;
      _future = _load();
    });
  }

  Future<void> _runAction(
    AppointmentModel a,
    Future<void> Function() action,
    String okMessage,
  ) async {
    if (_busy.contains(a.id)) return;
    setState(() => _busy.add(a.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(okMessage),
        backgroundColor: AppColors.success,
      ));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  void _complete(AppointmentModel a, String method) {
    final store = context.read<PartnerAppointmentsStore>();
    _runAction(
      a,
      () => store.completeAppointment(a.id, method),
      'Marcação concluída.',
    );
  }

  void _noShow(AppointmentModel a) {
    final store = context.read<PartnerAppointmentsStore>();
    _runAction(a, () => store.markNoShow(a.id), 'Falta registada.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Agenda',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Hoje')),
                ButtonSegment(value: true, label: Text('Semana')),
              ],
              selected: {_weekView},
              onSelectionChanged: (s) => _setView(s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AppointmentModel>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _error(snap.error.toString());
                }
                final items = snap.data ?? const <AppointmentModel>[];
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            _EmptyAgenda(),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              Spacing.lg, 0, Spacing.lg, Spacing.lg),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _AppointmentCard(
                            appointment: items[i],
                            busy: _busy.contains(items[i].id),
                            onCompleteOnSite: () =>
                                _complete(items[i], 'on_site'),
                            onCompleteApp: () => _complete(items[i], 'app'),
                            onNoShow: () => _noShow(items[i]),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(String e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(e.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.busy,
    required this.onCompleteOnSite,
    required this.onCompleteApp,
    required this.onNoShow,
  });

  final AppointmentModel appointment;
  final bool busy;
  final VoidCallback onCompleteOnSite;
  final VoidCallback onCompleteApp;
  final VoidCallback onNoShow;

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _timeLabel {
    final dt = appointment.scheduledAt.toLocal();
    return '${_two(dt.hour)}:${_two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final isBlocked = a.status == AppointmentStatus.blocked;
    final isCancelled = a.status == AppointmentStatus.cancelled;
    final isCompleted = a.status == AppointmentStatus.completed;
    final isNoShow = a.status == AppointmentStatus.noShow;
    final isConfirmed = a.status == AppointmentStatus.confirmed;

    // Cor do estado.
    final Color statusColor;
    final String statusLabel;
    if (isBlocked) {
      statusColor = AppColors.accent;
      statusLabel = 'Bloqueado';
    } else if (isCancelled) {
      statusColor = AppColors.error;
      statusLabel = 'Cancelada';
    } else if (isCompleted) {
      statusColor = AppColors.textSubtle;
      statusLabel = 'Concluída';
    } else if (isNoShow) {
      statusColor = AppColors.error;
      statusLabel = 'Faltou';
    } else if (isConfirmed) {
      statusColor = AppColors.success;
      statusLabel = 'Confirmada';
    } else {
      statusColor = AppColors.warning;
      statusLabel = 'Por pagar';
    }

    final clientName = isBlocked
        ? (a.cancelReason ?? 'Bloqueio')
        : (a.clientName?.trim().isNotEmpty == true
            ? a.clientName!.trim()
            : 'Cliente');
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: isCancelled ? AppColors.textSecondary : AppColors.textPrimary,
      decoration: isCancelled ? TextDecoration.lineThrough : null,
    );

    // Só marcações activas/confirmadas mostram ações.
    final showActions = isConfirmed && !busy;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
        border: Border(left: BorderSide(color: statusColor, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _timeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(clientName, style: titleStyle),
                ),
                _StatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            if (!isBlocked) ...[
              const SizedBox(height: Spacing.sm),
              _MetaRow(
                icon: Icons.content_cut,
                text: a.serviceName ?? 'Serviço',
              ),
              if (a.staffName != null)
                _MetaRow(icon: Icons.person_outline, text: a.staffName!),
              _MetaRow(
                icon: Icons.euro,
                text: a.servicePriceLabel,
              ),
            ],
            if (showActions) ...[
              const Divider(height: Spacing.xl, color: AppColors.divider),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  ElevatedButton.icon(
                    onPressed: onCompleteOnSite,
                    icon: const Icon(Icons.store_mall_directory, size: 18),
                    label: const Text('Concluído (loja)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCompleteApp,
                    icon: const Icon(Icons.smartphone, size: 18),
                    label: const Text('Concluído (app)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onNoShow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    icon: const Icon(Icons.person_off, size: 18),
                    label: const Text('Faltou'),
                  ),
                ],
              ),
            ],
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.md),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Sem marcações',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Não há marcações para este período.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
