// Sessão 5C-α/7 — Admin Knowledge Base.
// Mostra estatísticas RAG via RPC admin_get_knowledge_stats() (admin-only).
// 5C-β: botão re-indexar ACTIVO via Edge Fn reindex-knowledge.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminKnowledgeScreen extends StatefulWidget {
  const AdminKnowledgeScreen({super.key});

  @override
  State<AdminKnowledgeScreen> createState() => _AdminKnowledgeScreenState();
}

class _AdminKnowledgeScreenState extends State<AdminKnowledgeScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;

  // 5C-β re-index controls
  String _reindexMode = 'pending';
  bool _reindexing = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supabase.rpc('admin_get_knowledge_stats');
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

  Future<void> _reindex() async {
    if (_reindexing) return;

    if (_reindexMode == 'all') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Re-indexar TODOS os chunks?'),
          content: const Text(
            'ATENÇÃO: vai re-embedar todos os 534 chunks. '
            'Pode usar ~36% da quota Gemini do dia. '
            'Confirmas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _reindexing = true);
    try {
      final res = await _supabase.functions.invoke(
        'reindex-knowledge',
        body: {'mode': _reindexMode, 'max_chunks': 100},
      );
      if (!mounted) return;

      final data = res.data;
      String msg;
      if (data is Map) {
        final r = data['reindexed'] ?? 0;
        final e = data['errors'] ?? 0;
        final m = data['message'] ?? '';
        msg = '$r chunks re-indexados, $e erros'
            '${m is String && m.isNotEmpty ? ' · $m' : ''}';
      } else {
        msg = 'Resposta: $data';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
        ),
      );
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro re-index: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _reindexing = false);
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
              Text(
                'Erro a carregar stats:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetch,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    final data = _data;
    final total = (data?['total_chunks'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (total == 0) _emptyHint() else ..._buildStats(data!),
          const SizedBox(height: 24),
          _reindexCta(),
          const SizedBox(height: 16),
          _ingestNote(),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.warning),
                SizedBox(width: 8),
                Text(
                  'Knowledge base vazia',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Corre o ingest local para popular embeddings:\n\n'
              '  cd scripts/rag\n'
              '  deno run --allow-net --allow-read --allow-env \\\n'
              '    --env-file=.env ingest_knowledge.ts',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStats(Map<String, dynamic> data) {
    final total = (data['total_chunks'] as num?)?.toInt() ?? 0;
    final embedded = (data['embedded_chunks'] as num?)?.toInt() ?? 0;
    final pending = (data['pending_chunks'] as num?)?.toInt() ?? 0;
    final lastIndexed = data['last_indexed'];
    final avg = (data['avg_chunk_chars'] as num?)?.toInt() ?? 0;
    final maxC = (data['max_chunk_chars'] as num?)?.toInt() ?? 0;
    final unique = (data['unique_files'] as num?)?.toInt() ?? 0;
    final bySrc = (data['by_source'] is Map)
        ? Map<String, dynamic>.from(data['by_source'] as Map)
        : <String, dynamic>{};

    final pct = total > 0 ? (embedded * 100 / total) : 0.0;

    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: [
          _StatCard(
            icon: Icons.dataset_outlined,
            label: 'Total Chunks',
            value: '$total',
            color: AppColors.primary,
          ),
          _StatCard(
            icon: Icons.check_circle_outline,
            label: 'Indexados',
            value: '$embedded',
            sub: '${pct.toStringAsFixed(0)}%',
            color: AppColors.success,
          ),
          _StatCard(
            icon: Icons.hourglass_bottom,
            label: 'Pendentes',
            value: '$pending',
            sub: 'Aguardam embedding (5C-β)',
            color: pending > 0 ? AppColors.warning : Colors.grey,
          ),
          _StatCard(
            icon: Icons.schedule,
            label: 'Última Indexação',
            value: _fmtDate(lastIndexed),
            valueFontSize: 14,
            color: Colors.deepPurple,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Por Fonte',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (bySrc.isEmpty)
                const Text('—', style: TextStyle(color: Colors.grey))
              else
                ...bySrc.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${e.value} chunks',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Métricas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _metricRow('Tamanho médio', '$avg chars'),
              _metricRow(
                'Maior chunk',
                '$maxC chars',
                warning: maxC > 8000,
              ),
              _metricRow('Arquivos únicos', '$unique'),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _metricRow(String k, String v, {bool warning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              if (warning) ...[
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                v,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: warning ? Colors.orange : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reindexCta() {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Re-indexar embeddings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Modo: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _reindexMode,
                  onChanged: _reindexing
                      ? null
                      : (v) => setState(() => _reindexMode = v ?? 'pending'),
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pendentes (NULL embedding)'),
                    ),
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Todos (re-embed completo)'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _reindexing ? null : _reindex,
                  icon: _reindexing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _reindexing ? 'A re-indexar…' : 'Re-indexar agora',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Limite 100 chunks por chamada · rate-limited 1 req/s',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ingestNote() {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.terminal, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Como indexar novos arquivos',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Corre o script local para indexar novos .md (Obsidian / knowledge / business_rules):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const SelectableText(
                'cd scripts/rag\n'
                'deno run --allow-net --allow-read --allow-env \\\n'
                '  --env-file=.env ingest_knowledge.ts',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.greenAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nota: RAG controlado por feature flag support_settings.rag_enabled. '
              'Kill switch SQL: UPDATE support_settings SET rag_enabled=false WHERE id=1.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.sub,
    this.valueFontSize = 22,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color color;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: valueFontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(
                sub!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
