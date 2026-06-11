import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/reservation_model.dart';
import '../stores/reservation_store.dart';
import '../widgets/bora/bora.dart';
import '../widgets/bora_support_fab.dart';
import 'client/reservation/reservation_details_screen.dart';

/// T2.E (BR §18) + Reservas PRO F3.A — Lista de reservas do cliente.
/// 3 tabs: Próximas / Passadas / Canceladas.
/// Preserva _cancel() (RPC client_cancel_reservation, lógica refund <2h).
class ClientReservationsScreen extends StatefulWidget {
  const ClientReservationsScreen({super.key});

  @override
  State<ClientReservationsScreen> createState() =>
      _ClientReservationsScreenState();
}

class _ClientReservationsScreenState extends State<ClientReservationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<ReservationStore>();
      store.fetchMyReservations();
      // BUG OS-1 (2026-05-17) — antes só era ligado em MyReservationListsScreen,
      // por isso este ecrã (a lista principal) não recebia updates Realtime.
      // Idempotente — safe para chamar mesmo se já subscrito.
      store.subscribeMyReservations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      context.read<ReservationStore>().fetchMyReservations();

  /// Cancela reserva via RPC client_cancel_reservation.
  /// Mantém lógica refund <2h (BR §18). Não usa F2 RPCs (cancel é F3.B scope).
  Future<void> _cancel(ReservationModel r) async {
    final reservedFor = r.reservedFor;
    final hoursUntil =
        reservedFor.difference(DateTime.now()).inMinutes / 60.0;
    final willRefund = hoursUntil >= 2.0;
    final prepaymentEur = (r.prepaymentCents / 100).toStringAsFixed(2);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text(
          willRefund
              ? 'Faltam ${hoursUntil.toStringAsFixed(1)}h. Reembolso de €$prepaymentEur em 5–10 dias.'
              : 'Faltam apenas ${hoursUntil.toStringAsFixed(1)}h (<2h). Pré-pagamento de €$prepaymentEur NÃO é devolvido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: willRefund ? null : Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willRefund
                ? 'Cancelar com reembolso'
                : 'Cancelar (perco €$prepaymentEur)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'client_cancel_reservation',
        params: {
          'p_reservation_id': r.id,
          'p_reason': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva cancelada.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cancelar: $e')),
      );
    }
  }

  /// Cliente carrega "estou aqui" (RPC F2 client_arrived).
  Future<void> _markArrived(ReservationModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().markArrived(r.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Chegada confirmada. O parceiro foi avisado.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openDetails(ReservationModel r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReservationDetailsScreen(
          reservation: r,
          onCancelRequested: () => _cancel(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        title: const Text('As minhas reservas'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        bottom: TabBar(
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
      body: Consumer<ReservationStore>(
        builder: (context, store, _) {
          if (store.loading && store.myReservations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (store.error != null && store.myReservations.isEmpty) {
            return _ErrorState(
              message: store.error!,
              onRetry: _refresh,
            );
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _ReservationList(
                reservations: store.upcomingReservations,
                onRefresh: _refresh,
                emptyIcon: Icons.calendar_today,
                emptyText:
                    'Ainda não tens reservas\nExplora restaurantes e reserva a tua mesa!',
                buildCard: (r) => ReservationCard(
                  reservation: r,
                  onDetails: () => _openDetails(r),
                  onArrive: r.isApproved && r.arrivedAt == null
                      ? () => _markArrived(r)
                      : null,
                  onCancel: () => _cancel(r),
                ),
              ),
              _ReservationList(
                reservations: store.pastReservations,
                onRefresh: _refresh,
                emptyIcon: Icons.history,
                emptyText: 'Sem reservas anteriores',
                buildCard: (r) => ReservationCard(
                  reservation: r,
                  onDetails: () => _openDetails(r),
                ),
              ),
              _ReservationList(
                reservations: store.cancelledReservations,
                onRefresh: _refresh,
                emptyIcon: Icons.cancel_outlined,
                emptyText: 'Nenhuma reserva cancelada',
                buildCard: (r) => ReservationCard(
                  reservation: r,
                  onDetails: () => _openDetails(r),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReservationList extends StatelessWidget {
  const _ReservationList({
    required this.reservations,
    required this.onRefresh,
    required this.emptyText,
    required this.emptyIcon,
    required this.buildCard,
  });

  final List<ReservationModel> reservations;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final IconData emptyIcon;
  final Widget Function(ReservationModel) buildCard;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: reservations.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          emptyIcon,
                          size: 56,
                          color: AppColors.textSubtle,
                        ),
                        const SizedBox(height: 16),
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: reservations.length,
              itemBuilder: (_, i) => buildCard(reservations[i]),
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
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
