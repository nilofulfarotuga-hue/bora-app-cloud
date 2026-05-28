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
                      backgroundColor: AppColors.primary,
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
                                  backgroundColor: AppColors.primary,
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
                                backgroundColor: AppColors.primary,
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

  // ─── P1-S6-001 walk-in sheet (admin_seat_walk_in) ───────────────────────────

  Future<void> _showWalkInSheet() async {
    final restaurantIdCtrl = TextEditingController();
    final clientNameCtrl = TextEditingController(text: 'Walk-in admin');
    final clientPhoneCtrl = TextEditingController();
    int people = 2;
    List<Map<String, dynamic>> tables = const [];
    String? selectedTableId;
    bool loadingTables = false;
    bool submitting = false;

    final outerContext = context;
    final messenger = ScaffoldMessenger.of(outerContext);

    Future<void> loadTables(StateSetter setSt) async {
      final rid = restaurantIdCtrl.text.trim();
      if (rid.isEmpty) {
        tables = const [];
        selectedTableId = null;
        setSt(() {});
        return;
      }
      setSt(() => loadingTables = true);
      try {
        final rows = await Supabase.instance.client
            .from('restaurant_tables')
            .select('id, numero, capacity, zona, active')
            .eq('restaurant_id', rid)
            .eq('active', true)
            .order('numero', ascending: true);
        tables = (rows as List).cast<Map<String, dynamic>>();
        selectedTableId = null;
      } catch (e) {
        tables = const [];
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Erro a carregar mesas: $e'),
        ));
      } finally {
        setSt(() => loadingTables = false);
      }
    }

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
                  'Sentar walk-in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Regista um cliente que chega sem reserva. Cria reserva '
                  'imediata com status approved e atribui a mesa escolhida.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: restaurantIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Restaurant ID',
                    helperText: 'Copia de admin_partners_screen',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Carregar mesas',
                      onPressed:
                          submitting ? null : () => loadTables(setSt),
                    ),
                  ),
                  onSubmitted: (_) => loadTables(setSt),
                ),
                const SizedBox(height: 12),
                if (loadingTables)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child:
                        Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (tables.isEmpty)
                  const Text(
                    'Sem mesas activas (carrega para listar).',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: selectedTableId,
                    decoration: const InputDecoration(labelText: 'Mesa'),
                    items: tables
                        .map((t) => DropdownMenuItem<String>(
                              value: t['id'] as String,
                              child: Text(
                                'Mesa ${t['numero']} · cap ${t['capacity']} · '
                                '${t['zona']}',
                              ),
                            ))
                        .toList(),
                    onChanged: submitting
                        ? null
                        : (v) => setSt(() => selectedTableId = v),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Pessoas:'),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: people > 1 && !submitting
                          ? () => setSt(() => people--)
                          : null,
                    ),
                    Text('$people',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: people < 50 && !submitting
                          ? () => setSt(() => people++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clientNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome cliente',
                    helperText: 'Default: "Walk-in admin"',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clientPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefone (opcional)',
                    helperText: 'Para envio de eventual SMS',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.event_seat),
                      label: Text(submitting ? 'A sentar...' : 'Sentar'),
                      onPressed: (submitting ||
                              selectedTableId == null ||
                              restaurantIdCtrl.text.trim().isEmpty)
                          ? null
                          : () async {
                              setSt(() => submitting = true);
                              try {
                                final phone =
                                    clientPhoneCtrl.text.trim().isEmpty
                                        ? null
                                        : clientPhoneCtrl.text.trim();
                                final name = clientNameCtrl.text.trim().isEmpty
                                    ? 'Walk-in admin'
                                    : clientNameCtrl.text.trim();
                                await Supabase.instance.client.rpc(
                                  'admin_seat_walk_in',
                                  params: {
                                    'p_restaurant_id':
                                        restaurantIdCtrl.text.trim(),
                                    'p_party': people,
                                    'p_table_id': selectedTableId,
                                    'p_client_name': name,
                                    'p_client_phone': phone,
                                  },
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                messenger.showSnackBar(const SnackBar(
                                  backgroundColor: AppColors.primary,
                                  content: Text('Walk-in sentado.'),
                                ));
                                setState(() => _future = _load());
                              } catch (e) {
                                if (!ctx.mounted) return;
                                setSt(() => submitting = false);
                                messenger.showSnackBar(SnackBar(
                                  backgroundColor: Colors.red,
                                  content: Text('Erro: $e'),
                                ));
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    restaurantIdCtrl.dispose();
    clientNameCtrl.dispose();
    clientPhoneCtrl.dispose();
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
            // P1-S6-001 (2026-05-17) — Sentar walk-in (admin_seat_walk_in).
            icon: const Icon(Icons.event_seat, color: Colors.amberAccent),
            tooltip: 'Sentar walk-in',
            onPressed: _showWalkInSheet,
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
    } catch (e, st) {
      debugPrint('[admin_reservations._MetricsHeader] load failed: $e\n$st');
    }
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
