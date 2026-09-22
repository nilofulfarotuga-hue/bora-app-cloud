import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../services/order_edit_service.dart';
import '../../utils/hora_lisboa.dart';
import 'admin_order_detail_screen.dart';

/// Painel admin (PT-BR) — edições de pedido feitas pelas lojas parceiras
/// (acrescentar produto / marcar em falta). Lista geral com filtro por loja e
/// por estado, exportar CSV, e as ações: cancelar proposta pendente, aprovar
/// em nome do cliente e forçar o estorno Stripe que ficou pendente.
class AdminOrderEditsScreen extends StatefulWidget {
  const AdminOrderEditsScreen({super.key});

  @override
  State<AdminOrderEditsScreen> createState() => _AdminOrderEditsScreenState();
}

class _AdminOrderEditsScreenState extends State<AdminOrderEditsScreen> {
  List<Map<String, dynamic>> _linhas = const [];
  List<Map<String, dynamic>> _lojas = const [];
  String? _loja;
  String? _estado;
  bool _carregando = true;
  String? _erro;

  static const _estados = {
    null: 'Todos',
    'pendente_cliente': 'À espera do cliente',
    'aceite': 'Aceite (a cobrar)',
    'aplicado': 'Aplicado',
    'recusado': 'Recusado',
    'cancelado': 'Cancelado',
  };

  @override
  void initState() {
    super.initState();
    _carregarLojas();
    _carregar();
  }

