import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_export_service.dart';

/// T1.E — Admin: rever 281 category_root → 23 taxonomy_section.
class AdminCategoryMappingScreen extends StatefulWidget {
  const AdminCategoryMappingScreen({super.key});
  @override
  State<AdminCategoryMappingScreen> createState() =>
      _AdminCategoryMappingScreenState();
}

class _AdminCategoryMappingScreenState
    extends State<AdminCategoryMappingScreen> {
  static const _sections = <String>[
    'Mercearia', 'Bebidas', 'Frutas & Legumes', 'Higiene Pessoal',
    'Congelados', 'Charcutaria & Queijos', 'Talho', 'Animais', 'Peixaria',
    'Snacks', 'Higiene do Lar', 'Laticínios & Ovos', 'Padaria & Pastelaria',
    'Bebé', 'Vinhos & Espirituosas', 'Pequenos-Almoços', 'Conservas',
    'Bio & Saudável', 'Saúde & Bem-Estar', 'Fitness & Proteínas',
    'Pronto a Comer', 'Festa & Ocasiões', 'Outros',
  ];

  bool _loading = true;
  String _filter = 'all'; // all | unreviewed | low_confidence
  String _search = '';
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic>? _stats;
  final _searchCtrl = TextEditingController();

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
      final res = await Supabase.instance.client
          .rpc('admin_list_category_mappings', params: {
        'p_filter': _filter,
        'p_search': _search.isEmpty ? null : _search,
        'p_limit': 500,
      });
      final stats = await Supabase.instance.client
          .rpc('admin_category_mapping_stats');
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _stats = (stats as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _editMapping(Map<String, dynamic> row) async {
    String selected = row['taxonomy_section'] as String? ?? 'Outros';
    bool markReviewed = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: Text('Editar mapping'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Root: ${row['category_root']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Produtos afectados: ${row['product_count']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Secção'),
                items: _sections
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setM(() => selected = v!),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Marcar como revisto'),
                value: markReviewed,
                onChanged: (v) => setM(() => markReviewed = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await Supabase.instance.client.rpc('admin_update_category_mapping',
          params: {
            'p_category_root': row['category_root'],
            'p_taxonomy_section': selected,
            'p_mark_reviewed': markReviewed,
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mapping actualizado.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _exportCsv() async {
    final headers = ['category_root', 'taxonomy_section', 'confidence',
                     'reviewed', 'product_count'];
    final rows = _rows
        .map((r) => [
              r['category_root'] ?? '',
              r['taxonomy_section'] ?? '',
              r['confidence'] ?? '',
              r['reviewed_by_admin'] ?? '',
              r['product_count'] ?? '',
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_category_mappings_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Category mappings $stamp',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapeamento de categorias'),
        actions: [
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'CSV',
              onPressed: _exportCsv),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (s != null)
            Container(
              color: Colors.indigo.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Total', '${s['total']}', Colors.indigo),
                  _stat('Revistos', '${s['reviewed']}', Colors.green),
                  _stat('Por rever', '${s['unreviewed']}', Colors.orange),
                  _stat('→ Outros', '${s['mapped_to_outros']}', Colors.grey),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Procurar root ou secção…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                ('all', 'Todos'),
                ('unreviewed', 'Por rever'),
                ('low_confidence', 'Confidence baixa'),
              ].map((opt) {
                final isSel = _filter == opt.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(opt.$2, style: const TextStyle(fontSize: 12)),
                    selected: isSel,
                    onSelected: (_) {
                      setState(() => _filter = opt.$1);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _rows.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 80),
                              Center(child: Text('Sem resultados.')),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final reviewed =
                                  r['reviewed_by_admin'] == true;
                              final isOutros =
                                  r['taxonomy_section'] == 'Outros';
                              return Card(
                                color: !reviewed
                                    ? Colors.amber.shade50
                                    : isOutros
                                        ? Colors.grey.shade100
                                        : null,
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    reviewed
                                        ? Icons.verified
                                        : Icons.help_outline,
                                    color: reviewed
                                        ? Colors.green
                                        : Colors.orange,
                                    size: 20,
                                  ),
                                  title: Text(r['category_root'] as String),
                                  subtitle: Text(
                                      '→ ${r['taxonomy_section']} · ${r['product_count']} produtos'),
                                  trailing: Text(
                                      'conf ${r['confidence']}',
                                      style:
                                          const TextStyle(fontSize: 10)),
                                  onTap: () => _editMapping(r),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String v, Color c) => Column(
        children: [
          Text(v,
              style: TextStyle(
                  fontSize: 18, color: c, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      );
}
