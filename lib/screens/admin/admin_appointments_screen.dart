// BottomSheets admin usam StatefulBuilder com `ctx` interno após awaits — o
// linter não consegue inferir o lifetime. mounted checks no State outer já
// protegem o caso real. Suprimir info-level globalmente neste ficheiro.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/appointment_model.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Admin — Agenda global de marcações (vertical Serviços / Barbearias).
///
/// Lista `appointments` (limit 200, scheduled_at desc) com JOIN ao prestador
/// e serviço. Filtros por estado / data / barbearia aplicados em memória
/// (espelha `admin_reservations_screen.dart`). Cancelar em nome do cliente
/// via RPC `admin_cancel_appointment_on_behalf_of`. PT-BR.
class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  State<AdminAppointmentsScreen> createState() =>
      _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> {
  late Future<List<AppointmentModel>> _future;

  // Filtros em memória.
  String? _statusFilter; // null = todos
  String? _providerFilter; // null = todas
  DateTime? _dayFilter; // null = qualquer dia
  // Sessão 2026-06-11 — visão "por cliente" (nome/telefone contém).
  String _clientQuery = '';
  final _clientQueryController = TextEditingController();

  static const _statusOptions = <(String?, String)>[
    (null, 'Todos'),
    (AppointmentStatus.confirmed, 'Confirmadas'),
    (AppointmentStatus.completed, 'Concluídas'),
    (AppointmentStatus.noShow, 'No-show'),
    (AppointmentStatus.cancelled, 'Canceladas'),
    (AppointmentStatus.pendingPayment, 'Pend. pagamento'),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _clientQueryController.dispose();
    super.dispose();
  }

  Future<List<AppointmentModel>> _load() async {
    final rows = await Supabase.instance.client
        .from('appointments')
        .select(
            '*, service_providers(name, photo_url, hero_image_url, '
            'booking_payment_mode, booking_cancellation_policy), '
            'provider_services(name), staff_members(name)')
        .order('scheduled_at', ascending: false)
        .limit(200);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(AppointmentModel.fromSupabase)
        .toList();
  }

  List<AppointmentModel> _applyFilters(List<AppointmentModel> all) {
    final q = _clientQuery.trim().toLowerCase();
    return all.where((a) {
      if (_statusFilter != null && a.status != _statusFilter) return false;
      if (_providerFilter != null && a.providerId != _providerFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final name = (a.clientName ?? '').toLowerCase();
        final phone = (a.clientPhone ?? '').toLowerCase();
        if (!name.contains(q) && !phone.contains(q)) return false;
      }
      if (_dayFilter != null) {
        final d = a.scheduledAt.toLocal();
        if (d.year != _dayFilter!.year ||
            d.month != _dayFilter!.month ||
            d.day != _dayFilter!.day) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Lista de prestadores presentes nos dados carregados (para o dropdown).
  List<MapEntry<String, String>> _providersFrom(List<AppointmentModel> all) {
    final map = <String, String>{};
    for (final a in all) {
      map[a.providerId] = a.providerName ?? a.providerId;
    }
    final list = map.entries.toList()
      ..sort((x, y) => x.value.toLowerCase().compareTo(y.value.toLowerCase()));
    return list;
  }

  // ─── Cancelar em nome do cliente ─────────────────────────────────────────

  Future<void> _showCancelSheet() async {
    final apptIdCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool refund = true;
    bool submitting = false;

    final outerContext = context;

    await showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancelar marcação em nome do cliente',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: Spacing.lg),
              TextField(
                controller: apptIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Appointment ID (UUID) *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  isDense: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reembolsar o valor pago ao cliente'),
                value: refund,
                onChanged: (v) => setSt(() => refund = v),
              ),
              const SizedBox(height: Spacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          if (apptIdCtrl.text.trim().isEmpty ||
                              reasonCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Preencha os campos obrigatórios.'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }
                          setSt(() => submitting = true);
                          try {
                            await Supabase.instance.client.rpc(
                              'admin_cancel_appointment_on_behalf_of',
                              params: {
                                'p_appointment_id': apptIdCtrl.text.trim(),
                                'p_reason': reasonCtrl.text.trim(),
                                'p_refund': refund,
                              },
                            );
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(outerContext).showSnackBar(
                              const SnackBar(
                                content: Text('Marcação cancelada em nome.'),
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
                                backgroundColor: AppColors.error,
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
                      : const Text('Cancelar marcação'),
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
          ),
        ),
      ),
    );

    apptIdCtrl.dispose();
    reasonCtrl.dispose();
  }

  /// Cancelar directamente a partir de um cartão (pré-preenche o ID).
  Future<void> _cancelOne(AppointmentModel a) async {
    final reasonCtrl = TextEditingController();
    bool refund = true;
    final outerContext = context;
    await showDialog<void>(
      context: outerContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Cancelar — ${a.clientName ?? 'cliente'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reembolsar o valor pago'),
                value: refund,
                onChanged: (v) => setSt(() => refund = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Voltar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) return;
                try {
                  await Supabase.instance.client.rpc(
                    'admin_cancel_appointment_on_behalf_of',
                    params: {
                      'p_appointment_id': a.id,
                      'p_reason': reasonCtrl.text.trim(),
                      'p_refund': refund,
                    },
                  );
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(content: Text('Marcação cancelada.')),
                  );
                  setState(() => _future = _load());
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              },
              child: const Text('Cancelar marcação'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  static String _dmyHm(DateTime utc) {
    final d = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// BLOCO E (2026-07-28) — auditoria de reagendamentos (`appointment_reschedules`).
  /// RLS: o admin lê tudo. Read-only — o admin continua acima da política e
  /// pode cancelar em nome do cliente pelo botão ao lado.
  Future<void> _showRescheduleHistory(AppointmentModel a) async {
    final outerContext = context;
    List<Map<String, dynamic>> rows = const [];
    String? error;
    try {
      final res = await Supabase.instance.client
          .from('appointment_reschedules')
          .select()
          .eq('appointment_id', a.id)
          .order('created_at', ascending: true);
      rows = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: outerContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Histórico de reagendamentos'),
        content: SizedBox(
          width: 420,
          child: error != null
              ? Text('Erro: $error')
              : rows.isEmpty
                  ? const Text('Sem registos.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Spacing.sm),
                            child: Text(
                              '${_dmyHm(DateTime.parse(r['old_scheduled_at'] as String))}'
                              '  →  '
                              '${_dmyHm(DateTime.parse(r['new_scheduled_at'] as String))}'
                              '\npor ${r['changed_by'] ?? '—'}'
                              '${r['old_staff_id'] != r['new_staff_id'] ? ' · trocou de profissional' : ''}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
        AppointmentStatus.confirmed => AppColors.success,
        AppointmentStatus.completed => AppColors.info,
        AppointmentStatus.noShow => AppColors.error,
        AppointmentStatus.cancelled => AppColors.textSecondary,
        AppointmentStatus.pendingPayment => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  String _statusLabel(String s) => switch (s) {
        AppointmentStatus.confirmed => 'Confirmada',
        AppointmentStatus.completed => 'Concluída',
        AppointmentStatus.noShow => 'No-show',
        AppointmentStatus.cancelled => 'Cancelada',
        AppointmentStatus.pendingPayment => 'Pend. pagamento',
        AppointmentStatus.blocked => 'Bloqueada',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Agenda (admin)',
        actions: [
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
            tooltip: 'Cancelar em nome (por ID)',
            onPressed: _showCancelSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<List<AppointmentModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xxl),
                child: Text('Erro: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          final all = snap.data ?? const <AppointmentModel>[];
          final providers = _providersFrom(all);
          final filtered = _applyFilters(all);
          return Column(
            children: [
              _buildFilters(providers),
              const Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(Spacing.xxl),
                          child: Text('Sem marcações neste filtro.',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            setState(() => _future = _load()),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(Spacing.md),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(
                              height: Spacing.sm),
                          itemBuilder: (context, i) => _buildCard(filtered[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters(List<MapEntry<String, String>> providers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sessão 2026-06-11 — busca por cliente (espelho admin da visão
          // "Minhas marcações" do cliente).
          TextField(
            decoration: InputDecoration(
              labelText: 'Buscar cliente (nome ou telefone)',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: Spacing.sm),
              suffixIcon: _clientQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _clientQueryController.clear();
                        setState(() => _clientQuery = '');
                      },
                    ),
            ),
            controller: _clientQueryController,
            onChanged: (v) => setState(() => _clientQuery = v),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _statusFilter,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm, vertical: Spacing.sm),
                  ),
                  items: _statusOptions
                      .map((s) => DropdownMenuItem<String?>(
                            value: s.$1,
                            child: Text(s.$2,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _statusFilter = v),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _providerFilter,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Barbearia',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm, vertical: Spacing.sm),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child:
                            Text('Todas', style: TextStyle(fontSize: 13))),
                    ...providers.map((p) => DropdownMenuItem<String?>(
                          value: p.key,
                          child: Text(p.value,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        )),
                  ],
                  onChanged: (v) => setState(() => _providerFilter = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dayFilter == null
                        ? 'Qualquer dia'
                        : '${_dayFilter!.day.toString().padLeft(2, '0')}/${_dayFilter!.month.toString().padLeft(2, '0')}/${_dayFilter!.year}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dayFilter ?? DateTime.now(),
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _dayFilter = d);
                  },
                ),
              ),
              if (_dayFilter != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Limpar data',
                  onPressed: () => setState(() => _dayFilter = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard(AppointmentModel a) {
    final d = a.scheduledAt.toLocal();
    final canCancel = a.status == AppointmentStatus.confirmed ||
        a.status == AppointmentStatus.pendingPayment;
    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.clientName ?? 'Cliente'} · ${a.providerName ?? a.providerId}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(
                    color: _statusColor(a.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    _statusLabel(a.status).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        color: _statusColor(a.status),
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} · '
              '${a.serviceName ?? 'Serviço'} · ${a.servicePriceLabel}'
              '${a.staffName != null ? ' · ${a.staffName}' : ''}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            if (a.isWalkIn)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.xs),
                child: Text('Walk-in',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textSubtle)),
              ),
            // BLOCO E (2026-07-28) — reagendamento visível no admin.
            if (a.wasRescheduled)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  'Reagendada ${a.rescheduleCount}x'
                  '${a.originalScheduledAt != null ? ' · original: ${_dmyHm(a.originalScheduledAt!)}' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.info),
                ),
              ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.sm,
              children: [
                if (a.wasRescheduled)
                  TextButton.icon(
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Histórico'),
                    onPressed: () => _showRescheduleHistory(a),
                  ),
                if (canCancel)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: () => _cancelOne(a),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
