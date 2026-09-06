// Sessão 5F B5 + 5F-α B3 + 5F-β B4 — Admin observador robot_crosstalk
// Lista comunicação Robô A ↔ Robô B + reply UI (5F-β).
// Filtros status + direction + urgency. Realtime badge pending.
// 5F-α: badges urgência 🔴/🟡/🟢, filtro urgency, banner crítico topo.
// 5F-β: botão Responder em pending → admin_respond_to_crosstalk RPC.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminCrosstalkScreen extends StatefulWidget {
  const AdminCrosstalkScreen({super.key});

  @override
  State<AdminCrosstalkScreen> createState() => _AdminCrosstalkScreenState();
}

class _AdminCrosstalkScreenState extends State<AdminCrosstalkScreen> {
  static const _boraGreen = AppColors.primary;
  static const _boraOrange = AppColors.accent;
  static const _amber = Color(0xFFFF8F00);
  static const _critical = Color(0xFFD32F2F); // 5F-α: vermelho críticas
  static const _criticalBg = Color(0xFFFFEBEE);

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'all';
  String _directionFilter = 'all';
  String _urgencyFilter = 'all'; // 5F-α
  List<Map<String, dynamic>> _crosstalks = [];
  int _pendingBadge = 0;
  int _criticalCount = 0; // 5F-α — pending+critical
  bool _loading = false;
  String? _error;
  RealtimeChannel? _channel;

  static const _statusOptions = <String, String>{
    'all': 'Todos',
    'pending': 'Pendentes',
    'answered': 'Respondidas',
    'ignored': 'Ignoradas',
  };

  static const _directionOptions = <String, String>{
    'all': 'Ambas direcções',
    'a_to_b': 'Robô A → Robô B',
    'b_to_a': 'Robô B → Robô A',
  };

