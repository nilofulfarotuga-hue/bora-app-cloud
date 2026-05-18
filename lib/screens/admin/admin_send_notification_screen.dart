import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_broadcasts_history_screen.dart';

/// T2.3 — Admin: envia notification manual (1 user) ou broadcast segment.
/// P1-S11-002 (2026-05-17) — modo "Agendar" usa admin_create_broadcast
/// (persistido em push_broadcasts) em vez do fire-forget
/// admin_broadcast_notification, para auditoria e queue de envios.
class AdminSendNotificationScreen extends StatefulWidget {
  const AdminSendNotificationScreen({super.key});
  @override
  State<AdminSendNotificationScreen> createState() =>
      _AdminSendNotificationScreenState();
}

class _AdminSendNotificationScreenState
    extends State<AdminSendNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  String _mode = 'broadcast'; // 'broadcast' | 'one_user' | 'schedule'
  String _segment = 'all_clients';
  // P1-S11-002 — Segmentos suportados por admin_create_broadcast.
  String _scheduleSegment = 'all';
  String _kind = 'admin';
  final _userIdCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime? _scheduledAt;
  bool _sending = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickScheduledAt() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (t == null || !mounted) return;
    setState(() {
      _scheduledAt =
          DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_mode == 'broadcast') {
        final res = await Supabase.instance.client
            .rpc('admin_broadcast_notification', params: {
          'p_segment': _segment,
          'p_kind': _kind,
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        });
        messenger.showSnackBar(
            SnackBar(content: Text('Broadcast enviado: $res destinatários')));
      } else if (_mode == 'schedule') {
        // P1-S11-002 — persistir em push_broadcasts via admin_create_broadcast.
        final res = await Supabase.instance.client
            .rpc('admin_create_broadcast', params: {
          'p_segment': _scheduleSegment,
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim(),
          'p_scheduled_at':
              _scheduledAt?.toUtc().toIso8601String(),
        });
        final id = (res is Map) ? res['broadcast_id']?.toString() : null;
        messenger.showSnackBar(SnackBar(
          content: Text(
            _scheduledAt == null
                ? 'Broadcast criado (envio assim que Edge Fn corra). id=$id'
                : 'Broadcast agendado para ${_scheduledAt!.toLocal()}. id=$id',
          ),
        ));
      } else {
        await Supabase.instance.client.rpc('admin_send_notification', params: {
          'p_user_id': _userIdCtrl.text.trim(),
          'p_kind': _kind,
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        });
        messenger.showSnackBar(
            const SnackBar(content: Text('Notification enviada.')));
      }
      _titleCtrl.clear();
      _bodyCtrl.clear();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enviar notificação'),
        actions: [
          IconButton(
            tooltip: 'Histórico de broadcasts',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminBroadcastsHistoryScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'broadcast', label: Text('Imediato')),
                ButtonSegment(value: 'schedule', label: Text('Agendar')),
                ButtonSegment(value: 'one_user', label: Text('1 user')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            if (_mode == 'broadcast')
              DropdownButtonFormField<String>(
                value: _segment,
                decoration: const InputDecoration(
                  labelText: 'Segmento',
                  helperText: 'Envio imediato via FCM (admin_broadcast_notification)',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'all_clients', child: Text('Todos os clientes')),
                  DropdownMenuItem(
                      value: 'recent_clients_30d',
                      child: Text('Clientes activos (30d)')),
                  DropdownMenuItem(
                      value: 'drivers_online', child: Text('Drivers online')),
                  DropdownMenuItem(
                      value: 'partners', child: Text('Parceiros')),
                ],
                onChanged: (v) => setState(() => _segment = v!),
              ),
            if (_mode == 'schedule') ...[
              DropdownButtonFormField<String>(
                value: _scheduleSegment,
                decoration: const InputDecoration(
                  labelText: 'Segmento',
                  helperText: 'Persistido em push_broadcasts (Edge Fn consome quando pronta)',
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(
                      value: 'clients', child: Text('Clientes')),
                  DropdownMenuItem(
                      value: 'drivers', child: Text('Drivers')),
                  DropdownMenuItem(
                      value: 'partners', child: Text('Parceiros')),
                ],
                onChanged: (v) => setState(() => _scheduleSegment = v!),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  _scheduledAt == null
                      ? 'Enviar assim que pronto'
                      : 'Agendado: ${_scheduledAt!.toLocal()}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_scheduledAt != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Limpar agendamento',
                        onPressed: () => setState(() => _scheduledAt = null),
                      ),
                    TextButton(
                      onPressed: _pickScheduledAt,
                      child: Text(
                          _scheduledAt == null ? 'Agendar...' : 'Alterar'),
                    ),
                  ],
                ),
              ),
            ],
            if (_mode == 'one_user')
              TextFormField(
                controller: _userIdCtrl,
                decoration: const InputDecoration(
                    labelText: 'User ID (UUID)',
                    helperText: 'Copia do admin_clients_screen'),
                validator: (v) => (v == null || v.trim().length < 30)
                    ? 'UUID inválido'
                    : null,
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'promo', child: Text('Promo')),
                DropdownMenuItem(value: 'cashback', child: Text('Cashback')),
                DropdownMenuItem(value: 'cancellation', child: Text('Cancelamento')),
                DropdownMenuItem(value: 'referral', child: Text('Referral')),
                DropdownMenuItem(value: 'refund', child: Text('Refund')),
              ],
              onChanged: (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Título *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(
                  labelText: 'Mensagem (opcional)',
                  alignLabelWithHint: true),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('Enviar'),
            ),
          ]),
        ),
      ),
    );
  }
}
