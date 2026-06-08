import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/product_option.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Partner panel — manage option groups (modifiers) for one product.
/// Reads/writes product_option_groups + product_option_items (RLS lets only the
/// owning partner write). Self-contained CRUD; does NOT touch pricing/orders.
class ProductOptionsManageScreen extends StatefulWidget {
  const ProductOptionsManageScreen({super.key, required this.product});

  final PartnerProduct product;

  @override
  State<ProductOptionsManageScreen> createState() =>
      _ProductOptionsManageScreenState();
}

class _ProductOptionsManageScreenState
    extends State<ProductOptionsManageScreen> {
  final _db = Supabase.instance.client;
  List<ProductOptionGroup> _groups = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('product_option_groups')
          .select(
              'id,product_id,name,description,is_required,min_choices,max_choices,sort_order,product_option_items(id,name,price_add,is_available,sort_order)')
          .eq('product_id', widget.product.id)
          .order('sort_order');
      final list = (res as List)
          .map((e) => ProductOptionGroup.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (mounted) setState(() => _groups = list);
    } catch (e) {
      debugPrint('OptionsManage._load: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro a carregar opções: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([ProductOptionGroup? group]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _GroupEditorScreen(
          productId: widget.product.id,
          group: group,
          nextSortOrder: _groups.length,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteGroup(ProductOptionGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar grupo?'),
        content: Text('"${g.name}" e os seus ${g.items.length} itens serão removidos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('product_option_groups').delete().eq('id', g.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível apagar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Opções · ${widget.product.name}'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar grupo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _groupCard(_groups[i]),
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Sem grupos de opções',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Adiciona grupos como "Escolha os Acompanhamentos" ou "Extras".',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );

  Widget _groupCard(ProductOptionGroup g) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(g.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (g.isRequired
                                ? AppColors.accent
                                : AppColors.textSecondary)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        g.isRequired ? 'Obrigatório' : 'Opcional',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: g.isRequired
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Min ${g.minChoices} · Max ${g.maxChoices} · ${g.items.length} itens',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            onPressed: () => _openEditor(g),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => _deleteGroup(g),
          ),
        ],
      ),
    );
  }
}

// ─── Group editor (create / edit) ──────────────────────────────────────────────

class _ItemDraft {
  _ItemDraft({String name = '', double priceAdd = 0, this.available = true})
      : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(
            text: priceAdd == 0 ? '' : priceAdd.toStringAsFixed(2));
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  bool available;
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _GroupEditorScreen extends StatefulWidget {
  const _GroupEditorScreen({
    required this.productId,
    required this.nextSortOrder,
    this.group,
  });

  final String productId;
  final int nextSortOrder;
  final ProductOptionGroup? group;

  @override
  State<_GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends State<_GroupEditorScreen> {
  final _db = Supabase.instance.client;
  late final TextEditingController _nameCtrl;
  bool _required = false;
  int _min = 0;
  int _max = 1;
  final List<_ItemDraft> _items = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _required = g?.isRequired ?? false;
    _min = g?.minChoices ?? 0;
    _max = g?.maxChoices ?? 1;
    if (g != null) {
      for (final it in g.items) {
        _items.add(_ItemDraft(
            name: it.name, priceAdd: it.priceAdd, available: it.isAvailable));
      }
    }
    if (_items.isEmpty) _items.add(_ItemDraft());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Indica o nome do grupo.';
    if (_min > _max) return 'O mínimo não pode ser maior que o máximo.';
    if (_required && _min < 1) {
      return 'Um grupo obrigatório precisa de mínimo ≥ 1.';
    }
    final named = _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();
    if (named.isEmpty) return 'Adiciona pelo menos um item.';
    if (_max > named.length) {
      return 'O máximo ($_max) não pode exceder o nº de itens (${named.length}).';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    final named = _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();
    try {
      String groupId;
      final groupPayload = {
        'product_id': widget.productId,
        'name': _nameCtrl.text.trim(),
        'is_required': _required,
        'min_choices': _min,
        'max_choices': _max,
      };
      if (widget.group == null) {
        groupPayload['sort_order'] = widget.nextSortOrder;
        final inserted = await _db
            .from('product_option_groups')
            .insert(groupPayload)
            .select('id')
            .single();
        groupId = inserted['id'] as String;
      } else {
        groupId = widget.group!.id;
        await _db
            .from('product_option_groups')
            .update(groupPayload)
            .eq('id', groupId);
        // Replace items (simplest correct sync).
        await _db.from('product_option_items').delete().eq('group_id', groupId);
      }
      final itemRows = <Map<String, dynamic>>[];
      for (var i = 0; i < named.length; i++) {
        final it = named[i];
        itemRows.add({
          'group_id': groupId,
          'name': it.nameCtrl.text.trim(),
          'price_add': _parsePrice(it.priceCtrl.text),
          'is_available': it.available,
          'sort_order': i,
        });
      }
      if (itemRows.isNotEmpty) {
        await _db.from('product_option_items').insert(itemRows);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível guardar: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
          title: widget.group == null ? 'Novo grupo' : 'Editar grupo'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome do grupo',
                hintText: 'ex: Escolha os Acompanhamentos',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Obrigatório'),
              subtitle: const Text('O cliente tem de escolher para adicionar'),
              value: _required,
              onChanged: (v) => setState(() {
                _required = v;
                if (v && _min < 1) _min = 1;
              }),
            ),
            _stepperRow('Mínimo de escolhas', _min, (v) {
              setState(() => _min = v < 0 ? 0 : v);
            }),
            _stepperRow('Máximo de escolhas', _max, (v) {
              setState(() => _max = v < 1 ? 1 : v);
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Itens',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _items.add(_ItemDraft())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar item'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._items.asMap().entries.map((e) => _itemRow(e.key, e.value)),
            const SizedBox(height: 24),
            BoraPrimaryButton(
              label: 'Guardar grupo',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.primary,
            onPressed: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.primary,
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(int index, _ItemDraft it) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: it.nameCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: it.priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '+€',
                hintText: '0,00',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: it.available ? 'Disponível' : 'Indisponível',
            icon: Icon(
              it.available ? Icons.visibility : Icons.visibility_off,
              color: it.available ? AppColors.primary : AppColors.textSubtle,
            ),
            onPressed: () => setState(() => it.available = !it.available),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.error),
            onPressed: _items.length <= 1
                ? null
                : () => setState(() {
                      _items.removeAt(index).dispose();
                    }),
          ),
        ],
      ),
    );
  }
}

double _parsePrice(String input) {
  final n = input.trim().replaceAll(',', '.');
  if (n.isEmpty) return 0;
  return double.tryParse(n) ?? 0;
}
