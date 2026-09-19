// Admin (PT-BR) — Catálogo de Favores (Fase 7 / Bloco 4)
// Fila de produtos extraídos do OCR de talões de favores para aprovação manual.
// Aprovar 1-clique cria loja non-partner OCULTA + produto source='errand_auto'.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminErrandCatalogScreen extends StatefulWidget {
  const AdminErrandCatalogScreen({super.key});

  @override
  State<AdminErrandCatalogScreen> createState() =>
      _AdminErrandCatalogScreenState();
}

class _AdminErrandCatalogScreenState extends State<AdminErrandCatalogScreen> {
  String _status = 'pending';
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .rpc('admin_list_errand_queue', params: {
        'p_status': _status,
        'p_limit': 100,
      });
      _items = (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
      _selected.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao listar: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(String id) async {
    try {
      await Supabase.instance.client
          .rpc('admin_approve_errand_item', params: {'p_id': id});
      _items.removeWhere((i) => i['id'] == id);
      _selected.remove(id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao aprovar: $e')));
      }
    }
  }

  Future<void> _approveSelected() async {
    final ids = List<String>.from(_selected);
    for (final id in ids) {
      await _approve(id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} item(s) aprovado(s)')));
    }
  }

  Future<void> _reject(String id) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rejeitar item'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rejeitar')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.rpc('admin_reject_errand_item', params: {
        'p_id': id,
        'p_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      });
      _items.removeWhere((i) => i['id'] == id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao rejeitar: $e')));
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final nameCtrl = TextEditingController(text: item['product_name'] as String?);
    final priceCtrl = TextEditingController(
        text: ((item['price_cents'] as int? ?? 0) / 100).toStringAsFixed(2));
    final catCtrl = TextEditingController(text: item['category'] as String?);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nome do produto')),
          TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Preço (€)', prefixText: '€ ')),
          TextField(
              controller: catCtrl,
              decoration: const InputDecoration(labelText: 'Categoria')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final priceCents =
          ((double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0) *
                  100)
              .round();
      await Supabase.instance.client.rpc('admin_edit_errand_item', params: {
        'p_id': item['id'],
        'p_product_name': nameCtrl.text.trim(),
        'p_price_cents': priceCents > 0 ? priceCents : null,
        'p_category':
            catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao editar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Catálogo de Favores'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        // Filtro
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            for (final s in ['pending', 'approved', 'rejected', 'all'])
              ChoiceChip(
                label: Text(_statusLabel(s)),
                selected: _status == s,
                onSelected: (_) {
                  setState(() => _status = s);
                  _load();
                },
              ),
          ]),
        ),
        if (_selected.isNotEmpty && _status == 'pending')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text('${_selected.length} selecionado(s)'),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _approveSelected,
                icon: const Icon(Icons.check_circle),
                label: const Text('Aprovar lote'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('Sem itens nesta categoria.'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final id = item['id'] as String;
                        final pending = item['status'] == 'pending';
                        return ListTile(
                          leading: pending
                              ? Checkbox(
                                  value: _selected.contains(id),
                                  onChanged: (v) => setState(() => v == true
                                      ? _selected.add(id)
                                      : _selected.remove(id)),
                                )
                              : Icon(item['status'] == 'approved'
                                  ? Icons.check_circle
                                  : Icons.cancel),
                          title: Text(item['product_name'] as String? ?? ''),
                          subtitle: Text(
                              '${item['store_name']} · '
                              '€${((item['price_cents'] as int? ?? 0) / 100).toStringAsFixed(2)} · '
                              '${item['category']}'),
                          trailing: pending
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _edit(item)),
                                  IconButton(
                                      tooltip: 'Aprovar',
                                      icon: const Icon(Icons.check,
                                          color: Colors.green),
                                      onPressed: () => _approve(id)),
                                  IconButton(
                                      tooltip: 'Rejeitar',
                                      icon: const Icon(Icons.close,
                                          color: Colors.red),
                                      onPressed: () => _reject(id)),
                                ])
                              : null,
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pendentes';
      case 'approved':
        return 'Aprovados';
      case 'rejected':
        return 'Rejeitados';
      default:
        return 'Todos';
    }
  }
}
