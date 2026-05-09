// BottomSheets admin usam StatefulBuilder com `ctx` interno após awaits — o
// linter não consegue inferir o lifetime. mounted checks no State outer já
// protegem o caso real. Suprimir info-level globalmente neste ficheiro.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/reservation_model.dart';

/// Admin view: all table reservations across restaurants (BR §16.2).
class AdminReservationsScreen extends StatefulWidget {
  const AdminReservationsScreen({super.key});

  @override
  State<AdminReservationsScreen> createState() =>
      _AdminReservationsScreenState();
}

class _AdminReservationsScreenState extends State<AdminReservationsScreen> {
  late Future<List<ReservationModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReservationModel>> _load() async {
    final rows = await Supabase.instance.client
        .from('reservations')
        .select()
        .order('reserved_for', ascending: false)
        .limit(200);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ReservationModel.fromSupabase)
        .toList();
  }

  // ─── F4 admin override actions (B4-light) ─────────────────────────────────

  Future<void> _showForceCreateSheet() async {
    final restaurantIdCtrl = TextEditingController();
    final clientUserIdCtrl = TextEditingController();
    final clientNameCtrl = TextEditingController();
    final clientPhoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    int people = 2;
    DateTime? reservedFor;
    String status = 'approved';
    bool skipPrepayment = true;
    bool submitting = false;

    final outerContext = context;

    await showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Forçar criar reserva',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: restaurantIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Restaurante ID *',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clientNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome cliente *',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clientPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone *',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clientUserIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client User ID (opcional UUID)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Pessoas: '),
                    IconButton(
                      onPressed:
                          people > 1 ? () => setSt(() => people--) : null,
                      icon: const Icon(Icons.remove_circle),
                    ),
                    Text('$people'),
                    IconButton(
                      onPressed:
                          people < 50 ? () => setSt(() => people++) : null,
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    reservedFor == null
                        ? 'Escolher data e hora'
                        : '${reservedFor!.day.toString().padLeft(2, '0')}/'
                            '${reservedFor!.month.toString().padLeft(2, '0')}/'
                            '${reservedFor!.year} '
                            '${reservedFor!.hour.toString().padLeft(2, '0')}:'
                            '${reservedFor!.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d == null) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 19, minute: 0),
                    );
                    if (t == null) return;
                    setSt(() => reservedFor =
                        DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
                DropdownButton<String>(
                  value: status,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'approved', child: Text('Aprovada')),
                    DropdownMenuItem(
                        value: 'pending', child: Text('Pendente')),
                  ],
                  onChanged: (v) => setSt(() => status = v ?? 'approved'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pular pré-pagamento'),
                  value: skipPrepayment,
                  onChanged: (v) => setSt(() => skipPrepayment = v),
                ),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: submitting
                        ? null
                        : () async {
                            if (restaurantIdCtrl.text.isEmpty ||
                                clientNameCtrl.text.isEmpty ||
                                clientPhoneCtrl.text.isEmpty ||
                                reservedFor == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Preencha campos obrigatórios.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            setSt(() => submitting = true);
                            try {
                              await Supabase.instance.client.rpc(
                                'admin_force_create_reservation',
                                params: {
                                  'p_restaurant_id': restaurantIdCtrl.text,
                                  if (clientUserIdCtrl.text.isNotEmpty)
                                    'p_client_user_id':
                                        clientUserIdCtrl.text,
                                  'p_client_name': clientNameCtrl.text,
                                  'p_client_phone': clientPhoneCtrl.text,
                                  'p_people': people,
                                  'p_reserved_for':
                                      reservedFor!.toIso8601String(),
                                  'p_status': status,
                                  if (notesCtrl.text.isNotEmpty)
                                    'p_notes': notesCtrl.text,
                                  'p_skip_prepayment': skipPrepayment,
                                },
                              );
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(outerContext).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Reserva criada com sucesso.'),
                                  backgroundColor: Color(0xFF1B5E20),
                                ),
                              );
                              setState(() => _future = _load());
                            } catch (e) {
                              if (!mounted) return;
                              setSt(() => submitting = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Erro: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Criar reserva (override)'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCancelOnBehalfSheet() async {
    final reservationIdCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    final outerContext = context;

    await showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancelar reserva em nome do cliente',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reservationIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reservation ID (UUID) *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          if (reservationIdCtrl.text.isEmpty ||
                              reasonCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Preencha os campos obrigatórios.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setSt(() => submitting = true);
                          try {
                            await Supabase.instance.client.rpc(
                              'admin_cancel_reservation_on_behalf_of',
                              params: {
                                'p_reservation_id': reservationIdCtrl.text,
                                'p_reason': reasonCtrl.text,
                              },
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(outerContext).showSnackBar(
                              const SnackBar(
                                content: Text('Reserva cancelada em nome.'),
                                backgroundColor: Color(0xFF1B5E20),
                              ),
                            );
                            setState(() => _future = _load());
                          } catch (e) {
                            if (!mounted) return;
                            setSt(() => submitting = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Erro: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Cancelar reserva'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text(
          'Reservas (admin)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
            tooltip: 'Forçar criar reserva',
            onPressed: _showForceCreateSheet,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
            tooltip: 'Cancelar em nome',
            onPressed: _showCancelOnBehalfSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // T2.G: métricas 30d (no-show%, cancel%, receita Bora, créditos)
          const _MetricsHeader(),
          Expanded(
            child: FutureBuilder<List<ReservationModel>>(
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
                  return const Center(child: Text('Sem reservas.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _future = _load()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      final d = r.reservedFor.toLocal();
                      return ListTile(
                        title: Text(
                          '${r.clientName} · ${r.people} pessoas · ${r.restaurantId}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · '
                          '${r.status}',
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsHeader extends StatefulWidget {
  const _MetricsHeader();
  @override
  State<_MetricsHeader> createState() => _MetricsHeaderState();
}

class _MetricsHeaderState extends State<_MetricsHeader> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_reservations_metrics', params: {'p_days': 30});
      if (mounted) setState(() => _data = (res as Map).cast<String, dynamic>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox(height: 4);
    final noShow = (d['no_show'] as num?)?.toInt() ?? 0;
    final cancelNoRefund = (d['cancelled_no_refund'] as num?)?.toInt() ?? 0;
    // Cada no-show e cada cancel<2h vale 300c. Cada arrived vale 100c (Bora retém €1).
    final arrived = (d['arrived'] as num?)?.toInt() ?? 0;
    final boraServiceCents = arrived * 100;
    final boraNoShowCents = noShow * 300;
    final boraLateCancelCents = cancelNoRefund * 300;
    final partnerPendingCents =
        ((d['credits_given_cents'] as num?) ?? 0).toInt();

    return Container(
      width: double.infinity,
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _stat('Total 30d', '${d['total']}'),
              _stat('Chegou', '$arrived'),
              _stat('No-show', '${d['no_show_rate_pct']}%', highlight: true),
              _stat('Cancel', '${d['cancellation_rate_pct']}%'),
            ],
          ),
          const Divider(),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _stat('Pendente payout parceiros',
                  '€${(partnerPendingCents / 100).toStringAsFixed(2)}',
                  highlight: true),
              _stat('Receita Bora taxa €1×chegou',
                  '€${(boraServiceCents / 100).toStringAsFixed(2)}',
                  highlight: true),
              _stat('Receita Bora no-show',
                  '€${(boraNoShowCents / 100).toStringAsFixed(2)}'),
              _stat('Receita Bora late-cancel',
                  '€${(boraLateCancelCents / 100).toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String v, {bool highlight = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(v,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.deepPurple : Colors.black87)),
        ],
      );
}
