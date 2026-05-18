// T15 — Admin partner edit dialog. Use from admin_partners_screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../stores/restaurant_store.dart';

class AdminPartnerEditDialog extends StatefulWidget {
  const AdminPartnerEditDialog({
    super.key,
    required this.restaurantId,
    required this.initialName,
    required this.initialAddress,
    required this.initialCategory,
    required this.initialPhone,
  });

  final String restaurantId;
  final String initialName;
  final String initialAddress;
  final String initialCategory;
  final String initialPhone;

  @override
  State<AdminPartnerEditDialog> createState() => _AdminPartnerEditDialogState();
}

class _AdminPartnerEditDialogState extends State<AdminPartnerEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late String _category;
  bool _saving = false;

  static const _categories = ['restaurant', 'supermarket', 'store', 'pharmacy'];
  static const _categoryLabels = {
    'restaurant': 'Restaurante', 'supermarket': 'Supermercado',
    'store': 'Loja', 'pharmacy': 'Farmácia',
  };

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _address = TextEditingController(text: widget.initialAddress);
    _phone = TextEditingController(text: widget.initialPhone);
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final store = context.read<RestaurantStore>();
      final res = await store.adminUpdatePartnerData(
        restaurantId: widget.restaurantId,
        name: _name.text.trim() != widget.initialName ? _name.text.trim() : null,
        address: _address.text.trim() != widget.initialAddress ? _address.text.trim() : null,
        category: _category != widget.initialCategory ? _category : null,
        phone: _phone.text.trim() != widget.initialPhone ? _phone.text.trim() : null,
      );
      if (mounted) {
        Navigator.pop(context, res);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['no_changes'] == true ? 'Sem alterações.' : 'Actualizado.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar dados parceiro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 8),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Endereço')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabels[c]!))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