  // 5F-α
  static const _urgencyOptions = <String, String>{
    'all': 'Todas urgências',
    'critical': '🔴 Críticas',
    'medium': '🟡 Médias',
    'normal': '🟢 Normais',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _refreshBadge();
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
      final data = await _supabase.rpc('admin_list_crosstalk', params: {
        'p_status': _statusFilter,
        'p_direction': _directionFilter,
        'p_urgency': _urgencyFilter, // 5F-α
        'p_limit': 100,
      });
      final list = (data as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _crosstalks = list;
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
      final data = await _supabase.rpc('admin_list_crosstalk', params: {
        'p_status': 'pending',
        'p_direction': 'a_to_b',
        'p_urgency': 'all', // 5F-α — agregamos para criticalCount localmente
        'p_limit': 200,
      });
      final list = (data as List? ?? []);
      if (!mounted) return;
      // 5F-α: contagem critical computada do mesmo payload
      var critical = 0;
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['urgency'] == 'critical') critical++;
      }
      setState(() {
        _pendingBadge = list.length;
        _criticalCount = critical;
      });
    } catch (_) {/* silent */}
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_crosstalk');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'robot_crosstalk',
      // Filtro server-side: só pending
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'status',
        value: 'pending',
      ),
      callback: (_) {
        _refreshBadge();
        _load();
      },
    ).subscribe();
  }

  void _showRagChunks(Map<String, dynamic> ct) {
    final chunks = ct['rag_chunks_used'] as List? ?? [];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('RAG chunks consultados'),
        content: SizedBox(
          width: double.maxFinite,
          child: chunks.isEmpty
              ? const Text('(Sem chunks RAG registados)',
                  style: TextStyle(fontStyle: FontStyle.italic))
              : SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xFFF5F5F5),
                    child: Text(
                      const JsonEncoder.withIndent('  ').convert(chunks),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showQuestionContext(Map<String, dynamic> ct) {
    final ctx = ct['question_context'] as Map? ?? {};
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Contexto da pergunta'),
        content: SizedBox(
          width: double.maxFinite,
          child: ctx.isEmpty
              ? const Text('(Sem contexto)',
                  style: TextStyle(fontStyle: FontStyle.italic))
              : SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xFFF5F5F5),
                    child: Text(
                      const JsonEncoder.withIndent('  ').convert(ctx),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return _amber;
      case 'answered':
        return _boraGreen;
      case 'ignored':
        return Colors.grey;
      default:
        return Colors.black45;
    }
  }

  ({IconData icon, String label, Color color}) _directionBadge(String dir) {
    switch (dir) {
      case 'a_to_b':
        return (
          icon: Icons.arrow_forward,
          label: '🤖A → 🤖B',
          color: _boraOrange,
        );
      case 'b_to_a':
        return (
          icon: Icons.arrow_back,
          label: '🤖B → 🤖A',
          color: _boraGreen,
        );
      default:
        return (icon: Icons.help_outline, label: dir, color: Colors.grey);
    }
  }

  // 5F-α
  ({String label, Color color}) _urgencyBadgeData(String urg) {
    switch (urg) {
      case 'critical':
        return (label: '🔴 CRÍTICO', color: _critical);
      case 'medium':
        return (label: '🟡 MÉDIO', color: _amber);
      case 'normal':
        return (label: '🟢 NORMAL', color: Colors.grey);
      default:
        return (label: urg.toUpperCase(), color: Colors.black45);
    }
  }

  Widget _buildUrgencyBadge(String urgency) {
    final ub = _urgencyBadgeData(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ub.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        ub.label,
        style: TextStyle(
          color: ub.color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Comunicação A↔B',
        actions: [
          if (_pendingBadge > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_pendingBadge',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Status',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
            itemBuilder: (_) => _statusOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Direcção',
            initialValue: _directionFilter,
            onSelected: (v) {
              setState(() => _directionFilter = v);
              _load();
            },
            itemBuilder: (_) => _directionOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          // 5F-α: filtro urgência
          PopupMenuButton<String>(
            icon: const Icon(Icons.priority_high),
            tooltip: 'Urgência',
            initialValue: _urgencyFilter,
            onSelected: (v) {
              setState(() => _urgencyFilter = v);
              _load();
            },
            itemBuilder: (_) => _urgencyOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _refreshBadge();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _crosstalks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 5F-α: banner crítico empilhado ACIMA do banner observador (Opção 2)
        if (_criticalCount > 0) _buildCriticalBanner(),
        if (_criticalCount > 0) const SizedBox(height: 8),
        _buildBanner(),
        const SizedBox(height: 12),
        if (_error != null) _buildErrorCard(),
        if (_crosstalks.isEmpty && _error == null) _buildEmpty(),
        ..._crosstalks.map(_buildCard),
      ],
    );
  }

  // 5F-α: banner topo CRÍTICAS pendentes (vermelho, condicional)
  Widget _buildCriticalBanner() {
    return Card(
      color: _criticalBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _critical),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ $_criticalCount comunicação(ões) CRÍTICA(S) pendente(s) — '
                'analisar imediatamente.',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _critical,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Card(
      color: AppColors.primaryWash,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: _boraGreen),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply UI activa (5F-β)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Toca em "Responder" nos cards pendentes para responder ao cliente. '
                    'A resposta fica registada com answered_by=admin.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 5F-β — Dialog para responder a uma comunicação pendente
  Future<void> _openReplyDialog(Map<String, dynamic> ct) async {
    final controller = TextEditingController();
    final question = (ct['question'] as String?) ?? '';
    final preview =
        question.length > 200 ? '${question.substring(0, 200)}…' : question;
    final formKey = GlobalKey<FormState>();

    final answer = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) {
        return AlertDialog(
          title: const Text('Responder ao cliente'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      preview,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    minLines: 5,
                    maxLines: 10,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Resposta',
                      hintText: 'Resposta que será guardada no histórico…',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'A resposta não pode ficar vazia';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _boraGreen,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Enviar resposta'),
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dctx, controller.text.trim());
              },
            ),
          ],
        );
      },
    );

    if (answer == null || answer.isEmpty) return;
    if (!mounted) return;

    try {
      await _supabase.rpc('admin_respond_to_crosstalk', params: {
        'p_crosstalk_id': ct['id'],
        'p_answer': answer,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _boraGreen,
          content: Text('✅ Resposta guardada'),
        ),
      );
      await _load();
      await _refreshBadge();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = _mapRpcError(e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _critical,
          content: Text('Erro: $msg'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _critical,
          content: Text('Erro: $e'),
        ),
      );
    }
  }

  String _mapRpcError(String raw) {
    if (raw.contains('NOT_ADMIN')) return 'Sem permissão de admin';
    if (raw.contains('ANSWER_REQUIRED')) return 'Resposta vazia';
    if (raw.contains('CROSSTALK_NOT_FOUND_OR_NOT_PENDING')) {
      return 'Comunicação já não está pendente (foi respondida noutro device?)';
    }
    return raw;
  }

  Widget _buildErrorCard() {
    return Card(
      color: AppColors.error.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Erro ao carregar',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_error ?? '',
                style: const TextStyle(color: AppColors.error)),
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
              ? 'Nenhuma comunicação pendente.'
              : 'Sem comunicações para os filtros activos.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> ct) {
    final status = (ct['status'] as String?) ?? 'pending';
    final direction = (ct['direction'] as String?) ?? 'a_to_b';
    final urgency = (ct['urgency'] as String?) ?? 'normal'; // 5F-α
    final question = ct['question'] as String? ?? '';
    final answer = ct['answer'] as String?;
    final answeredBy = ct['answered_by'] as String?; // 5F-β
    final skill = ct['skill_triggered'] as String?;
    final ragCount = ct['rag_chunks_count'] as int? ?? 0;
    final hasContext =
        (ct['question_context'] as Map?)?.isNotEmpty == true;
    final dirBadge = _directionBadge(direction);
    // 5F-β — só perguntas A→B pendentes podem ser respondidas pelo admin
    final canReply = status == 'pending' && direction == 'a_to_b';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(dirBadge.icon, size: 16, color: dirBadge.color),
                const SizedBox(width: 4),
                Text(dirBadge.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: dirBadge.color)),
                const Spacer(),
                _buildUrgencyBadge(urgency), // 5F-α
                const SizedBox(width: 6),
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
            const Text('Pergunta:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            const SizedBox(height: 4),
            Text(
              question.length > 200
                  ? '${question.substring(0, 200)}…'
                  : question,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (skill != null && skill.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('skill: $skill',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (hasContext)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(Icons.info_outline, size: 14),
                    label: const Text('contexto',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () => _showQuestionContext(ct),
                  ),
                if (ragCount > 0) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    icon: const Icon(Icons.lightbulb_outline, size: 14),
                    label: Text('$ragCount chunks RAG',
                        style: const TextStyle(fontSize: 11)),
                    onPressed: () => _showRagChunks(ct),
                  ),
                ],
                const Spacer(),
                Text(_formatTs(ct['created_at']),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              ],
            ),
            // 5F-β — botão Responder em cards pending A→B
            if (canReply) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: BoraPrimaryButton(
                  label: 'Responder',
                  icon: Icons.reply,
                  expanded: false,
                  onPressed: () => _openReplyDialog(ct),
                ),
              ),
            ],
            if (answer != null && answer.isNotEmpty) ...[
              const Divider(height: 16, color: AppColors.divider),
              Row(
                children: [
                  const Text('Resposta:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                  const Spacer(),
                  // 5F-β — chip distintivo conforme quem respondeu
                  if (answeredBy == 'admin')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _boraGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '✋ Respondido por admin',
                        style: TextStyle(
                          color: _boraGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    )
                  else if (answeredBy == 'b' || answeredBy == 'a')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        answeredBy == 'b'
                            ? '🤖 Respondido por Robô B'
                            : '🤖 Respondido por Robô A',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  answer,
                  style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: AppColors.primary),
                ),
              ),
              if (ct['answered_at'] != null) ...[
                const SizedBox(height: 4),
                Text('Respondida em: ${_formatTs(ct['answered_at'])}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline JsonEncoder import shim para evitar import dart:convert duplicado.
class JsonEncoder {
  final String indent;
  const JsonEncoder.withIndent(this.indent);
  String convert(Object? obj) {
    return _encode(obj, 0);
  }

  String _encode(Object? obj, int depth) {
    final pad = indent * depth;
    final innerPad = indent * (depth + 1);
    if (obj == null) return 'null';
    if (obj is bool || obj is num) return obj.toString();
    if (obj is String) return '"${obj.replaceAll('"', '\\"')}"';
    if (obj is List) {
      if (obj.isEmpty) return '[]';
      final items =
          obj.map((e) => '$innerPad${_encode(e, depth + 1)}').join(',\n');
      return '[\n$items\n$pad]';
    }
    if (obj is Map) {
      if (obj.isEmpty) return '{}';
      final items = obj.entries.map((e) {
        final k = '"${e.key.toString().replaceAll('"', '\\"')}"';
        return '$innerPad$k: ${_encode(e.value, depth + 1)}';
      }).join(',\n');
      return '{\n$items\n$pad}';
    }
    return '"${obj.toString()}"';
  }
}
