import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../utils/hora_lisboa.dart';
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
  String _recipientType = 'client'; // 'client' | 'driver' | 'partner'
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

  /// Quantas pessoas/aparelhos vão receber (admin_broadcast_preview). Null se
  /// a pré-visualização falhar — nesse caso a confirmação diz que não se sabe.
  Future<Map<String, dynamic>?> _preview(String segment) async {
    try {
      final r = await Supabase.instance.client.rpc('admin_broadcast_preview',
          params: {'p_segment': segment, 'p_kind': _kind});
      return (r is Map) ? Map<String, dynamic>.from(r) : null;
    } catch (e) {
      debugPrint('[AdminSendNotification] preview falhou: $e');
      return null;
    }
  }

  /// Confirmação obrigatória antes de qualquer envio em massa (achado 06-admin:
  /// "Enviar a todos os clientes" saía com um toque, sem dizer a quantos).
  Future<bool> _confirmarEnvio(String segment, String segmentoLabel) async {
    final p = await _preview(segment);
    if (!mounted) return false;
    final pessoas = p?['pessoas'];
    final aparelhos = p?['aparelhos'];
    final soOptIn = p?['so_opt_in'] == true;
    final quando = _mode == 'schedule' && _scheduledAt != null
        ? 'Sai em ${dataHoraLisboa(_scheduledAt!.toUtc().toIso8601String())} (hora de Lisboa).'
        : 'Sai agora.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar envio em massa'),
        content: Text(
          pessoas == null
              ? 'Não consegui contar quantas pessoas vão receber.\n'
                  'Segmento: $segmentoLabel\n$quando\n\nEnviar mesmo assim?'
              : 'Você vai enviar "${_titleCtrl.text.trim()}" para '
                  '$pessoas pessoa(s) ($aparelhos aparelho(s) com push).\n'
                  'Segmento: $segmentoLabel'
                  '${soOptIn ? ' — só quem aceitou promoções' : ''}\n$quando\n\n'
                  'Isto não se desfaz depois de sair.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(pessoas == null ? 'Enviar' : 'Enviar a $pessoas')),
        ],
      ),
    );
    return ok == true;
  }

  /// Acorda a fila logo (a tarefa agendada também a apanha em <= 2 min).
  void _acordarFila() {
    Supabase.instance.client.functions
        .invoke('execute-broadcast', body: {'origem': 'painel'})
        .then((_) {}, onError: (Object e) {
      debugPrint('[AdminSendNotification] execute-broadcast: $e');
    });
  }

  static const _segLabels = {
    'all_clients': 'Todos os clientes',
    'recent_clients_30d': 'Clientes ativos (30 dias)',
    'drivers_online': 'Entregadores online',
    'partners': 'Parceiros',
    'all': 'Todos',
    'clients': 'Clientes',
    'drivers': 'Entregadores',
  };

  Future<void> _send() async {
    if (_sending) return;
    if (!_formKey.currentState!.validate()) return;
    if (_mode != 'one_user') {
      final seg = _mode == 'broadcast' ? _segment : _scheduleSegment;
      setState(() => _sending = true);
      final confirmado = await _confirmarEnvio(seg, _segLabels[seg] ?? seg);
      if (!mounted) return;
      if (!confirmado) {
        setState(() => _sending = false);
        return;
      }
    } else {
      setState(() => _sending = true);
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_mode == 'broadcast') {
        // admin_broadcast_notification (04/10) já grava o sininho E põe o push
        // na fila só para as pessoas do segmento — não chamar mais nada (o
        // antigo RPC de gravar o sininho à parte duplicava-o).
        final res = await Supabase.instance.client
            .rpc('admin_broadcast_notification', params: {
          'p_segment': _segment,
          'p_kind': _kind,
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        });
        _acordarFila();
        messenger.showSnackBar(SnackBar(
            content: Text('Enviado: $res pessoa(s) no sininho; o push sai já.')));
      } else if (_mode == 'schedule') {
        final res = await Supabase.instance.client
            .rpc('admin_create_broadcast', params: {
          'p_segment': _scheduleSegment,
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim().isEmpty
              ? _titleCtrl.text.trim()
              : _bodyCtrl.text.trim(),
          'p_scheduled_at': _scheduledAt?.toUtc().toIso8601String(),
        });
        final ok = (res is Map) && res['broadcast_id'] != null;
        if (_scheduledAt == null) _acordarFila();
        messenger.showSnackBar(SnackBar(
          content: Text(!ok
              ? 'Não consegui agendar. Tente de novo.'
              : _scheduledAt == null
                  ? 'Notificação na fila — sai em até 2 minutos.'
                  : 'Agendada para ${dataHoraLisboa(_scheduledAt!.toUtc().toIso8601String())} (hora de Lisboa).'),
        ));
      } else {
        await Supabase.instance.client.rpc('admin_send_push_notification', params: {
          'p_recipient_type': _recipientType,
          'p_recipient_id': _userIdCtrl.text.trim(),
          'p_title': _titleCtrl.text.trim(),
          'p_body': _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        });
        messenger.showSnackBar(
            const SnackBar(content: Text('Push notification enviada.')));
      }
      _titleCtrl.clear();
      _bodyCtrl.clear();
    } catch (e) {
      debugPrint('[AdminSendNotification] erro: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui enviar. Tente de novo.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Enviar notificação',
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
                  helperText: 'Sai agora: sininho + push (pede confirmação com o número de pessoas)',
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
                  DropdownMenuItem(
                      value: 'all_users',
                      child: Text('Clientes + parceiros')),
                ],
                onChanged: (v) => setState(() => _segment = v!),
              ),
            if (_mode == 'schedule') ...[
              DropdownButtonFormField<String>(
                value: _scheduleSegment,
                decoration: const InputDecoration(
                  labelText: 'Segmento',
                  helperText: 'A fila envia na hora marcada (verifica a cada 2 min)',
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
                      : 'Agendado: ${dataHoraLisboa(_scheduledAt!.toUtc().toIso8601String())} (Lisboa)',
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
            if (_mode == 'one_user') ...[
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
                value: _recipientType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de destinatário',
                  helperText: 'Tipo de utilizador para envio FCM',
                ),
                items: const [
                  DropdownMenuItem(value: 'client', child: Text('Cliente')),
                  DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  DropdownMenuItem(value: 'partner', child: Text('Parceiro')),
                ],
                onChanged: (v) => setState(() => _recipientType = v!),
              ),
            ],
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
            BoraPrimaryButton(
              label: 'Enviar',
              icon: Icons.send,
              loading: _sending,
              onPressed: _sending ? null : _send,
            ),
          ]),
        ),
      ),
    );
  }
}
