// Painel (PT-BR) — rascunho da compra do entregador (14/11/2026).
//
// O que o entregador já marcou na lista de compras de um pedido em curso
// (comprado, não tem, produto acrescentado/trocado, sacolas, valor e foto do
// cupom fiscal) e a hora da última marcação. Serve para fechar o pedido pelo
// painel/MCP se o app falhar, sem refazer a compra. Lê
// `admin_rascunho_compra` (só admin). Não mexe em dinheiro.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/euros.dart';

class AdminRascunhoCompraSection extends StatefulWidget {
  const AdminRascunhoCompraSection({
    super.key,
    required this.orderId,
    this.esconderSemRascunho = true,
  });

  final String orderId;

  /// No detalhe do pedido não desenha nada quando não há rascunho.
  final bool esconderSemRascunho;

  @override
  State<AdminRascunhoCompraSection> createState() =>
      _AdminRascunhoCompraSectionState();
}

class _AdminRascunhoCompraSectionState
    extends State<AdminRascunhoCompraSection> {
  Map<String, dynamic>? _dados;
  String? _erro;
  bool _aCarregar = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_rascunho_compra', params: {'p_order_id': widget.orderId});
      if (!mounted) return;
      setState(() {
        _dados = res is Map ? Map<String, dynamic>.from(res) : null;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      final texto = e.toString();
      setState(() {
        _aCarregar = false;
        _erro = texto.contains('PGRST202') || texto.contains('does not exist')
            ? 'A função admin_rascunho_compra ainda não foi publicada no servidor '
                '(migração 20261114190000).'
            : texto;
      });
    }
  }

  static String _hora(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dois(int n) => n.toString().padLeft(2, '0');
    final ha = DateTime.now().difference(d);
    final rel = ha.inMinutes < 1
        ? 'agora'
        : ha.inMinutes < 60
            ? 'há ${ha.inMinutes} min'
            : 'há ${ha.inHours} h';
    return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)} ($rel)';
  }

  static (String, Color) _estado(String? s) => switch (s) {
        'bought' => ('Comprado', Colors.green.shade700),
        'unavailable' => ('Não tem', Colors.red.shade700),
        _ => ('Falta marcar', Colors.grey.shade600),
      };

  @override
  Widget build(BuildContext context) {
    if (_aCarregar) {
      return widget.esconderSemRascunho
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()));
    }
    if (_erro != null) {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Rascunho da compra: $_erro'),
        ),
      );
    }
    final d = _dados;
    final tem = d?['tem_rascunho'] == true;
    if (d == null || (!tem && widget.esconderSemRascunho)) {
      return const SizedBox.shrink();
    }
    final itens = (d['itens'] as List?) ?? const [];
    final extras = (d['extras'] as List?) ?? const [];
    final pedido = (d['pedido'] as Map?) ?? const {};
    final total = d['total_talao_cents'];
    final foto = d['foto_talao'] as String?;
    final marcados = itens.where((i) => (i as Map)['estado'] != 'pending').length;

    return Card(
      key: const Key('admin_rascunho_compra'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Rascunho da compra (o que o entregador marcou)',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (!tem)
              const Text('O entregador ainda não marcou nada neste pedido.')
            else ...[
              Text(
                '$marcados de ${itens.length} itens marcados · última marcação: '
                '${_hora(d['ultima_marcacao'])}',
                style: TextStyle(color: Colors.grey.shade800),
              ),
              if (pedido['compra_fechada'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('A compra já foi fechada (cupom registrado).',
                      style: TextStyle(color: Colors.green.shade800)),
                ),
              const Divider(),
              for (final raw in itens)
                Builder(builder: (_) {
                  final i = Map<String, dynamic>.from(raw as Map);
                  final (rotulo, cor) = _estado(i['estado'] as String?);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text('${i['quantidade']} × ${i['nome']}')),
                        Text(rotulo,
                            style: TextStyle(
                                color: cor, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }),
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Acrescentados pelo entregador (troca ou extra):',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                for (final raw in extras)
                  Builder(builder: (_) {
                    final x = Map<String, dynamic>.from(raw as Map);
                    final preco = (x['preco_cents'] as num? ?? 0) / 100.0;
                    final (rotulo, cor) = _estado(x['s'] as String? ?? 'bought');
                    return Row(
                      children: [
                        Expanded(
                            child: Text(
                                '${x['qtd']} × ${x['nome']} — ${eur(preco)} (preço da prateleira)')),
                        Text(rotulo, style: TextStyle(color: cor)),
                      ],
                    );
                  }),
              ],
              const SizedBox(height: 8),
              Text('Sacolas: ${d['sacos'] ?? '—'}'),
              Text('Valor do cupom fiscal escrito: '
                  '${total is num ? eur(total / 100.0) : '—'}'),
              Text('Foto do cupom no servidor: ${foto ?? 'ainda não'}'),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Como fechar sem refazer a compra'),
                children: [
                  const Text(
                    'O fechamento continua sendo a mesma função de sempre '
                    '(finalizar_talao_nao_parceiro — a conta do dinheiro não '
                    'muda). Os itens abaixo já estão no formato que ela recebe '
                    '(p_items). Pelo MCP: simular o JWT do entregador e chamar a '
                    'função com a foto, o valor do cupom, estes itens e as '
                    'sacolas.',
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: '${d['itens_para_fecho']}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Itens copiados (p_items).')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar itens (p_items)'),
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
