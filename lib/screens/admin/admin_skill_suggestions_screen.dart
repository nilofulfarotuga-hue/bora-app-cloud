// Sessão 5E B4 — Admin: sugestões skill_suggestions com 3 tipos
//   1. new_skill        (5D mantido)
//   2. playbook_update  (5E — actualizar playbook skill existente)
//   3. settings_update  (5E — actualizar support_settings SAFE)
// Zonas SAFE (1-clique) vs CRITICAL (manual SQL).
// Rollback disponível para playbook_update + settings_update implementadas.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminSkillSuggestionsScreen extends StatefulWidget {
  const AdminSkillSuggestionsScreen({super.key});

  @override
  State<AdminSkillSuggestionsScreen> createState() =>
      _AdminSkillSuggestionsScreenState();
}

class _AdminSkillSuggestionsScreenState
    extends State<AdminSkillSuggestionsScreen> {
  static const _boraGreen = AppColors.primary;
  static const _boraOrange = AppColors.accent;
  static const _amber = Color(0xFFFF8F00);
  static const _critical = Color(0xFFC62828);

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'pending';
  String _typeFilter = 'all';
  String _zoneFilter = 'all';
  String _categoryFilter = 'all';
  List<Map<String, dynamic>> _suggestions = [];
  int _pendingBadgeCount = 0;
  Map<String, dynamic> _stats = const {};
  bool _loading = false;
  bool _analyzing = false;
  DateTime? _lastAnalysisAt;
  String? _error;
  RealtimeChannel? _channel;

  // 5G — pesquisa, bulk select, notas
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final Set<String> _selectedIds = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, Timer> _noteDebounce = {};

  static const _filterOptions = <String, String>{
    'pending': 'Pendentes',
    'implemented': 'Implementadas',
    'approved': 'Aprovadas',
    'rejected': 'Rejeitadas',
    'rolled_back': 'Revertidas',
    'auto_archived': 'Arquivadas',
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
    _searchDebounce?.cancel();
    for (final t in _noteDebounce.values) {
      t.cancel();
    }
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final search = _searchController.text.trim();
      final data = await _supabase.rpc('admin_list_skill_suggestions', params: {
        'p_status': _statusFilter,
        'p_type': _typeFilter,
        'p_zone': _zoneFilter,
        'p_category': _categoryFilter,
        'p_search': search.isEmpty ? null : search,
        'p_limit': 100,
      });
      final list = (data as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      // Garbage-collect note controllers de IDs que já não estão na lista actual.
      final activeIds = list.map((e) => e['id'] as String).toSet();
      _noteControllers.removeWhere((id, c) {
        if (activeIds.contains(id)) return false;
        c.dispose();
        _noteDebounce.remove(id)?.cancel();
        return true;
      });
      _selectedIds.removeWhere((id) => !activeIds.contains(id));
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
      final data = await _supabase.rpc('admin_skill_suggestions_stats');
      if (!mounted) return;
      final stats =
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      setState(() {
        _stats = stats;
        _pendingBadgeCount = (stats['pending'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {/* silent */}
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), _load);
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = 'pending';
      _typeFilter = 'all';
      _zoneFilter = 'all';
      _categoryFilter = 'all';
      _searchController.clear();
    });
    _load();
  }

  void _toggleSelected(String id, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _showBulkApproveDialog() async {
    if (_selectedIds.isEmpty) return;

    // Verify all selected are safe zone
    final allSafe = _selectedIds.every((id) {
      final s = _suggestions.firstWhere(
          (s) => s['id'] == id,
          orElse: () => <String, dynamic>{});
      return (s['zone_type'] as String?) == 'safe';
    });

    if (!allSafe) {
      _toast(
        'Selecção contém propostas CRÍTICAS — só é possível aprovar propostas SAFE em lote.',
        _critical,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aprovar ${_selectedIds.length} propostas SAFE?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Todas as propostas seleccionadas são SAFE e serão aprovadas imediatamente.',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              'Esta acção é irreversível (excepto playbook_update e settings_update que suportam rollback individual).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _boraGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Aprovar ${_selectedIds.length}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ids = _selectedIds.toList();
      final result = await _supabase.rpc(
        'admin_bulk_approve_skill_suggestions',
        params: {'p_ids': ids},
      );
      final data =
          result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
      final approved = (data['approved'] as num?)?.toInt() ?? 0;
      final skipped = (data['skipped_critical'] as num?)?.toInt() ?? 0;
      final errors = (data['errors'] as num?)?.toInt() ?? 0;
      final msg = errors > 0
          ? '$approved aprovada(s), $skipped ignorada(s), $errors erro(s)'
          : skipped > 0
              ? '$approved aprovada(s), $skipped ignorada(s) (não-safe ou não-pendente)'
              : '$approved aprovada(s) com sucesso';
      _toast(msg, errors > 0 ? Colors.orange : _boraGreen);
      if (mounted) setState(() => _selectedIds.clear());
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  Future<void> _showBulkRejectDialog() async {
    if (_selectedIds.isEmpty) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Rejeitar ${_selectedIds.length} propostas?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Razão obrigatória (aplicada a todas):',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                maxLength: 200,
                onChanged: (_) => setSt(() {}),
                decoration: const InputDecoration(
                  labelText: 'Razão',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _boraOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: reasonCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Rejeitar ${_selectedIds.length}'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final ids = _selectedIds.toList();
      final result = await _supabase
          .rpc('admin_bulk_reject_skill_suggestions', params: {
        'p_ids': ids,
        'p_reason': reasonCtrl.text.trim(),
      });
      final count = (result is Map && result['rejected_count'] is num)
          ? (result['rejected_count'] as num).toInt()
          : ids.length;
      _toast('$count propostas rejeitadas', _boraOrange);
      if (mounted) setState(() => _selectedIds.clear());
      await _load();
      await _refreshBadge();
    } catch (e) {
      _toast('Erro: $e', Colors.red);
    }
  }

  void _onNoteChanged(String id, String value) {
    _noteDebounce[id]?.cancel();
    _noteDebounce[id] = Timer(const Duration(seconds: 1), () async {
      try {
        await _supabase.rpc('admin_update_skill_suggestion_note', params: {
          'p_id': id,
          'p_note': value.trim(),
        });
      } catch (_) {/* silent autosave */}
    });
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
      case 'auto_archived':
        return Colors.grey.shade600;
      default:
        return Colors.black45;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'implemented':
        return 'Implementada';
      case 'approved':
        return 'Aprovada';
      case 'rejected':
        return 'Rejeitada';
      case 'rolled_back':
        return 'Revertida';
      case 'auto_archived':
        return 'Arquivada';
      default:
        return status;
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
    final hasSelection = _selectedIds.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: hasSelection ? _boraOrange : _boraGreen,
        foregroundColor: Colors.white,
        leading: hasSelection
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Limpar selecção',
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        title: hasSelection
            ? Text('${_selectedIds.length} seleccionadas')
            : Row(
                children: [
                  const Text('Sugestões IA'),
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
        actions: hasSelection
            ? [
                Builder(builder: (ctx) {
                  final allSafe = _selectedIds.every((id) {
                    final s = _suggestions.firstWhere(
                        (s) => s['id'] == id,
                        orElse: () => <String, dynamic>{});
                    return (s['zone_type'] as String?) == 'safe';
                  });
                  return IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    tooltip: allSafe
                        ? 'Aprovar em lote (todas SAFE)'
                        : 'Aprovar em lote (contém CRÍTICAS — desactivado)',
                    onPressed: allSafe ? _showBulkApproveDialog : null,
                  );
                }),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Rejeitar em lote',
                  onPressed: _showBulkRejectDialog,
                ),
              ]
            : const [],
      ),
      floatingActionButton: hasSelection
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _boraOrange,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pushNamed(
                  context, '/admin/suggestions/metrics'),
              icon: const Icon(Icons.bar_chart),
              label: const Text('Métricas'),
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
        _buildStatsCard(),
        const SizedBox(height: 8),
        _buildFiltersPanel(),
        const SizedBox(height: 12),
        _buildBanner(),
        const SizedBox(height: 12),
        if (_error != null) _buildErrorCard(),
        if (_suggestions.isEmpty && _error == null) _buildEmpty(),
        ..._suggestions.map(_buildCard),
        const SizedBox(height: 80), // espaço para FAB
      ],
    );
  }

  Widget _buildStatsCard() {
    final pending = (_stats['pending'] as num?)?.toInt() ?? 0;
    final implemented = (_stats['implemented'] as num?)?.toInt() ?? 0;
    final rejected = (_stats['rejected'] as num?)?.toInt() ?? 0;
    final archived = (_stats['auto_archived'] as num?)?.toInt() ?? 0;
    final pctApproved = _stats['pct_approved'];
    final oldestDays =
        (_stats['oldest_pending_days'] as num?)?.toInt() ?? 0;
    return Card(
      color: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estatísticas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statBox('Pendentes', pending, _boraOrange),
                _statBox('Implementadas', implemented, _boraGreen),
                _statBox('Rejeitadas', rejected, Colors.red.shade700),
                _statBox('Arquivadas', archived, Colors.grey.shade700),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Taxa de aprovação: ${pctApproved ?? 0}% · '
              'Mais antiga pendente: $oldestDays dias',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildFiltersPanel() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.filter_list),
        title: const Text('Filtros e pesquisa'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _statusFilter,
            decoration: const InputDecoration(
              labelText: 'Estado',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _filterOptions.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _statusFilter = v);
              _load();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _typeFilterOptions.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _typeFilter = v);
              _load();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _zoneFilter,
            decoration: const InputDecoration(
              labelText: 'Zona',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _zoneFilterOptions.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _zoneFilter = v);
              _load();
            },
          ),
          const SizedBox(height: 8),
          // Categoria — texto livre (categoria dinâmica = TODO 5G-β)
          TextField(
            decoration: InputDecoration(
              labelText: 'Categoria (vazio = Todas)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _categoryFilter == 'all'
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() => _categoryFilter = 'all');
                        _load();
                      },
                    ),
            ),
            controller:
                TextEditingController(text: _categoryFilter == 'all' ? '' : _categoryFilter),
            onSubmitted: (v) {
              final t = v.trim();
              setState(() => _categoryFilter = t.isEmpty ? 'all' : t);
              _load();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Buscar no resumo…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Limpar filtros'),
              onPressed: _clearFilters,
            ),
          ),
        ],
      ),
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
    final hasActiveFilter = _typeFilter != 'all' ||
        _zoneFilter != 'all' ||
        _categoryFilter != 'all' ||
        _searchController.text.trim().isNotEmpty;
    final String message;
    if (hasActiveFilter) {
      message = 'Nenhum resultado para os filtros aplicados.';
    } else if (_statusFilter == 'pending') {
      message =
          'Sem propostas no momento.\nCorre análise ou aguarda cron de segunda.';
    } else {
      message = 'Sem registos para o estado seleccionado.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Center(
        child: Text(
          message,
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
    final source = (s['source'] as String?) ?? 'robot_b_batch';
    final isRealtime = source == 'robot_a_realtime';
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

    final id = s['id'] as String;
    final isSelected = _selectedIds.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? const Color(0xFFFFF3E0) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isPending)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (v) => _toggleSelected(id, v),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
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
                      Text(isCritical ? 'CRÍTICA' : 'SEGURA',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCritical ? _critical : _boraGreen)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isRealtime
                            ? const Color(0xFF7E57C2)
                            : Colors.blueGrey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(isRealtime ? '🤖' : '⏰',
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 3),
                      Text(
                        isRealtime ? 'Robot A · tempo real' : 'Robot B · batch',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isRealtime
                              ? const Color(0xFF6A1B9A)
                              : Colors.blueGrey.shade800,
                        ),
                      ),
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
                  child: Text(_statusLabel(status),
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
            _buildAdminNotes(s),
          ],
        ),
      ),
    );
  }

  /// Diff naive linha-a-linha (sem LCS). Linhas presentes em ambos lados
  /// ficam transparentes; só presentes num lado ficam highlighted.
  /// LCS proper / package diff_match_patch: TODO 5G-β.
  Widget _buildSideBySideDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final newSet = newLines.toSet();
    final oldSet = oldLines.toSet();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFFFEBEE),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Antes',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC62828))),
                const SizedBox(height: 4),
                ...oldLines.map((line) => Container(
                      width: double.infinity,
                      color: newSet.contains(line)
                          ? Colors.transparent
                          : const Color(0xFFFFCDD2),
                      child: Text(
                        line.isEmpty ? ' ' : line,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFE8F5E9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Depois',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 4),
                ...newLines.map((line) => Container(
                      width: double.infinity,
                      color: oldSet.contains(line)
                          ? Colors.transparent
                          : const Color(0xFFC8E6C9),
                      child: Text(
                        line.isEmpty ? ' ' : line,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminNotes(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final controller = _noteControllers.putIfAbsent(id, () {
      return TextEditingController(text: (s['admin_notes'] as String?) ?? '');
    });
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        maxLines: 3,
        maxLength: 500,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          labelText: 'Notas internas (só admin vê)',
          helperText: 'Guardado automaticamente',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => _onNoteChanged(id, v),
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
            title: const Text('Diff playbook (lado-a-lado)',
                style: TextStyle(fontSize: 12)),
            children: [
              _buildSideBySideDiff(previous, suggested),
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
