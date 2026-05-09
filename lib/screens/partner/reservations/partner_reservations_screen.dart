import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../models/client_restaurant_profile.dart';
import '../../../models/reservation_model.dart';
import '../../../models/restaurant_table.dart';
import '../../../stores/partner_reservas_store.dart';

/// Reservas PRO F4 — lista partner com 3 tabs.
///
/// Layout inspirado em OpenTable Restaurant Center "Pending requests"
/// e SevenRooms reservation tray.
/// 3 tabs: Pendentes / Hoje / Histórico.
/// Pré-fetch ClientProfiles ONCE (anti N+1 VIP badges).
class PartnerReservationsScreen extends StatefulWidget {
  const PartnerReservationsScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  final String restaurantId;
  final String restaurantName;

  @override
  State<PartnerReservationsScreen> createState() =>
      _PartnerReservationsScreenState();
}

class _PartnerReservationsScreenState extends State<PartnerReservationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<ReservationModel>> _pendingFuture;
  late Future<List<ReservationModel>> _todayFuture;
  late Future<List<ReservationModel>> _historyFuture;
  Map<String, ClientRestaurantProfile> _profilesByClientId = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    final store = context.read<PartnerReservasStore>();
    setState(() {
      _pendingFuture = store.fetchRestaurantReservations(
        restaurantId: widget.restaurantId,
        filter: 'pending',
      );
      _todayFuture = store.fetchRestaurantReservations(
        restaurantId: widget.restaurantId,
        filter: 'today',
      );
      _historyFuture = store.fetchRestaurantReservations(
        restaurantId: widget.restaurantId,
        filter: 'history',
      );
    });
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await context
          .read<PartnerReservasStore>()
          .fetchClientProfiles(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _profilesByClientId = {for (final p in profiles) p.clientUserId: p};
      });
    } catch (_) {
      // VIP badges são opcionais — não bloquear UI.
    }
  }

  Future<void> _onAccept(ReservationModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<PartnerReservasStore>()
          .decideReservation(reservationId: r.id, accept: true);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Reserva aceite. Cliente foi avisado.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _onReject(ReservationModel r) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar reserva'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'O pré-pagamento de €3 será reembolsado ao cliente.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PartnerReservasStore>().decideReservation(
            reservationId: r.id,
            accept: false,
            reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Reserva rejeitada e reembolsada.')),
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _onMarkArrival(ReservationModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res =
          await context.read<PartnerReservasStore>().markArrival(r.id);
      final creditCents = (res['credit_cents'] as int?) ?? 0;
      final payoutCents = (res['payout_cents'] as int?) ?? 0;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.primary),
              SizedBox(width: 8),
              Text('Chegada marcada'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '€${(creditCents / 100).toStringAsFixed(2)} creditados ao cliente.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'A Bora deve-te €${(payoutCents / 100).toStringAsFixed(2)} '
                '(settlement semanal).',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _onSeat(ReservationModel r) async {
    // Modal escolher mesa.
    try {
      final tables = await context
          .read<PartnerReservasStore>()
          .fetchTables(restaurantId: widget.restaurantId);
      if (!mounted) return;
      final eligible =
          tables.where((t) => t.capacity >= r.people).toList();
      final selected = await showModalBottomSheet<RestaurantTable?>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _TablePickerSheet(tables: eligible, party: r.people),
      );
      if (selected == null || !mounted) return;
      await context.read<PartnerReservasStore>().markSeated(
            reservationId: r.id,
            tableId: selected.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sentado na mesa ${selected.numero}.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _onFinish(ReservationModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res =
          await context.read<PartnerReservasStore>().markFinished(r.id);
      final turnTime = (res['turn_time_minutes'] as int?) ?? 0;
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            turnTime > 0
                ? 'Mesa libertada (turn time $turnTime min).'
                : 'Mesa libertada.',
          ),
          backgroundColor: AppTheme.primary,
        ),
      );
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservas'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pendentes'),
            Tab(text: 'Hoje'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(_pendingFuture, 'Sem reservas pendentes.'),
          _buildList(_todayFuture, 'Sem reservas hoje.'),
          _buildList(_historyFuture, 'Sem reservas passadas.'),
        ],
      ),
    );
  }

  Widget _buildList(Future<List<ReservationModel>> future, String empty) {
    return FutureBuilder<List<ReservationModel>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    snap.error.toString().replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async => _refreshAll(),
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _refreshAll(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Text(
                    empty,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (_, i) => _ReservationCard(
              reservation: list[i],
              profile: _profilesByClientId[list[i].clientUserId],
              onAccept: () => _onAccept(list[i]),
              onReject: () => _onReject(list[i]),
              onMarkArrival: () => _onMarkArrival(list[i]),
              onSeat: () => _onSeat(list[i]),
              onFinish: () => _onFinish(list[i]),
            ),
          ),
        );
      },
    );
  }
}

