// Sessão 5E B4 — Admin: sugestões skill_suggestions com 3 tipos
//   1. new_skill        (5D mantido)
//   2. playbook_update  (5E — actualizar playbook skill existente)
//   3. settings_update  (5E — actualizar support_settings SAFE)
// Zonas SAFE (1-clique) vs CRITICAL (manual SQL).
// Rollback disponível para playbook_update + settings_update implementadas.

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
  static const _critical = Color(0xFFC62828);

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'pending';
  String _typeFilter = 'all';
  String _zoneFilter = 'all';
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
    'rolled_back': 'Revertidas',
    'all': 'Todas',
  };

  static const _typeFilterOptions = <String, String>{
    'all': 'Todos os tipos',
    'new_skill': 'Nova Skill',
    'playbook_update': 'Actualizar Playbook',
    'settings_update': 'Actualizar Definição',
  };

  static const _zoneFilterOptions = <String, String>{
    'all': 'Todas as zonas',
    'safe': 'SAFE (1-clique)',
    'critical': 'CRITICAL (manual)',
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

  bool _matchesFilters(Map<String, dynamic> s) {
    if (_typeFilter != 'all' && s['proposal_type'] != _typeFilter) return false;
    if (_zoneFilter != 'all' && s['zone_type'] != _zoneFilter) return false;
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _supabase.rpc('admin_list_skill_suggestions',
          params: {'p_status': _statusFilter, 'p_limit': 100});
      final list = (data as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(_matchesFilters)
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
          params: {'p_status': 'pending', 'p_limit': 200});
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
        final breakdown = data['breakdown'] as Map?;
        String msg;
        if (reason == 'below_threshold') {
          msg = 'Análise concluída: $analyzed mensagens (abaixo do threshold)';
        } else {
          final bk = breakdown == null
              ? ''
              : ' (skills: ${breakdown['new_skill']}, '
                  'playbooks: ${breakdown['playbook_update']}, '
                  'settings: ${breakdown['settings_update']})';
          msg = 'Análise concluída: $created sugestões novas$bk';
        }
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
    final type = (s['proposal_type'] as String?) ?? 'new_skill';
    final zone = (s['zone_type'] as String?) ?? 'safe';

    if (zone == 'critical') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: _critical,
        content: Text(
            'Zona CRITICAL — requer SQL manual. Não é possível aprovar via UI.'),
      ));
      return;
    }

    switch (type) {
      case 'new_skill':
        await _approveNewSkill(s);
        break;
      case 'playbook_update':
        await _approvePlaybookUpdate(s);
        break;
      case 'settings_update':
        await _approveSettingsUpdate(s);
        break;
    }
  }

  Future<void> _approveNewSkill(Map<String, dynamic> s) async {
    final nameCtrl = TextEditingController(
        text: (s['suggested_skill_name'] as String?) ?? '');
    final categoryCtrl = TextEditingController(
        text: (s['suggested_category'] as String?) ?? '');
    final playbookCtrl = TextEditingController(
        text: (s['suggested_playbook_md'] as String?) ?? '');
    String mode = (s['suggested_mode'] as String?) ?? 'read_only';

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Aprovar nova skill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Skill criada IMEDIATAMENTE e activa. Revê o playbook.',
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
                  maxLines: 12,
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
      _toast('Skill ${nameCtrl.text.trim()} criada', _boraGreen);
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  Future<void> _approvePlaybookUpdate(Map<String, dynamic> s) async {
    final previous = (s['previous_value'] as String?) ?? '';
    final suggested = (s['suggested_playbook_md'] as String?) ?? '';
    final playbookCtrl = TextEditingController(text: suggested);

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar actualização de playbook'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Playbook actualizado IMEDIATAMENTE. version++. Rollback disponível.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                const Text('Versão actual:',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Text(previous,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Nova versão (editável):',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: playbookCtrl,
                  maxLines: 14,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
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
            child: const Text('Aprovar e actualizar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (approved != true) return;

    try {
      await _supabase.rpc('admin_approve_skill_suggestion', params: {
        'p_suggestion_id': s['id'],
        'p_playbook_md': playbookCtrl.text,
      });
      _toast('Playbook actualizado', _boraGreen);
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  Future<void> _approveSettingsUpdate(Map<String, dynamic> s) async {
    final key = (s['target_setting_key'] as String?) ?? '';
    final previous = (s['previous_value'] as String?) ?? '';
    final suggested = (s['target_setting_value'] as String?) ?? '';
    final valCtrl = TextEditingController(text: suggested);

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar actualização de definição'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Key: $key',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const SizedBox(height: 8),
              Text('Valor actual: $previous',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: valCtrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Novo valor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠️ O servidor valida cast (text→int/bool/etc). Erro CAST_FAILED se incompatível.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
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
            child: const Text('Aprovar e gravar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (approved != true) return;

    try {
      // Server reads target_setting_value from row (or we could pre-update via UPDATE
      // skill_suggestions.target_setting_value = valCtrl.text first if user edited).
      if (valCtrl.text.trim() != suggested.trim()) {
        await _supabase
            .from('skill_suggestions')
            .update({'target_setting_value': valCtrl.text.trim()})
            .eq('id', s['id']);
      }
      await _supabase.rpc('admin_approve_skill_suggestion', params: {
        'p_suggestion_id': s['id'],
      });
      _toast('Definição $key actualizada', _boraGreen);
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
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
      _toast('Sugestão rejeitada', _boraOrange);
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  Future<void> _rollback(Map<String, dynamic> s) async {
    final type = (s['proposal_type'] as String?) ?? '';
    final previous = (s['previous_value'] as String?) ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverter sugestão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                type == 'playbook_update'
                    ? 'O playbook será restaurado à versão anterior. version será decrementada.'
                    : 'A definição será restaurada ao valor anterior.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text(
                previous.length > 200
                    ? 'Valor a restaurar: ${previous.substring(0, 200)}…'
                    : 'Valor a restaurar: $previous',
                style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reverter',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.rpc('admin_rollback_suggestion', params: {
        'p_suggestion_id': s['id'],
      });
      _toast('Sugestão revertida', _amber);
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bg,
      content: Text(msg),
    ));
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
      case 'rolled_back':
        return _amber;
      default:
        return Colors.black45;
    }
  }

  ({IconData icon, String label, Color color}) _typeBadge(String type) {
    switch (type) {
      case 'new_skill':
        return (icon: Icons.auto_awesome, label: 'Nova Skill', color: _boraGreen);
      case 'playbook_update':
        return (icon: Icons.edit_note, label: 'Playbook', color: Colors.blue.shade700);
      case 'settings_update':
        return (icon: Icons.settings, label: 'Definição', color: Colors.purple.shade700);
      default:
        return (icon: Icons.help_outline, label: type, color: Colors.grey);
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
            const Text('Sugestões IA'),
            if (_pendingBadgeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            tooltip: 'Status',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
            itemBuilder: (_) => _filterOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.category),
            tooltip: 'Tipo proposta',
            initialValue: _typeFilter,
            onSelected: (v) {
              setState(() => _typeFilter = v);
              _load();
            },
            itemBuilder: (_) => _typeFilterOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.shield),
            tooltip: 'Zona',
            initialValue: _zoneFilter,
            onSelected: (v) {
              setState(() => _zoneFilter = v);
              _load();
            },
            itemBuilder: (_) => _zoneFilterOptions.entries
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
                style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                    color: Color(0xFFC62828), fontWeight: FontWeight.bold)),
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
              : 'Sem registos para os filtros activos.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'pending';
    final type = (s['proposal_type'] as String?) ?? 'new_skill';
    final zone = (s['zone_type'] as String?) ?? 'safe';
    final isPending = status == 'pending';
    final isImplemented = status == 'implemented';
    final isCritical = zone == 'critical';
    final summary = s['pattern_summary'] as String? ?? '';
    final samples = (s['sample_messages'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final msgCount = s['message_count'] as int? ?? 0;
    final rejectionReason = s['rejection_reason'] as String?;
    final previousValue = s['previous_value'] as String?;
    final canRollback = isImplemented &&
        previousValue != null &&
        (type == 'playbook_update' || type == 'settings_update');

    final typeBadge = _typeBadge(type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(typeBadge.icon, size: 16, color: typeBadge.color),
                const SizedBox(width: 4),
                Text(typeBadge.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: typeBadge.color)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCritical
                        ? _critical.withValues(alpha: 0.15)
                        : _boraGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          isCritical
                              ? Icons.warning_amber
                              : Icons.check_circle,
                          size: 12,
                          color: isCritical ? _critical : _boraGreen),
                      const SizedBox(width: 4),
                      Text(isCritical ? 'CRITICAL' : 'SAFE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCritical ? _critical : _boraGreen)),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(summary,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Text('$msgCount mensagens com este padrão',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            ..._buildTypeSpecificContent(s, type),
            if (samples.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Amostras:',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...samples.take(3).map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• "${m.length > 100 ? '${m.substring(0, 100)}…' : m}"',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  )),
            ],
            const SizedBox(height: 6),
            Text('Sugerido em: ${_formatTs(s['suggested_at'])}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45)),
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
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              if (isImplemented && s['implemented_skill_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Skill ID: ${s['implemented_skill_id']}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ),
            ],
            if (isPending) _buildPendingActions(s, isCritical),
            if (canRollback) _buildRollbackAction(s),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTypeSpecificContent(
      Map<String, dynamic> s, String type) {
    switch (type) {
      case 'new_skill':
        final skillName = s['suggested_skill_name'] as String? ?? '(sem nome)';
        final category = s['suggested_category'] as String? ?? '';
        final mode = s['suggested_mode'] as String? ?? 'read_only';
        final playbook = s['suggested_playbook_md'] as String? ?? '';
        return [
          Text('Skill sugerida: $skillName · $category · $mode',
              style: const TextStyle(
                  fontSize: 12, fontStyle: FontStyle.italic)),
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
        ];
      case 'playbook_update':
        final targetId = s['target_skill_id'];
        final previous = (s['previous_value'] as String?) ?? '';
        final suggested = (s['suggested_playbook_md'] as String?) ?? '';
        return [
          Text(
              'Skill alvo: ${targetId ?? '?'}'.length > 20
                  ? 'Skill alvo: ${(targetId as String).substring(0, 8)}…'
                  : 'Skill alvo: $targetId',
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.black54)),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Diff playbook (anterior → novo)',
                style: TextStyle(fontSize: 12)),
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFFFEBEE),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anterior:',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC62828))),
                    Text(previous,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFE8F5E9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Novo:',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20))),
                    Text(suggested,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ];
      case 'settings_update':
        final key = s['target_setting_key'] as String? ?? '';
        final newVal = s['target_setting_value'] as String? ?? '';
        final oldVal = s['previous_value'] as String? ?? '(?)';
        return [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Key: $key',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text('Antes: $oldVal',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.black54)),
                    ),
                    const Icon(Icons.arrow_forward, size: 14),
                    Expanded(
                      child: Text('Depois: $newVal',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
      default:
        return [];
    }
  }

  Widget _buildPendingActions(Map<String, dynamic> s, bool isCritical) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          if (isCritical)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: _critical),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Esta acção requer mudança manual via SQL. Aprovação via UI desactivada.',
                        style: TextStyle(fontSize: 11, color: _critical)),
                  ),
                ],
              ),
            ),
          if (isCritical) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isCritical ? Colors.grey.shade400 : _boraGreen,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.check),
                  label: const Text('Aprovar'),
                  onPressed: isCritical ? null : () => _approve(s),
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
      ),
    );
  }

  Widget _buildRollbackAction(Map<String, dynamic> s) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _amber,
            side: const BorderSide(color: _amber),
          ),
          icon: const Icon(Icons.undo),
          label: const Text('Reverter'),
          onPressed: () => _rollback(s),
        ),
      ),
    );
  }
}
