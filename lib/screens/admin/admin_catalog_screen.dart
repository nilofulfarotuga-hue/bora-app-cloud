// T7 — Admin catalog management.
// Two levels: list partners with counts → tap → list products with toggle/edit.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminCatalogScreen extends StatefulWidget {
  const AdminCatalogScreen({super.key});

  @override
  State<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends State<AdminCatalogScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _partners = [];

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
      final res = await Supabase.instance.client.rpc('admin_partners_with_counts', params: {
        'p_search': _search.text.isEmpty ? null : _search.text.trim(),
        'p_limit': 200, 'p_offset': 0,
      });
      if (mounted) {
        setState(() {
          _partners = List<Map<String, dynamic>>.from(res as List);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        backgroundColor: AppColors.primary,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
                hintText: 'Pesquisar parceiro', prefixIcon: Icon(Icons.search), isDense: true),
            onSubmitted: (_) => _load(),
          ),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _partners.length,
                  itemBuilder: (ctx, i) {
                    final p = _partners[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: Text((p['name'] as String).substring(0, 1).toUpperCase()),
                        ),
                        title: Text(p['name'] ?? '—'),
                        subtitle: Text('${p['category']} · ${p['active_products']}/${p['total_products']} activos'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _AdminCatalogProductsScreen(
                              restaurantId: p['id'] as String,
                              restaurantName: p['name'] as String,
                            ),
                          ),
                        ).then((_) => _load()),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _AdminCatalogProductsScreen extends StatefulWidget {
  const _AdminCatalogProductsScreen({required this.restaurantId, required this.restaurantName});
  final String restaurantId;
  final String restaurantName;

  @override
  State<_AdminCatalogProductsScreen> createState() => _AdminCatalogProductsScreenState();
}

class _AdminCatalogProductsScreenState extends State<_AdminCatalogProductsScreen> {
  final _search = TextEditingController();
  bool _onlyInactive = false;
  bool _loading = true;
  List<Map<String, dynamic>> _products = [];

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
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_list_products_by_partner', params: {
        'p_restaurant_id': widget.restaurantId,
        'p_search': _search.text.isEmpty ? null : _search.text.trim(),
        'p_only_inactive': _onlyInactive,
        'p_limit': 200, 'p_offset': 0,
      });
      if (mounted) setState(() {
        _products = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _toggleAvailability(Map<String, dynamic> p) async {
    final reasonCtrl = TextEditingController();
    final newAvail = !(p['is_available'] as bool);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newAvail ? 'Activar' : 'Desactivar'),
        content: TextField(controller: reasonCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo (mín 3)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      await Supabase.instance.client.rpc('admin_set_product_availability', params: {
        'p_product_id': p['id'],
        'p_available': newAvail,
        'p_reason': reasonCtrl.text.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _editPrice(Map<String, dynamic> p) async {
    final priceCtrl = TextEditingController(text: p['price'].toString());
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar preço — ${p['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Novo preço (€)')),
          TextField(controller: reasonCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo (mín 3)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted || reasonCtrl.text.trim().length < 3) return;
    try {
      await Supabase.instance.client.rpc('admin_update_product_price', params: {
        'p_product_id': p['id'],
        'p_new_price': double.tryParse(priceCtrl.text) ?? 0.0,
        'p_reason': reasonCtrl.text.trim(),
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
        title: Text(widget.restaurantName, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.primary,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Pesquisar', prefixIcon: Icon(Icons.search), isDense: true),
              onSubmitted: (_) => _load(),
            )),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Inactivos'),
              selected: _onlyInactive,
              onSelected: (v) {
                setState(() => _onlyInactive = v);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _products.length,
                  itemBuilder: (ctx, i) {
                    final p = _products[i];
                    final available = p['is_available'] == true;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        title: Text(p['name'] ?? '—',
                            style: TextStyle(
                                color: available ? null : Colors.grey,
                                decoration: available ? null : TextDecoration.lineThrough)),
                        subtitle: Text(
                            '€${p['price']} · ${p['taxonomy_section'] ?? p['category_root'] ?? "—"}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: Icon(available ? Icons.toggle_on : Icons.toggle_off,
                                color: available ? Colors.green : Colors.grey),
                            onPressed: () => _toggleAvailability(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPrice(p),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
