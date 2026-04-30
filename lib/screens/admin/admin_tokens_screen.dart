// T8 — Admin token management screen.
// Search user → balance + grants. Grant new + revoke specific.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminTokensScreen extends StatefulWidget {
  const AdminTokensScreen({super.key});

  @override
  State<AdminTokensScreen> createState() => _AdminTokensScreenState();
}

class _AdminTokensScreenState extends State<AdminTokensScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchClient = TextEditingController();
  String? _selectedUserId;
  String? _selectedUserLabel;
  bool _loading = false;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchClient.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final q = _searchClient.text.trim();
    if (q.isEmpty) return;
    final role = _tab.index == 0 ? 'client' : 'driver';
    try {
      // For clients, use admin_list_clients. For drivers, query drivers table directly.
      if (role == 'client') {
        final res = await Supabase.instance.client.rpc('admin_list_clients', params: {
          'p_search': q, 'p_banned_only': false, 'p_limit': 20, 'p_offset': 0,
        });
        setState(() => _searchResults = List<Map<String, dynamic>>.from(res as List));
      } else {
        final res = await Supabase.instance.client
            .from('drivers')
            .select('id, name, phone, email')
            .or('name.ilike.%$q%,phone.ilike.%$q%,email.ilike.%$q%')
            .limit(20);
        setState(() => _searchResults = List<Map<String, dynamic>>.from(res as List));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _selectUser(String userId, String label) async {
    setState(() {
      _selectedUserId = userId;
      _selectedUserLabel = label;
      _loading = true;
      _searchResults = [];
    });
    try {
      final role = _tab.index == 0 ? 'client' : 'driver';
      final res = await Supabase.instance.client.rpc('admin_get_user_tokens', params: {
        'p_user_id': userId, 'p_role': role, 'p_limit': 100,
      });
      setState(() {
        _data = Map<String, dynamic>.from(res as Map);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _grantTokens() async {
    if (_selectedUserId == null) return;
    final amountCtrl = TextEditingController(text: '100');
    final reasonCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '60');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atribuir tokens'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amountCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade')),
          TextField(controller: daysCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Validade (dias)')),
          TextField(controller: reasonCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo (mín 3)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Atribuir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('admin_grant_tokens', params: {
        'p_user_id': _selectedUserId,
        'p_role': _tab.index == 0 ? 'client' : 'driver',
        'p_amount': int.tryParse(amountCtrl.text) ?? 0,
        'p_reason': reasonCtrl.text.trim(),
        'p_validity_days': int.tryParse(daysCtrl.text) ?? 60,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atribuído')));
        _selectUser(_selectedUserId!, _selectedUserLabel!);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _revokeGrant(Map<String, dynamic> grant) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revogar grant ${grant['amount']} tokens?'),
        content: TextField(
          controller: reasonCtrl, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      await Supabase.instance.client.rpc('admin_revoke_token_grant', params: {
        'p_token_id': grant['id'],
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revogado')));
        _selectUser(_selectedUserId!, _selectedUserLabel!);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tokens'),
        backgroundColor: AppColors.primary,
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Clientes'), Tab(text: 'Estafetas')],
            onTap: (_) {
              setState(() {
                _selectedUserId = null;
                _data = null;
                _searchResults = [];
              });
            }),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchClient,
            decoration: InputDecoration(
              hintText: 'Pesquisar utilizador',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _searchUser),
            ),
            onSubmitted: (_) => _searchUser(),
          ),
        ),
        if (_searchResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(
              shrinkWrap: true,
              children: _searchResults.map((r) {
                final id = (r['user_id'] ?? r['id']).toString();
                final label = (r['email'] ?? r['name'] ?? r['phone'] ?? '?').toString();
                return ListTile(
                  title: Text(label),
                  subtitle: Text(id),
                  onTap: () => _selectUser(id, label),
                );
              }).toList(),
            ),
          ),
        if (_selectedUserId != null && _data != null)
          Expanded(child: _buildSelectedUserView()),
      ]),
      floatingActionButton: _selectedUserId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _grantTokens,
              icon: const Icon(Icons.add),
              label: const Text('Atribuir'),
            ),
    );
  }

  Widget _buildSelectedUserView() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final balance = _data!['balance'];
    final grants = List<Map<String, dynamic>>.from(_data!['grants'] as List? ?? []);
    return Column(children: [
      Card(
        margin: const EdgeInsets.all(12),
        child: ListTile(
          leading: const Icon(Icons.account_balance_wallet, size: 40, color: AppColors.primary),
          title: Text(_selectedUserLabel ?? '—'),
          subtitle: Text('Saldo activo: $balance tokens'),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _selectUser(_selectedUserId!, _selectedUserLabel!),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: grants.length,
          itemBuilder: (ctx, i) {
            final g = grants[i];
            final active = g['is_active'] == true;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: Icon(
                  active ? Icons.check_circle : Icons.cancel,
                  color: active ? Colors.green : Colors.grey,
                ),
                title: Text('${g['amount']} tokens (${g['role']})'),
                subtitle: Text(
                    'Criado ${(g['created_at'] as String?)?.substring(0, 10) ?? "?"} · expira ${(g['expires_at'] as String?)?.substring(0, 10) ?? "?"}'
                    '${g['source_order_id'] == null ? " · MANUAL" : ""}'),
                trailing: active
                    ? IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _revokeGrant(g),
                      )
                    : const Text('usado', style: TextStyle(fontSize: 12)),
              ),
            );
          },
          ),
        ),
      ),
    ]);
  }
}
