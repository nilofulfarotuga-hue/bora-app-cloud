import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/reservation_model.dart';

/// Partner dashboard — reservations section (BR §14.7).
class PartnerReservationsScreen extends StatefulWidget {
  const PartnerReservationsScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<PartnerReservationsScreen> createState() =>
      _PartnerReservationsScreenState();
}

class _PartnerReservationsScreenState
    extends State<PartnerReservationsScreen> {
  late Future<List<ReservationModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReservationModel>> _load() async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('reservations')
        .select()
        .eq('restaurant_id', widget.restaurantId)
        .order('reserved_for', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ReservationModel.fromSupabase)
        .toList();
  }

  /// T2.F (BR §18): use server RPCs that enforce ownership + payment status
  /// + create menu credit + auto-refund on rejection.
  Future<void> _decide(ReservationModel r, bool accept,
      {String? reason}) async {
    final client = Supabase.instance.client;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.rpc('partner_decide_reservation', params: {
        'p_reservation_id': r.id,
        'p_accept': accept,
        'p_reason': reason,
      });
      messenger.showSnackBar(SnackBar(
        content: Text(accept
            ? 'Reserva aprovada.'
            : 'Reserva rejeitada — reembolso automático.'),
      ));
      setState(() => _future = _load());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _markArrived(ReservationModel r) async {
    final client = Supabase.instance.client;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.rpc('partner_mark_arrival',
          params: {'p_reservation_id': r.id});
      messenger.showSnackBar(const SnackBar(
        content: Text('Cliente marcado como chegou. Crédito €3 atribuído.'),
      ));
      setState(() => _future = _load());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Reservas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: FutureBuilder<List<ReservationModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          final list = snap.data ?? const <ReservationModel>[];
          if (list.isEmpty) {
            return const Center(child: Text('Sem reservas pendentes.'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ReservationCard(
                reservation: list[i],
                onAccept: () => _decide(list[i], true),
                onReject: () => _decide(list[i], false),
                onArrived: () => _markArrived(list[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onAccept,
    required this.onReject,
    required this.onArrived,
  });

  final ReservationModel reservation;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onArrived;

  String get _statusLabel {
    switch (reservation.status) {
      case ReservationStatus.pending:
        return 'Pendente';
      case ReservationStatus.accepted:
        return 'Aceite';
      case ReservationStatus.suggestedOtherTime:
        return 'Sugerida outra hora';
      case ReservationStatus.rejected:
        return 'Recusada';
      case ReservationStatus.customerArrived:
        return 'Cliente chegou';
      case ReservationStatus.cancelled:
        return 'Cancelada';
    }
  }

  Color get _statusColor {
    switch (reservation.status) {
      case ReservationStatus.pending:
        return Colors.orange;
      case ReservationStatus.accepted:
      case ReservationStatus.customerArrived:
        return Colors.green;
      case ReservationStatus.suggestedOtherTime:
        return Colors.blue;
      case ReservationStatus.rejected:
      case ReservationStatus.cancelled:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = reservation.reservedFor.toLocal();
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${reservation.clientName} · ${reservation.people} pessoas',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Quando: $dateStr'),
            Text('Telefone: ${reservation.clientPhone}'),
            if (reservation.notes != null && reservation.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Notas: ${reservation.notes}'),
              ),
            const SizedBox(height: 10),
            if (reservation.status == ReservationStatus.pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAccept,
                      child: const Text('Aceitar'),
                    ),
                  ),
                ],
              )
            else if (reservation.status == ReservationStatus.accepted) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Quando o cliente chegar:\n'
                  '· Desconta €2 da conta dele\n'
                  '· Bora paga-te €2 no próximo settlement semanal',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onArrived,
                  icon: const Icon(Icons.chair_alt_outlined),
                  label: const Text('Marcar sentado (€2 crédito)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
