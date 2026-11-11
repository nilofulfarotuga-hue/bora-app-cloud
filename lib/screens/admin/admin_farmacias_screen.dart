// Painel admin — Farmácias (missão farmacias-2026-11-11). PT-BR.
// Aba 1 "Farmácias": visibilidade (lista de permissão), modo da receita, comissão extra, abrir ao público.
// Aba 2 "Pedidos de receita": todos os estados, quem respondeu e quando, forçar/cancelar, exportar CSV.
// Nunca mostra fotos nem códigos da receita (dados de saúde): só "tem foto: sim/não".
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_prescricao.dart';
import '../../services/prescricao_service.dart';
import '../../widgets/admin/admin_csv_button.dart';

class AdminFarmaciasScreen extends StatelessWidget {
  const AdminFarmaciasScreen({super.key, this.abaInicial = 0});
  final int abaInicial;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: abaInicial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Farmácias'),
          bottom: const TabBar(tabs: [Tab(text: 'Farmácias'), Tab(text: 'Pedidos de receita')]),
        ),
        body: const TabBarView(children: [_AbaFarmacias(), AdminPedidosReceitaAba()]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── aba Farmácias

class _AbaFarmacias extends StatefulWidget {
  const _AbaFarmacias();
  @override
  State<_AbaFarmacias> createState() => _AbaFarmaciasState();
}

class _AbaFarmaciasState extends State<_AbaFarmacias> {
  final _svc = PrescricaoService();
  late Future<List<Map<String, dynamic>>> _f = _svc.adminFarmacias();

  void _recarregar() => setState(() => _f = _svc.adminFarmacias());

  Future<void> _acao(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  Future<bool> _confirmar(String titulo, String texto) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _mudarModo(Map<String, dynamic> f, String modo) async {
    if (modo == 'publico') {
      if (!await _confirmar('Ligar a receita para TODOS?',
          'Qualquer cliente que veja esta farmácia vai poder enviar receitas. Só ligue depois de a farmácia confirmar com o diretor técnico.')) {
        return;
      }
      if (!await _confirmar('Tem certeza?', 'Confirme outra vez: receita ligada ao público em ${f['name']}.')) return;
    }
    await _acao(() => _svc.adminFarmaciaDefinir(restaurantId: f['id'], modo: modo), 'Modo da receita atualizado.');
  }

  Future<void> _editarLista(Map<String, dynamic> f) async {
    final atual = (f['lista'] as List? ?? const []).map((e) => e.toString()).toList();
    final ctrl = TextEditingController(text: atual.join('\n'));
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lista de permissão'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Um e-mail por linha. Só estas contas (mais o admin e o dono da loja) veem a farmácia enquanto estiver escondida.'),
            const SizedBox(height: 10),
            TextField(controller: ctrl, minLines: 4, maxLines: 10, decoration: const InputDecoration(border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (r == null) return;
    final emails = r.split(RegExp(r'[\s,;]+')).where((e) => e.contains('@')).toList();
    try {
      final naoExistem = await _svc.adminListaPermissaoDefinir(f['id'], emails);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(naoExistem.isEmpty ? 'Lista salva.' : 'Lista salva. Sem conta no app: ${naoExistem.join(', ')}'),
      ));
      _recarregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  Future<void> _editarComissao(Map<String, dynamic> f) async {
    final pct = TextEditingController(text: ((f['partner_extra_commission_pct'] as num?) ?? 0.10).toString());
    final r = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Comissão extra da farmácia'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fração sobre o que a farmácia vende pelo app (0.10 = 10%). Vale só a partir da data de início, '
              'que é definida ao abrir ao público (+ meses sem comissão). Antes disso: zero.'),
          const SizedBox(height: 10),
          TextField(controller: pct, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(pct.text.replaceAll(',', '.'))), child: const Text('Salvar')),
        ],
      ),
    );
    if (r == null) return;
    if (r < 0 || r > 0.5) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor entre 0 e 0.5.')));
      return;
    }
    await _acao(() => _svc.adminFarmaciaDefinir(restaurantId: f['id'], extraPct: r), 'Comissão extra salva.');
  }

  Future<void> _abrir(Map<String, dynamic> f) async {
    if (!await _confirmar('Abrir ${f['name']} ao público?',
        'Todos os clientes passam a ver a farmácia (categoria, pesquisa, faixas). Começa a contar o período sem comissão. '
            'A receita continua no modo escolhido. Os dados fiscais (nome legal, NIF, IBAN, autocertificação) têm de estar completos.')) {
      return;
    }
    await _acao(() => _svc.adminFarmaciaAbrir(f['id']), 'Farmácia aberta ao público.');
  }

  String _data(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text(PrescricaoService.mensagemDe(s.error!)));
        final l = s.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async => _recarregar(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final f in l)
                AdminFarmaciaCartao(
                  farmacia: f,
                  aoMudarModo: (m) => _mudarModo(f, m),
                  aoEditarLista: () => _editarLista(f),
                  aoEditarComissao: () => _editarComissao(f),
                  aoAbrir: () => _abrir(f),
                  formatarData: _data,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Cartão de uma farmácia (testável sem rede).
class AdminFarmaciaCartao extends StatelessWidget {
  const AdminFarmaciaCartao({
    super.key,
    required this.farmacia,
    required this.aoMudarModo,
    required this.aoEditarLista,
    required this.aoEditarComissao,
    required this.aoAbrir,
    required this.formatarData,
  });

  final Map<String, dynamic> farmacia;
  final ValueChanged<String> aoMudarModo;
  final VoidCallback aoEditarLista;
  final VoidCallback aoEditarComissao;
  final VoidCallback aoAbrir;
  final String Function(dynamic) formatarData;

  @override
  Widget build(BuildContext context) {
    final f = farmacia;
    final escondida = f['so_lista_permissao'] == true;
    final lista = (f['lista'] as List? ?? const []).map((e) => e.toString()).toList();
    final pct = (f['partner_extra_commission_pct'] as num?);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${f['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            Chip(
              label: Text(escondida ? 'Escondida (só a lista)' : 'Aberta ao público'),
              backgroundColor: escondida ? const Color(0xFFFFF7ED) : AppColors.primaryWash,
            ),
          ]),
          Text('${f['id']} · dono: ${f['dono_email'] ?? '—'} · ${f['produtos'] ?? 0} produtos '
              '(${f['produtos_provisorios'] ?? 0} com preço provisório da Glovo) · ${f['pedidos_receita'] ?? 0} pedidos de receita'),
          const Divider(height: 24),
          const Text('Receita e botões da farmácia', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'desligado', label: Text('Desligado')),
              ButtonSegment(value: 'so_lista', label: Text('Só a lista')),
              ButtonSegment(value: 'publico', label: Text('Público')),
            ],
            selected: {(f['pharmacy_prescription_mode'] ?? 'desligado').toString()},
            onSelectionChanged: (s) => aoMudarModo(s.first),
          ),
          const SizedBox(height: 4),
          const Text('"Só a lista" = só as contas da lista de permissão, o admin e o dono veem os botões e enviam receitas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Divider(height: 24),
          Row(children: [
            const Expanded(child: Text('Lista de permissão', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: aoEditarLista, icon: const Icon(Icons.edit, size: 18), label: const Text('Editar')),
          ]),
          if (lista.isEmpty) const Text('Ninguém na lista.') else for (final e in lista) Text('• $e'),
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: Text(
                'Comissão extra: ${pct == null ? 'nenhuma' : '${(pct * 100).toStringAsFixed(0)}%'} · '
                'começa em ${formatarData(f['partner_extra_commission_starts_at'])}'
                '${f['partner_extra_commission_starts_at'] == null ? ' (definida ao abrir ao público)' : ''}',
              ),
            ),
            TextButton(onPressed: aoEditarComissao, child: const Text('Editar')),
          ]),
          if (escondida) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: aoAbrir,
                icon: const Icon(Icons.storefront),
                label: const Text('Abrir ao público'),
              ),
            ),
          ] else
            Text('Aberta ao público em ${formatarData(f['aberta_ao_publico_em'])}'),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── aba Pedidos de receita

