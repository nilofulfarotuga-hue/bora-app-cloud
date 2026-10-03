import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// T2.2 — Admin KPI: top searches + parceiros mais favoritados.
class AdminSearchKpiScreen extends StatefulWidget {
  const AdminSearchKpiScreen({super.key});
  @override
  State<AdminSearchKpiScreen> createState() => _AdminSearchKpiScreenState();
}

class _AdminSearchKpiScreenState extends State<AdminSearchKpiScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  int _periodDays = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_search_kpi', params: {'p_days': _periodDays});
      if (!mounted) return;
      setState(() {
        _data = (res as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Personalização (cliente)',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
                ButtonSegment(value: 90, label: Text('90d')),
              ],
              selected: {_periodDays},
              onSelectionChanged: (s) {
                setState(() => _periodDays = s.first);
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator())),
            if (_error != null)
              Card(
                color: AppColors.error.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
            if (_data != null) ..._sections(_data!),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(Map<String, dynamic> d) {
    final searches = (d['top_searches'] as List?) ?? const [];
    final favs = (d['top_favorited_partners'] as List?) ?? const [];
    return [
      _Section(
        title: 'Top buscas (${_periodDays}d)',
        empty: 'Sem buscas registadas.',
        children: searches.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return ListTile(
            leading: const Icon(Icons.search),
            title: Text(m['query'] as String),
            trailing: Text('${m['count']} ×'),
          );
        }).toList(),
      ),
      _Section(
        title: 'Parceiros mais favoritados',
        empty: 'Sem favoritos registados.',
        children: favs.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return ListTile(
            leading: const Icon(Icons.star, color: AppColors.warning),
            title: Text(m['partner_id'] as String),
            trailing: Text('${m['fav_count']} ★'),
          );
        }).toList(),
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title, required this.empty, required this.children});
  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (children.isEmpty)
              Text(empty, style: const TextStyle(color: AppColors.textSubtle))
            else
              ...children,
          ],
        ),
      ),
    );
  }
}
