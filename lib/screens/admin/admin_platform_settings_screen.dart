import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin Platform Settings — edit configurable parameters in `platform_settings`.
/// HIGH-RISK: changes propagate live; use with care. All changes audited.
class AdminPlatformSettingsScreen extends StatefulWidget {
  const AdminPlatformSettingsScreen({super.key});
  @override
  State<AdminPlatformSettingsScreen> createState() => _AdminPlatformSettingsScreenState();
}

class _AdminPlatformSettingsScreenState extends State<AdminPlatformSettingsScreen> {
  Map<String, List<_Setting>> _byCategory = const {};
  bool _loading = true;
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
      final res = await Supabase.instance.client.rpc('admin_list_settings',
          params: {'p_category': null});
      final list = (res as List)
          .map((e) => _Setting.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final by = <String, List<_Setting>>{};
      for (final s in list) {
        by.putIfAbsent(s.category ?? 'other', () => []).add(s);
      }
      if (mounted) setState(() => _byCategory = by);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editSetting(_Setting s) async {
    final ctrl = TextEditingController(text: s.value.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.key),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.description != null) Text(s.description!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Valor (JSON)',
                border: OutlineInputBorder(),
                hintText: 'ex: 250 ou 0.80 ou "abc"',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ Esta alteração propaga-se live. Tens a certeza?',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Atualizar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Try parse as number first, then as raw JSON, fallback to quoted string.
      final txt = ctrl.text.trim();
      dynamic parsed;
      final asNum = num.tryParse(txt);
      if (asNum != null) {
        parsed = asNum;
      } else if (txt == 'true' || txt == 'false') {
        parsed = txt == 'true';
      } else {
        parsed = txt;
      }
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': s.key, 'p_value': parsed});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: _byCategory.entries.map((entry) {
                      return ExpansionTile(
                        title: Text(entry.key.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        children: entry.value.map((s) {
                          return ListTile(
                            title: Text(s.key, style: const TextStyle(fontFamily: 'monospace')),
                            subtitle: s.description != null ? Text(s.description!) : null,
                            trailing: Text(s.value.toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            onTap: () => _editSetting(s),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}

class _Setting {
  final String key;
  final dynamic value;
  final String? description;
  final String? category;
  _Setting({required this.key, required this.value, this.description, this.category});
  factory _Setting.fromJson(Map<String, dynamic> j) => _Setting(
        key: j['key'] as String,
        value: j['value'],
        description: j['description'] as String?,
        category: j['category'] as String?,
      );
}