const kEstadosReceita = <String, String>{
  'enviado': 'À espera da farmácia',
  'aceite': 'Aceito',
  'aceite_parcial': 'Aceito em parte',
  'recusado': 'Recusado',
  'expirado': 'Expirado',
  'cancelado': 'Cancelado',
  'confirmado': 'Confirmado',
  'entregue': 'Entregue',
};

class AdminPedidosReceitaAba extends StatefulWidget {
  const AdminPedidosReceitaAba({super.key});
  @override
  State<AdminPedidosReceitaAba> createState() => _AdminPedidosReceitaAbaState();
}

class _AdminPedidosReceitaAbaState extends State<AdminPedidosReceitaAba> {
  final _svc = PrescricaoService();
  String? _estado;
  late Future<List<Map<String, dynamic>>> _f = _svc.adminListar();

  void _recarregar() => setState(() => _f = _svc.adminListar(estado: _estado));

  String _dt(dynamic v) {
    final d = v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _forcar(Map<String, dynamic> r, {bool cancelar = false}) async {
    String estado = cancelar ? 'cancelado' : (r['estado'] ?? 'enviado').toString();
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cancelar ? 'Cancelar pedido de receita' : 'Forçar estado'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!cancelar)
              DropdownButton<String>(
                value: estado,
                isExpanded: true,
                items: [for (final e in kEstadosReceita.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => estado = v ?? estado),
              ),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (obrigatório)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (motivo.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Motivo obrigatório.')));
      return;
    }
    try {
      await _svc.adminForcar(r['id'].toString(), estado: estado, motivo: motivo.text.trim());
      _recarregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(PrescricaoService.mensagemDe(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, s) {
        final linhas = s.data ?? const <Map<String, dynamic>>[];
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _estado == null,
                onSelected: (_) {
                  _estado = null;
                  _recarregar();
                },
              ),
              for (final e in kEstadosReceita.entries) ...[
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(e.value),
                  selected: _estado == e.key,
                  onSelected: (_) {
                    _estado = e.key;
                    _recarregar();
                  },
                ),
              ],
              const SizedBox(width: 12),
              AdminCsvButton(
                nome: 'pedidos_receita',
                colunas: const [
                  ('created_at', 'Data'),
                  ('loja', 'Loja'),
                  ('cliente_email', 'Cliente'),
                  ('tipo', 'Tipo'),
                  ('estado_txt', 'Estado'),
                  ('respondido_por_email', 'Respondido por'),
                  ('respondido_em', 'Respondido em'),
                  ('valor_txt', 'Valor remédios'),
                  ('taxa_txt', 'Taxa'),
                  ('total_txt', 'Total'),
                  ('metodo_pagamento', 'Método'),
                  ('demo_txt', 'Demonstração'),
                  ('foto_txt', 'Tem foto'),
                ],
                linhas: () => [
                  for (final r in linhas)
                    {
                      ...r,
                      'estado_txt': kEstadosReceita[r['estado']] ?? '${r['estado']}',
                      'valor_txt': eurosDeCents((r['valor_medicamentos_cents'] as num?)?.toInt()),
                      'taxa_txt': eurosDeCents((r['taxa_servico_cents'] as num?)?.toInt()),
                      'total_txt': eurosDeCents((r['total_cents'] as num?)?.toInt()),
                      'demo_txt': r['is_demo'] == true ? 'sim' : 'não',
                      'foto_txt': r['tem_foto'] == true ? 'sim' : 'não',
                    },
                ],
              ),
            ]),
          ),
          Expanded(
            child: s.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : s.hasError
                    ? Center(child: Text(PrescricaoService.mensagemDe(s.error!)))
                    : linhas.isEmpty
                        ? const Center(child: Text('Nenhum pedido de receita.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: linhas.length,
                            itemBuilder: (context, i) {
                              final r = linhas[i];
                              return Card(
                                child: ListTile(
                                  title: Text('${r['loja']} · ${kEstadosReceita[r['estado']] ?? r['estado']}'
                                      '${r['is_demo'] == true ? ' · demonstração' : ''}'),
                                  subtitle: Text([
                                    _dt(r['created_at']),
                                    r['tipo'] == 'receita' ? 'Receita' : 'Pedido especial',
                                    '${r['cliente_email'] ?? ''}',
                                    if (r['respondido_em'] != null) 'respondido ${_dt(r['respondido_em'])} por ${r['respondido_por_email'] ?? '—'}',
                                    if (r['total_cents'] != null) 'total ${eurosDeCents((r['total_cents'] as num).toInt())}',
                                    'foto: ${r['tem_foto'] == true ? 'sim' : 'não'}',
                                  ].join(' · ')),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) => _forcar(r, cancelar: v == 'cancelar'),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'forcar', child: Text('Forçar estado')),
                                      PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ]);
      },
    );
  }
}
