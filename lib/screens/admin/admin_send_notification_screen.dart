import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// T2.3 — Admin: envia notification manual (1 user) ou broadcast segment.
class AdminSendNotificationScreen extends StatefulWidget {
  const AdminSendNotificationScreen({super.key});
  @override
  State<AdminSendNotificationScreen> createState() =>
      _AdminSendNotificationScreenState();
}

class _AdminSendNotificationScreenState
    extends State<AdminSendNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  String _mode = 'broadcast'; // 'broadcast' or 'one_user'
  String _segment = 'all_clients';
  String _kind = 'admin';
  final _userIdCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
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
      appBar: AppBar(title: const Text('Enviar notificação')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'broadcast', label: Text('Broadcast')),
                ButtonSegment(value: 'one_user', label: Text('Um cliente')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            if (_mode == 'broadcast')
              DropdownButtonFormField<String>(
                value: _segment,
                decoration: const InputDecoration(labelText: 'Segmento'),
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
