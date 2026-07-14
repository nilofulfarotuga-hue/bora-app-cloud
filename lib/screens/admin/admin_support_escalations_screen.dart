// Escalações do chat guiado (2026-07-14) — quando o Hermes (persona
// Thayline/Thabyta) não sabe resolver, a pergunta cai aqui. Responder aqui
// grava a resposta na mesma sessão do cliente via admin_reply_escalation
// (a mesma RPC que o Hermes/Telegram usa do lado VPS).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminSupportEscalationsScreen extends StatefulWidget {
  const AdminSupportEscalationsScreen({super.key});

  @override
  State<AdminSupportEscalationsScreen> createState() =>
      _AdminSupportEscalationsScreenState();
}

class _AdminSupportEscalationsScreenState
    extends State<AdminSupportEscalationsScreen> {
  static const _boraGreen = AppColors.primary;
  static const _amber = Color(0xFFFF8F00);

  final _supabase = Supabase.instance.client;
  bool _showAnswered = false;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_support_escalations');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'support_escalations',
      callback: (_) => _load(),
    ).subscribe();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _supabase
          .from('support_escalations')
          .select('id, session_id, user_id, user_role, question, '
              'persona_name, status, danilo_reply, created_at, answered_at')
          .eq('status', _showAnswered ? 'answered' : 'pending')
          .order('created_at', ascending: false)
          .limit(100);
      final rows = await query;
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.parse(ts as String).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
          '${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return ts.toString();
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _openReplyDialog(Map<String, dynamic> item) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final question = (item['question'] as String?) ?? '';

    final answer = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) {
        return AlertDialog(
          title: const Text('Responder ao cliente'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(question, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: 'Resposta (aparece no chat como '
                          '${(item['persona_name'] as String?) ?? 'Bora'})',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'A resposta não pode ficar vazia'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _boraGreen,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Enviar'),
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dctx, controller.text.trim());
              },
            ),
          ],
        );
      },
    );

    if (answer == null || answer.isEmpty) return;
    if (!mounted) return;

    try {
      await _supabase.rpc('admin_reply_escalation', params: {
        'p_escalation_id': item['id'],
        'p_reply': answer,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: _boraGreen, content: Text('✅ Resposta enviada')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.error, content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Suporte — Escalações',
        actions: [
          IconButton(
            tooltip: _showAnswered ? 'Ver pendentes' : 'Ver respondidas',
            icon: Icon(_showAnswered ? Icons.hourglass_top : Icons.history),
            onPressed: () {
              setState(() => _showAnswered = !_showAnswered);
              _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: AppColors.primaryWash,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.support_agent, color: _boraGreen),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A Thayline/Thabyta (Hermes) passou-te estas conversas. '
                    'A tua resposta volta para o chat do cliente.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Card(
            color: AppColors.error.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Erro: $_error', style: const TextStyle(color: AppColors.error)),
            ),
          ),
        if (_items.isEmpty && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(
                _showAnswered ? 'Sem escalações respondidas.' : 'Sem escalações pendentes 🎉',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ),
          ),
        ..._items.map(_buildCard),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final status = (item['status'] as String?) ?? 'pending';
    final persona = (item['persona_name'] as String?) ?? 'Bora';
    final question = (item['question'] as String?) ?? '';
    final reply = item['danilo_reply'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('via $persona',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (status == 'pending' ? _amber : _boraGreen).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: status == 'pending' ? _amber : _boraGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            Text(_formatTs(item['created_at']),
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: BoraPrimaryButton(
                  label: 'Responder',
                  icon: Icons.reply,
                  expanded: false,
                  onPressed: () => _openReplyDialog(item),
                ),
              ),
            ],
            if (reply != null && reply.isNotEmpty) ...[
              const Divider(height: 16, color: AppColors.divider),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(reply,
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
