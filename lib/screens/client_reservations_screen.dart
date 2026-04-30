import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// T2.E (BR §18) — Lista de reservas do cliente + cancel button.
class ClientReservationsScreen extends StatefulWidget {
  const ClientReservationsScreen({super.key});
  @override
  State<ClientReservationsScreen> createState() =>
      _ClientReservationsScreenState();
}

class _ClientReservationsScreenState extends State<ClientReservationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('reservations')
          .select()
          .eq('client_user_id',
              Supabase.instance.client.auth.currentUser?.id ?? '')
          .order('reserved_for', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _items = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final reservedFor = DateTime.parse(r['reserved_for'] as String);
    final hoursUntil =
        reservedFor.difference(DateTime.now()).inMinutes / 60.0;
    final willRefund = hoursUntil >= 2.0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text(
          willRefund
              ? 'Faltam ${hoursUntil.toStringAsFixed(1)}h. Reembolso de €${((r['prepayment_cents'] as num) / 100).toStringAsFixed(2)} em 5–10 dias.'
              : 'Faltam apenas ${hoursUntil.toStringAsFixed(1)}h (<2h). Pré-pagamento de €${((r['prepayment_cents'] as num) / 100).toStringAsFixed(2)} NÃO é devolvido.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: willRefund ? null : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text(willRefund ? 'Cancelar com reembolso' : 'Cancelar (perco €3)'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc('client_cancel_reservation',
          params: {
            'p_reservation_id': r['id'],
            'p_reason': null,
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reserva cancelada.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
      case 'arrived':
        return Colors.green;
      case 'pending':
      case 'pending_payment':
        return Colors.orange;
      case 'no_show':
      case 'cancelled_no_refund':
      case 'rejected_refunded':
        return Colors.red;
      case 'cancelled_refunded':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String s) => {
        'pending_payment': 'Aguardando pagamento',
        'pending': 'Aguardando restaurante',
        'approved': 'Aprovada',
        'arrived': 'Chegou (crédito atribuído)',
        'rejected_refunded': 'Rejeitada (reembolsada)',
        'cancelled_refunded': 'Cancelada (reembolsada)',
        'cancelled_no_refund': 'Cancelada (sem reembolso)',
        'no_show': 'Falta',
      }[s] ??
      s;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('As minhas reservas')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('Sem reservas.')),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final r = _items[i];
                      final status = r['status'] as String? ?? '';
                      final reservedFor =
                          DateTime.tryParse(r['reserved_for'] as String? ?? '');
                      final canCancel = const ['pending', 'approved']
                          .contains(status);
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.event_seat,
                            color: _statusColor(status),
                          ),
                          title: Text(
                              '${r['people']} pax · ${reservedFor != null ? "${reservedFor.day}/${reservedFor.month} ${reservedFor.hour.toString().padLeft(2, '0')}:${reservedFor.minute.toString().padLeft(2, '0')}" : '—'}'),
                          subtitle: Text(
                              '${_statusLabel(status)}\n€${((r['prepayment_cents'] as num? ?? 0) / 100).toStringAsFixed(2)}'),
                          isThreeLine: true,
                          trailing: canCancel
                              ? IconButton(
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.red),
                                  onPressed: () => _cancel(r),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