  Future<void> _carregarLojas() async {
    try {
      final rows = await Supabase.instance.client
          .from('restaurants')
          .select('id,name')
          .eq('is_partner', true)
          .order('name');
      if (mounted) setState(() => _lojas = (rows as List).cast<Map<String, dynamic>>());
    } catch (_) {/* filtro fica só com "Todas" */}
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await OrderEditService.instance
          .adminListar(restaurantId: _loja, estado: _estado, limite: 1000);
      if (mounted) setState(() => _linhas = l);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro a carregar: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _exportar() async {
    await AdminExportService.instance.exportCsv(
      filename: 'edicoes_pedidos_${DateTime.now().toIso8601String().substring(0, 10)}.csv',
      headers: const [
        'criado_em', 'pedido', 'loja', 'editado_por', 'tipo', 'produto', 'quantidade',
        'preco_unitario', 'subtotal_antes', 'subtotal_depois', 'total_antes',
        'total_depois', 'estado', 'motivo', 'pagamento', 'liquidacao',
      ],
      rows: [
        for (final r in _linhas)
          [
            r['criado_em'], r['order_id'], r['loja'], r['editado_por_email'],
            r['tipo'], r['nome'], r['quantidade'], r['preco_unitario'],
            r['subtotal_antes'], r['subtotal_depois'], r['total_antes'],
            r['total_depois'], r['estado'], r['motivo'], r['payment_method'],
            r['liquidacao'],
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edições de pedidos (parceiros)'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: _linhas.isEmpty ? null : _exportar,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String?>(
                  value: _loja,
                  hint: const Text('Loja'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas as lojas')),
                    for (final l in _lojas)
                      DropdownMenuItem(
                          value: l['id'] as String, child: Text('${l['name']}')),
                  ],
                  onChanged: (v) {
                    setState(() => _loja = v);
                    _carregar();
                  },
                ),
                DropdownButton<String?>(
                  value: _estado,
                  items: [
                    for (final e in _estados.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    setState(() => _estado = v);
                    _carregar();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Center(child: Text(_erro!, style: const TextStyle(color: AppColors.error)))
                    : _linhas.isEmpty
                        ? const Center(child: Text('Nenhuma edição encontrada.'))
                        : RefreshIndicator(
                            onRefresh: _carregar,
                            child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: [
                                for (final g in agruparEdicoesAdmin(_linhas))
                                  AdminOrderEditCard(
                                    linhas: g,
                                    mostrarPedido: true,
                                    onChanged: _carregar,
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Agrupa as linhas de `admin_list_order_edits` por proposta (grupo_id),
/// mantendo a ordem (mais recente primeiro).
List<List<Map<String, dynamic>>> agruparEdicoesAdmin(List<Map<String, dynamic>> rows) {
  final ordem = <String>[];
  final por = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final g = '${r['grupo_id']}';
    if (!por.containsKey(g)) ordem.add(g);
    por.putIfAbsent(g, () => []).add(r);
  }
  return [for (final g in ordem) por[g]!];
}

/// Histórico das edições de UM pedido — separador "Edições" do detalhe do pedido.
class AdminOrderEditsPanel extends StatefulWidget {
  const AdminOrderEditsPanel({super.key, required this.orderId});
  final String orderId;

  @override
  State<AdminOrderEditsPanel> createState() => _AdminOrderEditsPanelState();
}

class _AdminOrderEditsPanelState extends State<AdminOrderEditsPanel> {
  late Future<List<Map<String, dynamic>>> _f = _ler();

  Future<List<Map<String, dynamic>>> _ler() =>
      OrderEditService.instance.adminListar(orderId: widget.orderId);

  void _recarregar() => setState(() => _f = _ler());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Erro a carregar: ${snap.error}'));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const Center(child: Text('A loja não mexeu neste pedido.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final g in agruparEdicoesAdmin(rows))
              AdminOrderEditCard(linhas: g, onChanged: _recarregar),
          ],
        );
      },
    );
  }
}

/// Cartão de UMA proposta (quem, quando, antes/depois, dinheiro, ações).
class AdminOrderEditCard extends StatelessWidget {
  const AdminOrderEditCard({
    super.key,
    required this.linhas,
    required this.onChanged,
    this.mostrarPedido = false,
  });

  final List<Map<String, dynamic>> linhas;
  final VoidCallback onChanged;
  final bool mostrarPedido;

  String _eur(dynamic v) =>
      '€${((v as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';

  String _quando(dynamic iso) => dataHoraLisboa(iso);

  Future<String?> _pedirMotivo(BuildContext context, String titulo) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo (obrigatório)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.length < 3) ? null : r;
  }

  Future<void> _acao(
    BuildContext context,
    String titulo,
    Future<Map<String, dynamic>> Function(String grupo, String motivo) fn,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final motivo = await _pedirMotivo(context, titulo);
    if (motivo == null) return;
    try {
      final r = await fn('${linhas.first['grupo_id']}', motivo);
      messenger.showSnackBar(SnackBar(
          content: Text(r['ok'] == false
              ? 'Não aplicado: ${r['erro'] ?? r}'
              : 'Feito.')));
      onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = linhas.first;
    final estado = '${p['estado']}';
    final liq = (p['liquidacao'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tirar = linhas.every((l) => l['tipo'] == 'remove');
    final svc = OrderEditService.instance;
    final estornoPendente = liq['metodo'] == 'cartao' && liq['estado'] == 'pendente';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tirar ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    color: tirar ? AppColors.info : AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tirar ? 'Em falta' : 'Acrescentar'} · ${p['loja'] ?? p['restaurant_id']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(label: Text(estado), visualDensity: VisualDensity.compact),
              ],
            ),
            if (mostrarPedido)
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminOrderDetailScreen(orderId: '${p['order_id']}'),
                  ),
                ),
                child: Text(
                  'Pedido #${'${p['order_id']}'.substring(0, 8)} · ${p['order_status'] ?? ''} · ${p['payment_method'] ?? ''}',
                  style: const TextStyle(color: AppColors.info, decoration: TextDecoration.underline),
                ),
              ),
            const SizedBox(height: 6),
            for (final l in linhas)
              Text('• ${l['quantidade']}× ${l['nome']} (${_eur(l['preco_unitario'])} cada)'),
            const SizedBox(height: 6),
            Text('Subtotal ${_eur(p['subtotal_antes'])} → ${_eur(p['subtotal_depois'])} · '
                'Total ${_eur(p['total_antes'])} → ${_eur(p['total_depois'])}'),
            Text(
              'Quem: ${p['editado_por_email'] ?? p['editado_por'] ?? '—'} · '
              'criado ${_quando(p['criado_em'])}'
              '${p['respondido_em'] != null ? ' · respondido ${_quando(p['respondido_em'])}' : ''}'
              '${p['aplicado_em'] != null ? ' · aplicado ${_quando(p['aplicado_em'])}' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if ((p['motivo'] ?? '').toString().isNotEmpty)
              Text('Motivo: ${p['motivo']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (liq.isNotEmpty)
              Text('Dinheiro (liquidação): $liq',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (estado == 'pendente_cliente' || estornoPendente)
              Wrap(
                spacing: 8,
                children: [
                  if (estado == 'pendente_cliente') ...[
                    OutlinedButton(
                      onPressed: () => _acao(context, 'Cancelar proposta', svc.adminCancelar),
                      child: const Text('Cancelar proposta'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          _acao(context, 'Aprovar em nome do cliente', svc.adminAprovar),
                      child: const Text('Aprovar pelo cliente'),
                    ),
                  ],
                  if (estornoPendente)
                    FilledButton.icon(
                      icon: const Icon(Icons.replay),
                      onPressed: () =>
                          _acao(context, 'Forçar estorno no cartão', svc.adminForcarEstorno),
                      label: const Text('Forçar estorno'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
