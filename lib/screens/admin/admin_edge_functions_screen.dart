import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// T5.5 — Admin Edge Functions monitor.
/// Lista das 17 Edge Fns + erros recentes (mbway + edge_function_invocations).
class AdminEdgeFunctionsScreen extends StatefulWidget {
  const AdminEdgeFunctionsScreen({super.key});
  @override
  State<AdminEdgeFunctionsScreen> createState() =>
      _AdminEdgeFunctionsScreenState();
}

class _AdminEdgeFunctionsScreenState extends State<AdminEdgeFunctionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await Supabase.instance.client.rpc('admin_edge_fn_health');
      if (!mounted) return;
      setState(() {
        _data = (res as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge Functions'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Funções'),
            Tab(text: 'Erros recentes'),
            Tab(text: 'MBWay'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildFnList(),
              _buildErrors(),
              _buildMbwayErrors(),
            ]),
    );
  }

  Widget _buildFnList() {
    final fns = (_data?['fn_list'] as List?) ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Lista das Edge Functions deployed.\n'
              'Para versão e ACTIVE/ERROR detalhado, ver Supabase Dashboard.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          ...fns.map((slug) => Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_done, color: Colors.green),
                  title: Text(slug as String,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildErrors() {
    final errors = (_data?['recent_errors'] as List?) ?? const [];
    if (errors.isEmpty) {
      return const Center(child: Text('Sem erros nos últimos 7 dias.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: errors.length,
        itemBuilder: (_, i) {
          final e = (errors[i] as Map).cast<String, dynamic>();
          return Card(
            color: Colors.red.shade50,
            child: ListTile(
              leading: const Icon(Icons.error, color: Colors.red),
              title: Text(e['fn_slug'] as String? ?? '?'),
              subtitle: Text(
                  '${e['error_message'] ?? ''}\n${e['created_at'] ?? ''}'),
              isThreeLine: true,
              trailing: Text(e['error_code'] as String? ?? '',
                  style: const TextStyle(fontSize: 11)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMbwayErrors() {
    final errs = (_data?['mbway_errors'] as List?) ?? const [];
    if (errs.isEmpty) {
      return const Center(child: Text('Sem erros MBWay nos últimos 7 dias.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: errs.length,
        itemBuilder: (_, i) {
          final e = (errs[i] as Map).cast<String, dynamic>();
          return Card(
            color: Colors.orange.shade50,
            child: ListTile(
              leading: const Icon(Icons.payment, color: Colors.orange),
              title: Text(e['error_message'] as String? ?? ''),
              subtitle: Text(
                  'order ${(e['order_id'] as String?)?.substring(0, 8) ?? ''} · ${e['stripe_mode'] ?? ''}\n${e['created_at'] ?? ''}'),
              isThreeLine: true,
              trailing: Text(e['error_code'] as String? ?? '',
                  style: const TextStyle(fontSize: 11)),
            ),
          );
        },
      ),
    );
  }
}
