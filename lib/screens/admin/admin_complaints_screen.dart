// T14 — Admin complaints inbox.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  String? _statusFilter; // null = all
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  static const _statuses = ['open', 'in_progress', 'resolved', 'dismissed'];
  static const _statusLabels = {
    'open': 'Aberto', 'in_progress': 'Em curso',
    'resolved': 'Resolvido', 'dismissed': 'Descartado',
  };
  static const _statusColors = {
    'open': Colors.orange, 'in_progress': Colors.blue,
    'resolved': Colors.green, 'dismissed': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_list_complaints', params: {
        'p_status_filter': _statusFilter,
        'p_limit': 100, 'p_offset': 0,
      });
      if (mounted) setState(() {
        _items = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> c) async {
    final notesCtrl = TextEditingController(text: '');
    String newStatus = c['status'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(c['subject'] ?? '—'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              value: newStatus,
              isExpanded: true,
              items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(_statusLabels[s]!))).toList(),
              onChanged: (v) => setSt(() => newStatus = v ?? newStatus),
            ),
            TextField(controller: notesCtrl, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notas admin (opcional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('admin_update_complaint_status', params: {
        'p_complaint_id': c['id'],
        'p_new_status': newStatus,
        'p_admin_notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reclamações'),
        backgroundColor: AppColors.primary,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: _statusFilter == null,
              onSelected: (_) {
                setState(() => _statusFilter = null);
                _load();
              },
            ),
            const SizedBox(width: 6),
            ..._statuses.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_statusLabels[s]!),
                    selected: _statusFilter == s,
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _load();
                    },
                  ),
                )),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('Sem reclamações.'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final c = _items[i];
                        final status = c['status'] as String;
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _statusColors[status],
                              child: const Icon(Icons.report_problem, color: Colors.white, size: 20),
                            ),
                            title: Text(c['subject'] ?? '—'),
                            subtitle: Text(
                                '${c['reporter_role']} · ${c['reporter_email']}\n'
                                '${(c['body'] as String).substring(0, ((c['body'] as String).length).clamp(0, 100))}'),
                            isThreeLine: true,
                            trailing: Chip(
                              label: Text(_statusLabels[status]!,
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: _statusColors[status],
                            ),
                            onTap: () => _changeStatus(c),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
