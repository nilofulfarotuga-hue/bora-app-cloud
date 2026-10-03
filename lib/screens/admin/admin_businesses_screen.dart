// BLOCO 7.2 — Admin "Comércios da Guarda" (PT-BR).
// Lista paginada + pesquisável de public.guarda_businesses via RPCs admin
// (admin_list/upsert/set_visibility/delete_business — guard _admin_op_guard).
// Botão "Reimportar" invoca a Edge Function import-guarda-businesses.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminBusinessesScreen extends StatefulWidget {
  const AdminBusinessesScreen({super.key});

  @override
  State<AdminBusinessesScreen> createState() => _AdminBusinessesScreenState();
}

class _AdminBusinessesScreenState extends State<AdminBusinessesScreen> {
  static const _categories = <String>[
    'supermarket',
    'convenience',
    'pharmacy',
    'bakery',
    'cafe',
    'restaurant',
    'fast_food',
    'bar',
    'fuel',
    'marketplace',
    'other',
  ];

  final _searchCtrl = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _reimporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_businesses',
        params: {
          'p_search': _searchCtrl.text.trim(),
          'p_limit': 100,
          'p_offset': 0,
        },
      );
      final list = (res as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Erro ao carregar: ${_clean(e)}');
    }
  }

  Future<void> _reimport() async {
    setState(() => _reimporting = true);
    try {
      final res = await Supabase.instance.client.functions
          .invoke('import-guarda-businesses');
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['ok'] == true) {
        _snack('Importados ${data['imported']} comércios.');
        await _load();
      } else {
        _snack('Falha na importação: ${data?['error'] ?? 'desconhecida'}');
      }
    } catch (e) {
      _snack('Erro na importação: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _reimporting = false);
    }
  }

  Future<void> _setVisibility(Map<String, dynamic> b, bool visible) async {
    try {
      await Supabase.instance.client.rpc('admin_set_business_visibility',
          params: {'p_id': b['id'], 'p_visible': visible});
      setState(() => b['is_visible'] = visible);
    } catch (e) {
      _snack('Erro: ${_clean(e)}');
    }
  }

  Future<void> _delete(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar comércio'),
        content: Text('Apagar "${b['name']}"? Esta ação é definitiva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .rpc('admin_delete_business', params: {'p_id': b['id']});
      setState(() => _items.remove(b));
      _snack('Comércio apagado.');
    } catch (e) {
      _snack('Erro ao apagar: ${_clean(e)}');
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BusinessEditorDialog(
        existing: existing,
        categories: _categories,
      ),
    );
    if (saved == true) await _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException(message: ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comércios da Guarda'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Reimportar comércios da Guarda',
            onPressed: _reimporting ? null : _reimport,
            icon: _reimporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Pesquisar nome ou endereço…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _load,
                ),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const Expanded(
              child: Center(child: Text('Nenhum comércio. Use "Reimportar".')),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tile(_items[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> b) {
    final visible = b['is_visible'] == true;
    final source = b['source'] as String? ?? 'osm';
    return Opacity(
      opacity: visible ? 1 : 0.5,
      child: ListTile(
        title: Text(b['name']?.toString() ?? '—'),
        subtitle: Text([
          b['category'],
          if (b['address'] != null) b['address'],
          'fonte: $source',
        ].where((e) => e != null).join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: visible ? 'Esconder' : 'Mostrar',
            icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
            onPressed: () => _setVisibility(b, !visible),
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openEditor(existing: b),
          ),
          IconButton(
            tooltip: 'Apagar',
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => _delete(b),
          ),
        ]),
      ),
    );
  }
}

class _BusinessEditorDialog extends StatefulWidget {
  const _BusinessEditorDialog({required this.existing, required this.categories});
  final Map<String, dynamic>? existing;
  final List<String> categories;

  @override
  State<_BusinessEditorDialog> createState() => _BusinessEditorDialogState();
}

class _BusinessEditorDialogState extends State<_BusinessEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late String _category;
  late bool _visible;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _address = TextEditingController(text: e?['address']?.toString() ?? '');
    _lat = TextEditingController(text: e?['lat']?.toString() ?? '');
    _lng = TextEditingController(text: e?['lng']?.toString() ?? '');
    _category = (e?['category'] as String?) ?? 'other';
    if (!widget.categories.contains(_category)) _category = 'other';
    _visible = e?['is_visible'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O nome é obrigatório.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('admin_upsert_business', params: {
        'p_id': widget.existing?['id'],
        'p_name': _name.text.trim(),
        'p_category': _category,
        'p_address':
            _address.text.trim().isEmpty ? null : _address.text.trim(),
        'p_lat': double.tryParse(_lat.text.trim().replaceAll(',', '.')),
        'p_lng': double.tryParse(_lng.text.trim().replaceAll(',', '.')),
        'p_is_visible': _visible,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao guardar: '
              '${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Adicionar comércio'
          : 'Editar comércio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Endereço'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lng,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visível'),
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
