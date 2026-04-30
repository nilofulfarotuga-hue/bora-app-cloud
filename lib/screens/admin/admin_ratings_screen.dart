import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

/// Admin view: all ratings + tag filters (BR §16.2, §13.3).
///
/// Admin uses this to review "denúncia" tagged ratings manually. The ratings
/// table has RLS — admin access uses the service role via a future Edge
/// Function; for MVP, reads fall back to the user's RLS view (private
/// driver→client ratings won't appear via anon/authenticated key).
class AdminRatingsScreen extends StatefulWidget {
  const AdminRatingsScreen({super.key});

  @override
  State<AdminRatingsScreen> createState() => _AdminRatingsScreenState();
}

class _AdminRatingsScreenState extends State<AdminRatingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _onlyReports = false;
  // T2.1: filters via admin_list_ratings + admin_low_rated_subjects.
  String _subjectFilter = 'all'; // all | driver | partner
  int? _maxStars; // null = no cap

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    // T2.1: prefer admin_list_ratings RPC (SECURITY DEFINER + _admin_op_guard).
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_ratings',
        params: {
          'p_subject_type': _subjectFilter == 'all' ? null : _subjectFilter,
          'p_max_stars': _maxStars,
          'p_limit': 200,
          'p_offset': 0,
        },
      );
      final list = (res as List).cast<Map<String, dynamic>>();
      if (_onlyReports) {
        return list.where((r) {
          final tags = (r['tags'] as List?)?.cast<String>() ?? const [];
          return tags.any((t) => t.toLowerCase().contains('denún'));
        }).toList();
      }
      return list;
    } catch (_) {
      // Fallback to direct table read if RPC unavailable.
      final rows = await Supabase.instance.client
          .from('ratings')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List).cast<Map<String, dynamic>>();
    }
  }

  Future<void> _showLowRated() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_low_rated_subjects',
        params: {'p_threshold': 2.0, 'p_min_count': 3},
      );
      final list = (res as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Subjects com média < 2.0 (≥3 ratings)'),
          content: SizedBox(
            width: 400,
            child: list.isEmpty
                ? const Text('Nenhum subject candidato a banimento.')
                : ListView(
                    shrinkWrap: true,
                    children: list
                        .map((r) => ListTile(
                              dense: true,
                              title: Text(
                                  '${r['subject_type']} · ${r['subject_id']}'),
                              subtitle: Text(
                                  'média ${r['avg_stars']} · ${r['rating_count']} ratings'),
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
          'Avaliações (admin)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber, color: Colors.white),
            tooltip: 'Subjects com média < 2.0',
            onPressed: _showLowRated,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: 'Filtros',
            onSelected: (v) {
              setState(() {
                if (v == 'all' || v == 'driver' || v == 'partner') {
                  _subjectFilter = v;
                } else if (v == 'lowest') {
                  _maxStars = 2;
                } else if (v == 'all_stars') {
                  _maxStars = null;
                }
                _future = _load();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Todos')),
              PopupMenuItem(value: 'driver', child: Text('Só estafetas')),
              PopupMenuItem(value: 'partner', child: Text('Só parceiros')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'lowest', child: Text('≤ 2 estrelas')),
              PopupMenuItem(value: 'all_stars', child: Text('Todas estrelas')),
            ],
          ),
          Row(
            children: [
              const Text('Só denúncias',
                  style: TextStyle(fontSize: 12, color: Colors.white)),
              Switch(
                value: _onlyReports,
                onChanged: (v) {
                  setState(() {
                    _onlyReports = v;
                    _future = _load();
                  });
                },
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = list[i];
                final stars = (r['stars'] as num?)?.toInt() ??
                    (r['rating'] as num?)?.toInt() ??
                    0;
                final tags =
                    (r['tags'] as List?)?.cast<String>() ?? const <String>[];
                final subject =
                    '${r['subject_type'] ?? 'driver'} → ${r['subject_id'] ?? '?'}';
                return ListTile(
                  title: Text('★ $stars · $subject'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((r['comment'] as String?)?.isNotEmpty ?? false)
                        Text(r['comment'] as String),
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            children: tags
                                .map((t) => Chip(
                                      label: Text(t,
                                          style:
                                              const TextStyle(fontSize: 10)),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: EdgeInsets.zero,
                                    ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
