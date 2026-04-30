import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPromoCodesScreen extends StatefulWidget {
  const AdminPromoCodesScreen({super.key});
  @override
  State<AdminPromoCodesScreen> createState() => _S();
}

class _S extends State<AdminPromoCodesScreen> {
  bool _activeOnly = false;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.rpc('admin_list_promo_codes', params: {
        'p_active_only': _activeOnly,
        'p_search': _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        'p_limit': 200, 'p_offset': 0,
      });
      final list = ((res as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final code = TextEditingController();
    String type = 'percent_off';
    final value = TextEditingController();
    final minOrder = TextEditingController(text: '0');
    final maxUses = TextEditingController();
    final maxPerUser = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Novo promo code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Código (ex BORA10)')),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'percent_off', child: Text('% desconto')),
                    DropdownMenuItem(value: 'fixed_off', child: Text('€ desconto fixo')),
                    DropdownMenuItem(value: 'free_delivery', child: Text('Entrega grátis')),
                  ],
                  onChanged: (v) => set(() => type = v!),
                ),
                if (type == 'percent_off')
                  TextField(controller: value, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '% (0.10 = 10%)')),
                if (type == 'fixed_off')
                  TextField(controller: value, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cents (200 = €2.00)')),
                TextField(controller: minOrder, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min order cents')),
                TextField(controller: maxUses, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max usos total (vazio = ilimitado)')),
                TextField(controller: maxPerUser, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max por user')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_create_promo_code', params: {
        'p_code': code.text.trim().toUpperCase(),
        'p_type': type,
        'p_value_cents': type == 'fixed_off' ? int.tryParse(value.text) : null,
        'p_value_pct': type == 'percent_off' ? double.tryParse(value.text) : null,
        'p_max_uses': maxUses.text.trim().isEmpty ? null : int.tryParse(maxUses.text),
        'p_max_uses_per_user': int.tryParse(maxPerUser.text) ?? 1,
        'p_min_order_cents': int.tryParse(minOrder.text) ?? 0,
        'p_valid_until': null,
        'p_partner_ids': null,
      });
      if (mounted) await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _deactivate(String code) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Desativar $code'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Motivo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_deactivate_promo_code',
          params: {'p_code': code, 'p_reason': ctrl.text.trim()});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promo Codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
                    hintText: 'Procurar código',
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Só ativos'), selected: _activeOnly,
                onSelected: (v) { setState(() => _activeOnly = v); _load(); },
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final desc = r['type'] == 'percent_off'
                              ? '${((r['value_pct'] as num) * 100).toStringAsFixed(0)}% off'
                              : r['type'] == 'fixed_off'
                                ? '€${((r['value_cents'] as num) / 100).toStringAsFixed(2)} off'
                                : 'Entrega grátis';
                            return ListTile(
                              title: Text(r['code'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '$desc · ${r['uses_count']}/${r['max_uses'] ?? '∞'} usos · '
                                  'min €${((r['min_order_cents'] as num) / 100).toStringAsFixed(2)}'),
                              trailing: r['is_active'] as bool
                                  ? IconButton(
                                      icon: const Icon(Icons.block, color: Colors.red),
                                      onPressed: () => _deactivate(r['code']),
                                    )
                                  : const Chip(label: Text('Inativo')),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
