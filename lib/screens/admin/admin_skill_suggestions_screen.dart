// Sessão 5D B5 — Admin: sugestões automáticas de skills novas
// Lista skill_suggestions (pending/approved/rejected/implemented/all),
// permite aprovar (cria skill) ou rejeitar (com motivo). Realtime badge,
// botão "Analisar Agora" rate-limited 1/h, banner com cron status.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSkillSuggestionsScreen extends StatefulWidget {
  const AdminSkillSuggestionsScreen({super.key});

  @override
  State<AdminSkillSuggestionsScreen> createState() =>
      _AdminSkillSuggestionsScreenState();
}

class _AdminSkillSuggestionsScreenState
    extends State<AdminSkillSuggestionsScreen> {
  static const _boraGreen = Color(0xFF1B5E20);
  static const _boraOrange = Color(0xFFE65100);
  static const _amber = Color(0xFFFF8F00);

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'pending';
  List<Map<String, dynamic>> _suggestions = [];
  int _pendingBadgeCount = 0;
  bool _loading = false;
  bool _analyzing = false;
  DateTime? _lastAnalysisAt;
  String? _error;
  RealtimeChannel? _channel;

  static const _filterOptions = <String, String>{
    'pending': 'Pendentes',
    'approved': 'Aprovadas',
    'rejected': 'Rejeitadas',
    'implemented': 'Implementadas',
    'all': 'Todas',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _refreshBadge();
    _loadLastAnalysis();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _supabase.rpc('admin_list_skill_suggestions',
          params: {'p_status': _statusFilter, 'p_limit': 50});
      final list = (data as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _suggestions = list;
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

  Future<void> _refreshBadge() async {
    try {
      final data = await _supabase.rpc('admin_list_skill_suggestions',
          params: {'p_status': 'pending', 'p_limit': 100});
      final list = (data as List? ?? []);
      if (!mounted) return;
      setState(() => _pendingBadgeCount = list.length);
    } catch (_) {/* silent */}
  }

  Future<void> _loadLastAnalysis() async {
    try {
      final row = await _supabase
          .from('support_settings')
          .select('last_skill_analysis_at')
          .eq('id', 1)
          .maybeSingle();
      if (!mounted) return;
      final ts = row?['last_skill_analysis_at'] as String?;
      setState(() {
        _lastAnalysisAt = ts != null ? DateTime.parse(ts).toLocal() : null;
      });
    } catch (_) {/* silent */}
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_skill_suggestions');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'skill_suggestions',
      callback: (_) {
        _refreshBadge();
        _load();
      },
    ).subscribe();
  }

  Future<void> _analyzeNow() async {
    setState(() => _analyzing = true);
    try {
      final res = await _supabase.functions.invoke('analyze-conversations',
          body: {'days_back': 7, 'dry_run': false});
      if (!mounted) return;
      final data = res.data as Map?;
      if (res.status == 429) {
        final secs = data?['retry_after_seconds'] as int? ?? 3600;
        final mins = (secs / 60).ceil();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _amber,
          content: Text('Rate limit: tenta de novo em ~$mins min'),
        ));
      } else if (data != null && data['suggestions_created'] != null) {
        final created = data['suggestions_created'] as int? ?? 0;
        final analyzed = data['analyzed_messages'] as int? ?? 0;
        final reason = data['reason'] as String?;
        final msg = reason == 'below_threshold'
            ? 'Análise concluída: $analyzed mensagens (abaixo do threshold)'
            : 'Análise concluída: $created sugestões novas ($analyzed mensagens)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _boraGreen,
          content: Text(msg),
        ));
        await _load();
        await _refreshBadge();
        await _loadLastAnalysis();
      } else {
        final err = data?['error'] ?? data?['gemini_error'] ?? 'unknown';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Falhou: $err'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Erro: $e'),
      ));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> s) async {
    final nameCtrl = TextEditingController(
        text: (s['suggested_skill_name'] as String?) ?? '');
    final categoryCtrl = TextEditingController(
        text: (s['suggested_category'] as String?) ?? '');
    final playbookCtrl = TextEditingController(
        text: (s['suggested_playbook_md'] as String?) ?? '');
    String mode =
        (s['suggested_mode'] as String?) ?? 'read_only';

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Aprovar sugestão · cria skill activa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ A skill será criada IMEDIATAMENTE e activada. Revê o playbook abaixo.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Skill name (UPPER_SNAKE_CASE)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'read_only', child: Text('read_only')),
                    DropdownMenuItem(
                        value: 'write_shadow', child: Text('write_shadow')),
                    DropdownMenuItem(
                        value: 'escalate', child: Text('escalate')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => mode = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: playbookCtrl,
                  maxLines: 10,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Playbook (markdown)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _boraGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprovar e criar',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (approved != true) return;

    try {
      await _supabase.rpc('admin_approve_skill_suggestion', params: {
        'p_suggestion_id': s['id'],
        'p_skill_name': nameCtrl.text.trim(),
        'p_category': categoryCtrl.text.trim(),
        'p_mode': mode,
        'p_playbook_md': playbookCtrl.text,
        'p_allowed_tools': s['suggested_allowed_tools'] ?? [],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _boraGreen,
        content: Text('Skill ${nameCtrl.text.trim()} criada'),
      ));
      await _load();
      await _refreshBadge();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Erro: $e'),
      ));
    }
  }

  Future<void> _reject(Map<String, dynamic> s) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar sugestão'),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _boraOrange),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rejeitar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      await _supabase.rpc('admin_reject_skill_suggestion', params: {
        'p_suggestion_id': s['id'],
        'p_reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: _boraOrange,
        content: Text('Sugestão rejeitada'),
      ));
      await _load();
      await _refreshBadge();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Erro: $e'),
      ));
    }
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.parse(ts as String).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
          '${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return ts.toString();
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatNextMonday() {
    final now = DateTime.now().toUtc();
    final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
    final daysToAdd = daysUntilMonday == 0 && now.hour >= 4
        ? 7
        : (daysUntilMonday == 0 ? 0 : daysUntilMonday);
    final next = DateTime.utc(now.year, now.month, now.day, 4, 0)
        .add(Duration(days: daysToAdd));
    final local = next.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return _boraOrange;
      case 'implemented':
        return _boraGreen;
      case 'approved':
        return _boraGreen;
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.black45;
    }
  }

  bool get _analyzeButtonEnabled {
    if (_analyzing) return false;
    if (_lastAnalysisAt == null) return true;
    final diff = DateTime.now().difference(_lastAnalysisAt!);
    return diff.inHours >= 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _boraGreen,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('Sugestões Skills IA'),
            if (_pendingBadgeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _boraOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_pendingBadgeCount',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar status',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
            itemBuilder: (_) => _filterOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _refreshBadge();
          await _loadLastAnalysis();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildBanner(),
        const SizedBox(height: 12),
        if (_error != null) _buildErrorCard(),
        if (_suggestions.isEmpty && _error == null) _buildEmpty(),
        ..._suggestions.map(_buildCard),
      ],
    );
  }

  Widget _buildBanner() {
    final cronInactive = _lastAnalysisAt == null;
    return Card(
      color: cronInactive ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  cronInactive ? Icons.warning_amber : Icons.schedule,
                  color: cronInactive ? _amber : _boraGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cronInactive
                        ? 'Cron inactivo (config pendente)'
                        : 'Cron semanal: segundas 04:00 UTC',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cronInactive
                  ? 'pg_net settings ainda não configurados em prod. Usa o botão abaixo para análise manual.'
                  : 'Próxima análise automática: ${_formatNextMonday()}',
              style: const TextStyle(fontSize: 12),
            ),
            if (_lastAnalysisAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Última análise: ${_formatTs(_lastAnalysisAt!.toIso8601String())}',
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _boraGreen,
                    foregroundColor: Colors.white),
                icon: _analyzing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh),
                label: Text(_analyzing
                    ? 'A analisar…'
                    : (_analyzeButtonEnabled
                        ? 'Analisar Agora (7 dias)'
                        : 'Analisar Agora (rate-limited 1h)')),
                onPressed: _analyzeButtonEnabled ? _analyzeNow : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: const Color(0xFFFFEBEE),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Erro ao carregar',
                style: TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_error ?? '',
                style: const TextStyle(color: Color(0xFFC62828))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Center(
        child: Text(
          _statusFilter == 'pending'
              ? 'Nenhuma sugestão pendente.\nCorre análise ou aguarda cron de segunda.'
              : 'Sem registos para "${_filterOptions[_statusFilter]}".',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'pending';
    final isPending = status == 'pending';
    final summary = s['pattern_summary'] as String? ?? '';
    final samples = (s['sample_messages'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final msgCount = s['message_count'] as int? ?? 0;
    final skillName = s['suggested_skill_name'] as String? ?? '(sem nome)';
    final category = s['suggested_category'] as String? ?? '';
    final mode = s['suggested_mode'] as String? ?? 'read_only';
    final playbook = s['suggested_playbook_md'] as String? ?? '';
    final rejectionReason = s['rejection_reason'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(summary,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$msgCount mensagens com este padrão',
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text('Skill sugerida: $skillName · $category · $mode',
                style: const TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            if (samples.isNotEmpty) ...[
              const Text('Amostras:',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...samples.take(3).map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• "${m.length > 100 ? '${m.substring(0, 100)}…' : m}"',
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Ver playbook',
                  style: TextStyle(fontSize: 12)),
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFFF5F5F5),
                  child: Text(playbook,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Sugerido em: ${_formatTs(s['suggested_at'])}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.black45)),
            if (!isPending) ...[
              if (s['reviewed_at'] != null)
                Text('Revisto em: ${_formatTs(s['reviewed_at'])}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              if (rejectionReason != null && rejectionReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Motivo rejeição: $rejectionReason',
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ),
              if (status == 'implemented' && s['implemented_skill_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Skill ID: ${s['implemented_skill_id']}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _boraGreen,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprovar'),
                      onPressed: () => _approve(s),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _boraOrange,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.close),
                      label: const Text('Rejeitar'),
                      onPressed: () => _reject(s),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
