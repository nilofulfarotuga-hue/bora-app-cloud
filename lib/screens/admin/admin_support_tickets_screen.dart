// Sessão 5A-2 B16 — Admin support tickets list (mínima)
// Filtros: status + channel. Detalhe read-only + Mark Resolved.
// CRUD completo (responder, atribuir, métricas) → 5B.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSupportTicketsScreen extends StatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  State<AdminSupportTicketsScreen> createState() =>
      _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState
    extends State<AdminSupportTicketsScreen> {
  final _supabase = Supabase.instance.client;
  String? _statusFilter;
  String? _channelFilter;
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _supabase
          .from('support_tickets')
          .select('id, user_role, channel, status, subject, question, '
              'created_at, resolved_at, order_id, session_id');
      if (_statusFilter != null) query = query.eq('status', _statusFilter!);
      if (_channelFilter != null) query = query.eq('channel', _channelFilter!);
      final rows =
          await query.order('created_at', ascending: false).limit(200);
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _resolve(String ticketId) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Marcar resolvido'),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Nota opcional…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    if (notes == null) return;
    try {
      await _supabase.rpc('admin_resolve_ticket', params: {
        'p_ticket_id': ticketId,
        if (notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ticket resolvido.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suporte — Tickets'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    value: _statusFilter,
                    isExpanded: true,
                    hint: const Text('Status: todos'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(
                          value: 'in_progress', child: Text('In progress')),
                      DropdownMenuItem(
                          value: 'resolved', child: Text('Resolved')),
                      DropdownMenuItem(
                          value: 'closed', child: Text('Closed')),
                    ],
                    onChanged: (v) {
                      setState(() => _statusFilter = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    value: _channelFilter,
                    isExpanded: true,
                    hint: const Text('Canal: todos'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(
                          value: 'chatbot', child: Text('Chatbot')),
                      DropdownMenuItem(
                          value: 'whatsapp', child: Text('WhatsApp')),
                      DropdownMenuItem(value: 'email', child: Text('Email')),
                    ],
                    onChanged: (v) {
                      setState(() => _channelFilter = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFC62828))),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tickets.isEmpty
                    ? const Center(child: Text('Sem tickets.'))
                    : ListView.builder(
                        itemCount: _tickets.length,
                        itemBuilder: (_, i) {
                          final t = _tickets[i];
                          final id = t['id'] as String;
                          return ListTile(
                            title: Text(
                              (t['subject'] as String?)?.isNotEmpty == true
                                  ? t['subject'] as String
                                  : (t['question'] as String? ?? '(sem assunto)'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${t['channel'] ?? '—'} · ${t['status']} · '
                              '${t['user_role']} · ${(t['created_at'] as String).substring(0, 19)}',
                            ),
                            trailing: t['status'] == 'resolved'
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : IconButton(
                                    icon: const Icon(Icons.task_alt),
                                    tooltip: 'Marcar resolvido',
                                    onPressed: () => _resolve(id),
                                  ),
                            onTap: () => _showDetail(t),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showDetail(Map<String, dynamic> t) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text((t['subject'] as String?) ?? '(sem assunto)'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('id', (t['id'] as String).substring(0, 8)),
              _row('canal', t['channel']?.toString() ?? '—'),
              _row('role', t['user_role']?.toString() ?? '—'),
              _row('status', t['status']?.toString() ?? '—'),
              _row('order', t['order_id']?.toString() ?? '—'),
              _row('session', t['session_id']?.toString() ?? '—'),
              _row('criado', t['created_at']?.toString() ?? '—'),
              if (t['resolved_at'] != null)
                _row('resolvido', t['resolved_at'].toString()),
              const Divider(),
              const Text('Pergunta/body:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(t['question']?.toString() ?? '—'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$label: $value', style: const TextStyle(fontSize: 13)),
      );
}
