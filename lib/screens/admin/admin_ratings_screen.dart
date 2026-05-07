import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

/// Admin de avaliações (BR §44.8).
///
/// Filtros completos: sujeito, max stars, só sinalizadas, só privadas,
/// pesquisa em comentário. ORDER server-side: flagged primeiro, stars asc,
/// created desc. Drill-down em AlertDialog com toggle flag.
class AdminRatingsScreen extends StatefulWidget {
  const AdminRatingsScreen({super.key});

  @override
  State<AdminRatingsScreen> createState() => _AdminRatingsScreenState();
}

class _AdminRatingsScreenState extends State<AdminRatingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  String _subjectFilter = 'all'; // all | partner | driver | app
  int? _maxStars;
  bool _onlyFlagged = false;
  bool _onlyPrivate = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_ratings',
        params: {
          'p_subject_type': _subjectFilter == 'all' ? null : _subjectFilter,
          'p_max_stars': _maxStars,
          'p_only_flagged': _onlyFlagged,
          'p_only_private': _onlyPrivate,
          'p_search': _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          'p_limit': 200,
          'p_offset': 0,
        },
      );
      return (res as List).cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await Supabase.instance.client
          .from('ratings')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List).cast<Map<String, dynamic>>();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _showLowRated() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_low_rated_subjects',
        params: {'p_threshold': 2.0, 'p_min_count': 3},
      );
      final list = (res as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sujeitos com média < 2.0 (≥ 3 avaliações)'),
          content: SizedBox(
            width: 400,
            child: list.isEmpty
                ? const Text('Nenhum sujeito candidato a moderação.')
                : ListView(
                    shrinkWrap: true,
                    children: list
                        .map((r) => ListTile(
                              dense: true,
                              title: Text(
                                  '${r['subject_type']} · ${r['subject_id']}'),
                              subtitle: Text(
                                  'média ${r['avg_stars']} · ${r['rating_count']} avaliações'),
                              trailing: const Icon(Icons.warning,
                                  color: Colors.red),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _toggleFlag(Map<String, dynamic> rating) async {
    final id = rating['id']?.toString();
    if (id == null) return;
    final currentlyFlagged = rating['flagged_inappropriate'] == true;
    try {
      await Supabase.instance.client.rpc(
        'admin_flag_rating',
        params: {'p_rating_id': id, 'p_flag': !currentlyFlagged},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentlyFlagged
              ? 'Sinal removido.'
              : 'Avaliação sinalizada como inapropriada.'),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  String _subjectLabel(String? raw) {
    switch (raw) {
      case 'partner':
        return 'Restaurante';
      case 'driver':
        return 'Estafeta';
      case 'app':
        return 'App';
      default:
        return raw ?? '?';
    }
  }

  void _openDrillDown(Map<String, dynamic> rating) {
    showDialog<void>(
      context: context,
      builder: (_) {
        final stars = (rating['stars'] as num?)?.toInt() ?? 0;
        final comment = (rating['comment'] as String?) ?? '';
        final tags =
            (rating['tags'] as List?)?.cast<String>() ?? const <String>[];
        final isPrivate = rating['is_private'] == true;
        final isFlagged = rating['flagged_inappropriate'] == true;
        final response = (rating['response_text'] as String?) ?? '';
        return AlertDialog(
          title: Row(
            children: [
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < stars ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 18,
                  );
                }),
              ),
              const SizedBox(width: 8),
              Text(_subjectLabel(rating['subject_type'] as String?)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kv('ID', rating['id']?.toString() ?? '?'),
                _kv('Sujeito',
                    '${_subjectLabel(rating['subject_type'] as String?)} · ${rating['subject_id'] ?? '?'}'),
                _kv('Avaliador (uid)',
                    rating['rater_user_id']?.toString() ?? '?'),
                _kv('Pedido', rating['order_id']?.toString() ?? '—'),
                _kv('Data', rating['created_at']?.toString() ?? '—'),
                _kv('Privada', isPrivate ? 'Sim' : 'Não'),
                _kv('Sinalizada', isFlagged ? 'Sim' : 'Não'),
                if (comment.isNotEmpty) ...[
                  const Divider(),
                  const Text('Comentário',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(comment),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: tags
                        .map((t) => Chip(
                              label: Text(t,
                                  style: const TextStyle(fontSize: 10)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                ],
                if (response.isNotEmpty) ...[
                  const Divider(),
                  const Text('Resposta do parceiro',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(response),
                ],
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: Icon(
                isFlagged ? Icons.flag_outlined : Icons.flag,
                color: isFlagged ? Colors.grey : Colors.red,
              ),
              label: Text(
                isFlagged ? 'Remover sinal' : 'Sinalizar como inapropriado',
              ),
              onPressed: () {
                Navigator.pop(context);
                _toggleFlag(rating);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: const Text(
          'Avaliações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber, color: Colors.white),
            tooltip: 'Sujeitos com média < 2.0',
            onPressed: _showLowRated,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _subjectFilter,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Sujeito',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('Todos')),
                          DropdownMenuItem(
                              value: 'partner', child: Text('Restaurantes')),
                          DropdownMenuItem(
                              value: 'driver', child: Text('Estafetas')),
                          DropdownMenuItem(
                              value: 'app', child: Text('App')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _subjectFilter = v;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _maxStars,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Máx. estrelas',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: null, child: Text('Todas')),
                          DropdownMenuItem(value: 1, child: Text('≤ 1')),
                          DropdownMenuItem(value: 2, child: Text('≤ 2')),
                          DropdownMenuItem(value: 3, child: Text('≤ 3')),
                          DropdownMenuItem(value: 4, child: Text('≤ 4')),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _maxStars = v;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Só sinalizadas',
                            style: TextStyle(fontSize: 12)),
                        value: _onlyFlagged,
                        onChanged: (v) {
                          setState(() {
                            _onlyFlagged = v;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Só privadas',
                            style: TextStyle(fontSize: 12)),
                        value: _onlyPrivate,
                        onChanged: (v) {
                          setState(() {
                            _onlyPrivate = v;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Pesquisar comentário',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _future = _load());
                            },
                          ),
                  ),
                  onSubmitted: (_) => setState(() => _future = _load()),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }
                final list = snap.data ?? const <Map<String, dynamic>>[];
                if (list.isEmpty) {
                  return const Center(child: Text('Sem avaliações.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      final stars = (r['stars'] as num?)?.toInt() ??
                          (r['rating'] as num?)?.toInt() ??
                          0;
                      final tags = (r['tags'] as List?)?.cast<String>() ??
                          const <String>[];
                      final comment = (r['comment'] as String?) ?? '';
                      final isPrivate = r['is_private'] == true;
                      final isFlagged = r['flagged_inappropriate'] == true;
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          onTap: () => _openDrillDown(r),
                          title: Row(
                            children: [
                              Row(
                                children: List.generate(5, (idx) {
                                  return Icon(
                                    idx < stars
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 14,
                                    color: Colors.amber,
                                  );
                                }),
                              ),
                              const SizedBox(width: 6),
                              Chip(
                                label: Text(
                                  _subjectLabel(
                                      r['subject_type'] as String?),
                                  style: const TextStyle(fontSize: 10),
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              if (isPrivate) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.lock,
                                    size: 13, color: Colors.grey),
                              ],
                              if (isFlagged) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.flag,
                                    size: 13, color: Colors.red),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (comment.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    comment,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (tags.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    children: tags
                                        .take(4)
                                        .map((t) => Chip(
                                              label: Text(t,
                                                  style: const TextStyle(
                                                      fontSize: 9)),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ))
                                        .toList(),
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: isFlagged
                                ? 'Remover sinal'
                                : 'Sinalizar inapropriado',
                            icon: Icon(
                              isFlagged ? Icons.flag : Icons.flag_outlined,
                              color: isFlagged ? Colors.red : Colors.grey,
                            ),
                            onPressed: () => _toggleFlag(r),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
