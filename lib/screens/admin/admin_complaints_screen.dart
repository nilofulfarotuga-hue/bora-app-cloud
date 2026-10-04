// T14 — Admin complaints inbox.
// Ronda 04/10/2026 (admin-geral): corpo completo da queixa, foto (a app do
// cliente/estafeta grava-a numa linha "Foto: <url>" do corpo — a tabela não tem
// coluna de foto), filtro por categoria, abrir o pedido, hora de Lisboa e CSV.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../widgets/private_bucket_image.dart';
import 'admin_order_detail_screen.dart';

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

/// Separa a linha "Foto: <url>" do resto do texto da queixa.
({String texto, String? foto}) separarFotoDaQueixa(String body) {
  String? foto;
  final linhas = <String>[];
  for (final l in body.split('\n')) {
    final t = l.trim();
    final m = RegExp(r'^foto\s*:\s*(\S+)$', caseSensitive: false).firstMatch(t);
    if (m != null && foto == null) {
      foto = m.group(1);
    } else {
      linhas.add(l);
    }
  }
  return (texto: linhas.join('\n').trim(), foto: foto);
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  String? _statusFilter; // null = all
  String? _categoryFilter; // null = all (filtro local)
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  static const _statuses = ['open', 'in_progress', 'resolved', 'dismissed'];
  static const _statusLabels = {
    'open': 'Aberto', 'in_progress': 'Em curso',
    'resolved': 'Resolvido', 'dismissed': 'Descartado',
  };
  static const _statusColors = {
    'open': Colors.orange, 'in_progress': Colors.blue,
    'resolved': Colors.green, 'dismissed': Colors.grey,
  };
  static const _categoryLabels = {
    'order_issue': 'Problema no pedido',
    'payment_issue': 'Pagamento',
    'driver_behavior': 'Entregador',
    'partner_behavior': 'Parceiro',
    'app_bug': 'Erro na app',
    'other': 'Outro',
  };
  static const _roleLabels = {
    'client': 'Cliente', 'driver': 'Entregador', 'partner': 'Parceiro',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_list_complaints', params: {
        'p_status_filter': _statusFilter,
        'p_limit': 300, 'p_offset': 0,
      });
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminComplaints] $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui carregar as reclamações.')));
    }
  }

  List<Map<String, dynamic>> get _visiveis => _categoryFilter == null
      ? _items
      : _items.where((c) => c['category'] == _categoryFilter).toList();

  Future<void> _exportCsv() async {
    final rows = _visiveis.map((c) {
      final q = separarFotoDaQueixa('${c['body'] ?? ''}');
      return [
        dataHoraLisboa(c['created_at']),
        _statusLabels[c['status']] ?? c['status'],
        _categoryLabels[c['category']] ?? c['category'],
        _roleLabels[c['reporter_role']] ?? c['reporter_role'],
        c['reporter_email'] ?? '',
        c['related_order_id'] ?? '',
        c['subject'] ?? '',
        q.texto,
        q.foto ?? '',
        dataHoraLisboa(c['resolved_at']),
      ];
    }).toList();
    await AdminExportService.instance.exportCsv(
      filename: 'reclamacoes_${DateTime.now().millisecondsSinceEpoch}.csv',
      headers: const [
        'criada (Lisboa)', 'estado', 'categoria', 'quem', 'email', 'pedido',
        'assunto', 'texto', 'foto', 'resolvida (Lisboa)',
      ],
      rows: rows,
    );
  }

  Future<void> _abrir(Map<String, dynamic> c) async {
    final notesCtrl = TextEditingController(text: '');
    String newStatus = c['status'] as String;
    final q = separarFotoDaQueixa('${c['body'] ?? ''}');
    final orderId = (c['related_order_id'] as String?)?.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(c['subject'] ?? '—'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_roleLabels[c['reporter_role']] ?? c['reporter_role']} · '
                    '${c['reporter_email'] ?? '—'}\n'
                    '${_categoryLabels[c['category']] ?? c['category']} · '
                    '${dataHoraLisboa(c['created_at'])} (Lisboa)',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(q.texto.isEmpty ? '—' : q.texto),
                  if (q.foto != null) ...[
                    const SizedBox(height: 12),
                    PrivateBucketImage(
                      urlOrPath: q.foto!,
                      height: 240,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ],
                  if (orderId != null && orderId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('Abrir pedido ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}'),
                      onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                          builder: (_) => AdminOrderDetailScreen(orderId: orderId))),
                    ),
                  ],
                  const Divider(),
                  DropdownButton<String>(
                    value: newStatus,
                    isExpanded: true,
                    items: _statuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(_statusLabels[s]!)))
                        .toList(),
                    onChanged: (v) => setSt(() => newStatus = v ?? newStatus),
                  ),
                  TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notas admin (opcional)')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fechar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar estado')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('admin_update_complaint_status', params: {
        'p_complaint_id': c['id'],
        'p_new_status': newStatus,
        'p_admin_notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
      });
      _load();
    } catch (e) {
      debugPrint('[AdminComplaints] update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não consegui gravar o estado.')));
      }
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  @override
  Widget build(BuildContext context) {
    final itens = _visiveis;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Reclamações',
        actions: [
          IconButton(
              tooltip: 'Descarregar CSV',
              icon: const Icon(Icons.download),
              onPressed: itens.isEmpty ? null : _exportCsv),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            _chip('Todos', _statusFilter == null, () {
              setState(() => _statusFilter = null);
              _load();
            }),
            ..._statuses.map((s) => _chip(_statusLabels[s]!, _statusFilter == s, () {
                  setState(() => _statusFilter = s);
                  _load();
                })),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            _chip('Todas as categorias', _categoryFilter == null,
                () => setState(() => _categoryFilter = null)),
            ..._categoryLabels.entries.map((e) => _chip(e.value, _categoryFilter == e.key,
                () => setState(() => _categoryFilter = e.key))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: itens.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Sem reclamações.')),
                        ])
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: itens.length,
                          itemBuilder: (ctx, i) {
                            final c = itens[i];
                            final status = c['status'] as String;
                            final q = separarFotoDaQueixa('${c['body'] ?? ''}');
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(Radii.lg),
                                boxShadow: AppColors.shadowCard,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _statusColors[status],
                                  child: Icon(
                                      q.foto != null ? Icons.photo_camera : Icons.report_problem,
                                      color: Colors.white,
                                      size: 20),
                                ),
                                title: Text(c['subject'] ?? '—'),
                                subtitle: Text(
                                  '${_roleLabels[c['reporter_role']] ?? c['reporter_role']} · '
                                  '${_categoryLabels[c['category']] ?? c['category']} · '
                                  '${dataHoraLisboa(c['created_at'])}\n${q.texto}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                isThreeLine: true,
                                trailing: Chip(
                                  label: Text(_statusLabels[status] ?? status,
                                      style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  backgroundColor: _statusColors[status],
                                ),
                                onTap: () => _abrir(c),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }
}
