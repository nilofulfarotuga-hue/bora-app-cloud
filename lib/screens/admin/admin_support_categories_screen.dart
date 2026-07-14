// Admin — editar o menu guiado do chat (categorias + Q&A) sem redeploy.
// support_categories / support_category_options (2026-07-14).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminSupportCategoriesScreen extends StatefulWidget {
  const AdminSupportCategoriesScreen({super.key});

  @override
  State<AdminSupportCategoriesScreen> createState() =>
      _AdminSupportCategoriesScreenState();
}

class _AdminSupportCategoriesScreenState
    extends State<AdminSupportCategoriesScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('support_categories')
          .select('id, slug, label, icon, active')
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openOptions(Map<String, dynamic> category) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _CategoryOptionsScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Menu do Chat — Categorias'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final c = _categories[i];
                  final active = (c['active'] as bool?) ?? true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.lg)),
                    child: ListTile(
                      title: Text(c['label'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(active ? 'Ativa' : 'Inativa'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openOptions(c),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CategoryOptionsScreen extends StatefulWidget {
  const _CategoryOptionsScreen({required this.category});
  final Map<String, dynamic> category;

  @override
  State<_CategoryOptionsScreen> createState() =>
      _CategoryOptionsScreenState();
}

class _CategoryOptionsScreenState extends State<_CategoryOptionsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _options = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('support_category_options')
          .select('id, question, answer_md, active, sort_order')
          .eq('category_id', widget.category['id'])
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _options = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openEditDialog({Map<String, dynamic>? option}) async {
    final questionCtrl = TextEditingController(text: option?['question'] as String? ?? '');
    final answerCtrl = TextEditingController(text: option?['answer_md'] as String? ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(option == null ? 'Nova pergunta' : 'Editar pergunta'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: questionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pergunta', border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: answerCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Resposta', border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              try {
                if (option == null) {
                  await _supabase.from('support_category_options').insert({
                    'category_id': widget.category['id'],
                    'question': questionCtrl.text.trim(),
                    'answer_md': answerCtrl.text.trim(),
                    'sort_order': _options.length + 1,
                  });
                } else {
                  await _supabase.from('support_category_options').update({
                    'question': questionCtrl.text.trim(),
                    'answer_md': answerCtrl.text.trim(),
                    'updated_at': DateTime.now().toIso8601String(),
                  }).eq('id', option['id']);
                }
                if (dctx.mounted) Navigator.pop(dctx, true);
              } catch (e) {
                if (dctx.mounted) {
                  ScaffoldMessenger.of(dctx).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved == true) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> option) async {
    final active = (option['active'] as bool?) ?? true;
    await _supabase
        .from('support_category_options')
        .update({'active': !active}).eq('id', option['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: widget.category['label'] as String,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nova pergunta',
            onPressed: () => _openEditDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _options.length,
                itemBuilder: (_, i) {
                  final o = _options[i];
                  final active = (o['active'] as bool?) ?? true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.lg)),
                    child: ListTile(
                      title: Text(o['question'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        o['answer_md'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: active,
                            onChanged: (_) => _toggleActive(o),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _openEditDialog(option: o),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
