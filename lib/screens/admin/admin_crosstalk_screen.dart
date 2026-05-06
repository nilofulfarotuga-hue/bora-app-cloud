// Sessão 5F B5 — Admin observador robot_crosstalk
// Lista comunicação Robô A ↔ Robô B (read-only em 5F).
// Filtros status + direction. Realtime badge pending.
// TODO 5F-β: admin_respond_to_crosstalk + UI reply.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCrosstalkScreen extends StatefulWidget {
  const AdminCrosstalkScreen({super.key});

  @override
  State<AdminCrosstalkScreen> createState() => _AdminCrosstalkScreenState();
}

class _AdminCrosstalkScreenState extends State<AdminCrosstalkScreen> {
  static const _boraGreen = Color(0xFF1B5E20);
  static const _boraOrange = Color(0xFFE65100);
  static const _amber = Color(0xFFFF8F00);

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'all';
  String _directionFilter = 'all';
  List<Map<String, dynamic>> _crosstalks = [];
  int _pendingBadge = 0;
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
        'p_limit': 200,
      });
      final list = (data as List? ?? []);
      if (!mounted) return;
      setState(() => _pendingBadge = list.length);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _boraGreen,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('Comunicação A↔B'),
            if (_pendingBadge > 0) ...[
              const SizedBox(width: 8),
              Container(
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
        _buildBanner(),
        const SizedBox(height: 12),
        if (_error != null) _buildErrorCard(),
        if (_crosstalks.isEmpty && _error == null) _buildEmpty(),
        ..._crosstalks.map(_buildCard),
      ],
    );
  }

  Widget _buildBanner() {
    return const Card(
      color: Color(0xFFE8F5E9),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: _boraGreen),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modo observador (5F)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Resposta às perguntas pendentes via scripts/crosstalk/respond.ts. '
                    'Reply UI será adicionada em 5F-β.',
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
    final question = ct['question'] as String? ?? '';
    final answer = ct['answer'] as String?;
    final skill = ct['skill_triggered'] as String?;
    final ragCount = ct['rag_chunks_count'] as int? ?? 0;
    final hasContext =
        (ct['question_context'] as Map?)?.isNotEmpty == true;
    final dirBadge = _directionBadge(direction);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
            if (answer != null && answer.isNotEmpty) ...[
              const Divider(height: 16),
              const Text('Resposta:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  answer,
                  style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: Color(0xFF1B5E20)),
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