class _ReservationCard extends StatefulWidget {
  const _ReservationCard({
    required this.reservation,
    required this.profile,
    required this.onAccept,
    required this.onReject,
    required this.onMarkArrival,
    required this.onSeat,
    required this.onFinish,
  });

  final ReservationModel reservation;
  final ClientRestaurantProfile? profile;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function() onMarkArrival;
  final Future<void> Function() onSeat;
  final Future<void> Function() onFinish;

  @override
  State<_ReservationCard> createState() => _ReservationCardState();
}

class _ReservationCardState extends State<_ReservationCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final clientName = r.clientName.isNotEmpty
        ? r.clientName
        : (widget.profile?.clientName ?? 'Cliente');
    final clientPhone = r.clientPhone.isNotEmpty
        ? r.clientPhone
        : (widget.profile?.clientPhone ?? '');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              clientName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.profile?.isVip == true)
                            const _Badge(
                              label: 'VIP',
                              color: Color(0xFFD4AF37),
                            ),
                          if (widget.profile?.isBlocked == true)
                            const _Badge(
                              label: 'Bloqueado',
                              color: Colors.red,
                            ),
                        ],
                      ),
                      if (clientPhone.isNotEmpty)
                        Text(
                          clientPhone,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTimePt(r.reservedFor.toLocal()),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        r.people == 1 ? '1 pessoa' : '${r.people} pessoas',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(reservation: r),
              ],
            ),
            if (r.notes != null && r.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.notes!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _buildActions(r),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ReservationModel r) {
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (r.isPending) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _run(widget.onAccept),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Aceitar'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _run(widget.onReject),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Rejeitar'),
            ),
          ),
        ],
      );
    }
    if (r.isApproved && r.arrivedAt == null && r.seatedAt == null) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _run(widget.onMarkArrival),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.location_on, size: 18),
              label: const Text('Marcar chegada'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _run(widget.onSeat),
              icon: const Icon(Icons.event_seat, size: 18),
              label: const Text('Sentar'),
            ),
          ),
        ],
      );
    }
    if (r.seatedAt != null && r.finishedAt == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _run(widget.onFinish),
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Terminar'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  static String _formatDateTimePt(DateTime dt) {
    const wd = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    const mo = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final w = wd[(dt.weekday - 1).clamp(0, 6)];
    final m = mo[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$w, ${dt.day} $m • $hh:$mm';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.reservation});
  final ReservationModel reservation;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    String label;
    Color color;
    if (r.isFinished) {
      label = 'Concluída';
      color = AppTheme.primary;
    } else if (r.seatedAt != null) {
      label = 'Sentada';
      color = AppTheme.primary;
    } else if (r.arrivedAt != null) {
      label = 'Chegou';
      color = AppTheme.primary;
    } else if (r.isCancelled) {
      label = 'Cancelada';
      color = Colors.grey;
    } else if (r.isNoShow) {
      label = 'Não apareceu';
      color = Colors.red;
    } else if (r.isApproved) {
      label = 'Confirmada';
      color = AppTheme.primary;
    } else if (r.isPending) {
      label = 'Pendente';
      color = AppTheme.secondary;
    } else {
      label = r.status;
      color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
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
}

class _TablePickerSheet extends StatelessWidget {
  const _TablePickerSheet({required this.tables, required this.party});
  final List<RestaurantTable> tables;
  final int party;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Escolher mesa para $party ${party == 1 ? "pessoa" : "pessoas"}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: tables.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sem mesas com capacidade suficiente.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: tables.length,
                    itemBuilder: (_, i) {
                      final t = tables[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.1),
                          child: Text(
                            t.numero,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text('Mesa ${t.numero}'),
                        subtitle: Text(
                          '${t.capacity} lugares • ${_zonaLabel(t.zona)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(ctx, t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _zonaLabel(String zona) {
    switch (zona) {
      case 'esplanada':
        return 'Esplanada';
      case 'balcao':
        return 'Balcão';
      case 'privado':
        return 'Privado';
      default:
        return 'Interior';
    }
  }
}
