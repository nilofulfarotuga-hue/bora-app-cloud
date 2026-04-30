// T9 — Admin clients management screen.
// Mirrors admin_drivers_screen pattern. Uses admin_list_clients RPC.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminClientsScreen extends StatefulWidget {
  const AdminClientsScreen({super.key});

  @override
  State<AdminClientsScreen> createState() => _AdminClientsScreenState();
}

class _AdminClientsScreenState extends State<AdminClientsScreen> {
  final _search = TextEditingController();
  bool _bannedOnly = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_clients',
        params: {
          'p_search': _search.text.isEmpty ? null : _search.text.trim(),
          'p_banned_only': _bannedOnly,
          'p_limit': 100,
          'p_offset': 0,
        },
      );
      if (mounted) {
        setState(() {
          _clients = List<Map<String, dynamic>>.from(res as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ban(Map<String, dynamic> client) async {
    final reasonCtrl = TextEditingController();
    bool permanent = false;
    DateTime? until;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Banir ${client['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Ban permanente'),
                value: permanent,
                onChanged: (v) => setSt(() => permanent = v),
              ),
              if (!permanent)
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(until == null
                      ? 'Escolher data fim'
                      : 'Até ${until.toString().substring(0, 10)}'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                    );
                    if (picked != null) setSt(() => until = picked);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('BANIR'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    if (reasonCtrl.text.trim().length < 3) return;

    try {
      await Supabase.instance.client.rpc('admin_ban_client', params: {
        'p_user_id': client['user_id'],
        'p_reason': reasonCtrl.text.trim(),
        'p_banned_until': permanent ? null : until?.toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Banido')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _unban(Map<String, dynamic> client) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desbanir ${client['email']}'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desbanir')),
        ],
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      await Supabase.instance.client.rpc('admin_unban_client', params: {
        'p_user_id': client['user_id'],
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Desbanido')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _showHistory(Map<String, dynamic> client) async {
    try {
      final res = await Supabase.instance.client.rpc('admin_get_client_history', params: {
        'p_user_id': client['user_id'],
        'p_limit': 50,
      });
      if (!mounted) return;
      final data = Map<String, dynamic>.from(res as Map);
      final orders = List<Map<String, dynamic>>.from(data['orders'] as List? ?? []);
      final tokens = List<Map<String, dynamic>>.from(data['tokens'] as List? ?? []);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Histórico — ${client['email']}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('Pedidos (${orders.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              ...orders.map((o) => ListTile(
                    title: Text('${o['vendor_name'] ?? '—'} · €${o['price']}'),
                    subtitle: Text('${o['status']} · ${o['created_at']}'),
                  )),
              const SizedBox(height: 12),
              Text('Tokens (${tokens.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ...tokens.map((t) => ListTile(
                    title: Text('${t['amount']} (${t['role']})'),
                    subtitle: Text(
                        '${t['is_used'] == true ? 'usado' : 'activo'} · expira ${t['expires_at']}'),
                  )),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar email/nome/telefone',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Banidos'),
                  selected: _bannedOnly,
                  onSelected: (v) {
                    setState(() => _bannedOnly = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _clients.isEmpty
                    ? const Center(child: Text('Sem clientes.'))
                    : ListView.builder(
                        itemCount: _clients.length,
                        itemBuilder: (ctx, i) {
                          final c = _clients[i];
                          final banned = c['is_banned'] == true;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: banned ? Colors.red : AppColors.primary,
                                child: Text(((c['bora_name'] ?? c['email']) as String)
                                    .substring(0, 1)
                                    .toUpperCase()),
                              ),
                              title: Text((c['bora_name'] as String?)?.isNotEmpty == true
                                  ? c['bora_name']
                                  : c['email']),
                              subtitle: Text(
                                  '${c['email']} · ${c['total_orders']} pedidos · €${(c['total_spent'] ?? 0).toString()}\n'
                                  '${c['token_balance'] ?? 0} tokens · ${banned ? "BANIDO até ${c['banned_until']}" : "Activo"}'),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'history') _showHistory(c);
                                  if (action == 'ban') _ban(c);
                                  if (action == 'unban') _unban(c);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'history', child: Text('Histórico')),
                                  if (!banned)
                                    const PopupMenuItem(value: 'ban', child: Text('Banir')),
                                  if (banned)
                                    const PopupMenuItem(value: 'unban', child: Text('Desbanir')),
                                ],
                              ),
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
