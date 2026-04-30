import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});
  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final _searchCtrl = TextEditingController();
  String? _actionType;
  List<_AuditRow> _rows = const [];
  List<String> _actionTypes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActionTypes();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActionTypes() async {
    try {
      final res = await Supabase.instance.client.rpc('admin_list_audit_action_types');
      final list = (res as List).map((e) => (e as Map)['action'] as String).toList();
      if (mounted) setState(() => _actionTypes = list);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('admin_list_audit_log', params: {
        'p_search': _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        'p_action_type': _actionType,
        'p_admin_id': null,
        'p_date_from': null,
        'p_date_to': null,
        'p_limit': 200,
        'p_offset': 0,
      });
      final list = (res as List)
          .map((e) => _AuditRow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Acções')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Procurar (admin, motivo, ação)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          if (_actionTypes.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  ChoiceChip(
                    label: const Text('Todas'),
                    selected: _actionType == null,
                    onSelected: (_) {
                      setState(() => _actionType = null);
                      _load();
                    },
                  ),
                  ..._actionTypes.map((a) => Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(a),
                          selected: _actionType == a,
                          onSelected: (_) {
                            setState(() => _actionType = a);
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _rows.isEmpty
                            ? ListView(children: const [
                                SizedBox(height: 60),
                                Center(child: Text('Sem registos.')),
                              ])
                            : ListView.builder(
                                itemCount: _rows.length,
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  return ExpansionTile(
                                    title: Text(r.action,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${r.adminEmail ?? "system"} · ${_fmt(r.createdAt)}'
                                      '${r.entityType != null ? "\n${r.entityType}: ${r.entityId ?? "-"}" : ""}',
                                    ),
                                    isThreeLine: true,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: SelectableText(
                                          const JsonEncoder.withIndent('  ').convert(r.details),
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2,'0')}-${l.day.toString().padLeft(2,'0')} '
        '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';
  }
}

class _AuditRow {
  final String id;
  final String? adminId;
  final String? adminEmail;
  final String action;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  _AuditRow({
    required this.id,
    required this.adminId,
    required this.adminEmail,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.details,
    required this.createdAt,
  });
  factory _AuditRow.fromJson(Map<String, dynamic> j) => _AuditRow(
        id: j['id'] as String,
        adminId: j['admin_id'] as String?,
        adminEmail: j['admin_email'] as String?,
        action: j['action'] as String,
        entityType: j['entity_type'] as String?,
        entityId: j['entity_id'] as String?,
        details: ((j['details'] as Map?) ?? {}).cast<String, dynamic>(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// dart:convert
class JsonEncoder {
  final String indent;
  const JsonEncoder.withIndent(this.indent);
  String convert(Object? v) {
    final buf = StringBuffer();
    _w(buf, v, '');
    return buf.toString();
  }
  void _w(StringBuffer b, Object? v, String prefix) {
    if (v is Map) {
      b.writeln('{');
      final entries = v.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        b.write('$prefix$indent"${entries[i].key}": ');
        _w(b, entries[i].value, '$prefix$indent');
        if (i < entries.length - 1) b.write(',');
        b.writeln();
      }
      b.write('$prefix}');
    } else if (v is List) {
      b.writeln('[');
      for (var i = 0; i < v.length; i++) {
        b.write('$prefix$indent');
        _w(b, v[i], '$prefix$indent');
        if (i < v.length - 1) b.write(',');
        b.writeln();
      }
      b.write('$prefix]');
    } else if (v is String) {
      b.write('"${v.replaceAll('"', r'\"')}"');
    } else {
      b.write(v.toString());
    }
  }
}
