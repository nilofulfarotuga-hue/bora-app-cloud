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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final base = Supabase.instance.client
        .from('ratings')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    final rows = await base;
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (_onlyReports) {
      return list.where((r) {
        final tags = (r['tags'] as List?)?.cast<String>() ?? const [];
        return tags.any((t) => t.toLowerCase().contains('denún'));
      }).toList();
    }
    return list;
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
