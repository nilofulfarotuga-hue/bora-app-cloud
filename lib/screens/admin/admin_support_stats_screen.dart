// Sessão 6 B3 — Painel admin: estatísticas robô IA suporte.
// Chama RPC admin_get_support_stats(p_from, p_to) — SECURITY DEFINER admin-only.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminSupportStatsScreen extends StatefulWidget {
  const AdminSupportStatsScreen({super.key});

  @override
  State<AdminSupportStatsScreen> createState() =>
      _AdminSupportStatsScreenState();
}

class _AdminSupportStatsScreenState extends State<AdminSupportStatsScreen> {
  final _supabase = Supabase.instance.client;

  late DateTime _from;
  late DateTime _to;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _to = DateTime.now();
    _from = _to.subtract(const Duration(days: 30));
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase.rpc(
        'admin_get_support_stats',
        params: {
          'p_from': _from.toUtc().toIso8601String(),
          'p_to': _to.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      setState(() {
        _data = (res is Map) ? Map<String, dynamic>.from(res) : null;
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

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
      await _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estatísticas Suporte IA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Período',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Erro: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }
    final d = _data;
    if (d == null) {
      return const Center(child: Text('Sem dados no período.'));
    }

    final sessionsTotal = (d['sessions_total'] ?? 0) as int;
    final sessionsResolved = (d['sessions_resolved'] ?? 0) as int;
    final sessionsEscalated = (d['sessions_escalated'] ?? 0) as int;
    final resolutionPct = (d['resolution_rate_pct'] ?? 0).toString();
    final avgMsgs = (d['avg_messages_per_session'] ?? 0).toString();
    final tokens = (d['tokens'] is Map)
        ? Map<String, dynamic>.from(d['tokens'] as Map)
        : <String, dynamic>{};
    final inputTk = (tokens['input_tokens'] ?? 0) as int;
    final outputTk = (tokens['output_tokens'] ?? 0) as int;
    final totalTk = (tokens['total_tokens'] ?? 0) as int;
    final cost = (d['cost_eur_estimated'] ?? 0).toString();
    final topSkills = (d['top_skills'] as List?) ?? const [];
    final escalating = (d['escalating_skills'] as List?) ?? const [];
    final tickets = (d['tickets_by_channel'] as List?) ?? const [];
    final avgSat = (d['avg_satisfaction'] ?? 0).toString();
    final satRated = (d['satisfaction_responses'] ?? 0) as int;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _periodCard(),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              _StatCard(
                title: 'Sessões totais',
                value: '$sessionsTotal',
                icon: Icons.forum_outlined,
                color: AppColors.primary,
              ),
              _StatCard(
                title: 'Resolução robô',
                value: '$resolutionPct%',
                subtitle: '$sessionsResolved resolvidas',
                icon: Icons.check_circle_outline,
                color: Colors.green,
              ),
              _StatCard(
                title: 'Escaladas',
                value: '$sessionsEscalated',
                icon: Icons.flag_outlined,
                color: Colors.orange,
              ),
              _StatCard(
                title: 'Custo Gemini',
                value: '€$cost',
                subtitle: 'in $inputTk · out $outputTk',
                icon: Icons.euro,
                color: Colors.purple,
                tooltip:
                    'Total tokens: $totalTk\nInput: $inputTk · Output: $outputTk\nPreço: €0.067/M in + €0.27/M out',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('Skills mais usadas'),
          if (topSkills.isEmpty)
            const _EmptyHint('Sem skills usadas no período.')
          else
            ...topSkills.map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              return _SkillTile(
                name: (m['active_skill'] ?? '?').toString(),
                trailing: '${m['uses']} usos',
                subtitle: 'Sucesso ${m['success_rate_pct'] ?? 0}%',
              );
            }),
          const SizedBox(height: 16),
          _sectionTitle('Skills com mais escalações'),
          if (escalating.isEmpty)
            const _EmptyHint('Sem escalações no período. ✅')
          else
            ...escalating.map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              return _SkillTile(
                name: (m['active_skill'] ?? '?').toString(),
                trailing: '${m['escalations']}',
                subtitle: 'Atenção: melhorar prompt/skill',
                warning: true,
              );
            }),
          const SizedBox(height: 16),
          _sectionTitle('Mensagens · Tickets · Satisfação'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Média mensagens/sessão: $avgMsgs'),
                  const SizedBox(height: 6),
                  Text('Satisfação média: $avgSat ($satRated respostas)'),
                  const SizedBox(height: 6),
                  Text('Tickets por canal:'),
                  if (tickets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('— sem tickets',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...tickets.map((t) {
                      final m = Map<String, dynamic>.from(t as Map);
                      return Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Text('• ${m['channel']}: ${m['c']}'),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _periodCard() {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.date_range),
        title: Text('${fmt(_from)} → ${fmt(_to)}'),
        subtitle: const Text('Toca no calendário no topo para mudar'),
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.tooltip,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: card) : card;
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.name,
    required this.trailing,
    this.subtitle,
    this.warning = false,
  });

  final String name;
  final String trailing;
  final String? subtitle;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          warning ? Icons.warning_amber_outlined : Icons.psychology_outlined,
          color: warning ? Colors.orange : AppColors.primary,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: Text(trailing,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    );
  }
}
