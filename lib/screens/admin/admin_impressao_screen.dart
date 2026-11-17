// Painel admin (PT-BR) — Impressão e personalizados + Robô do catálogo da A3
// (missão a3-guarda-16-11, parte 2; Bloco 2.6 e 1.5 da caixa 111).
// Abas: Pedidos (todos, com arquivos) · Lojas (ligar/desligar o serviço) · Preços (tabela por loja)
// · Robô A3 (estado das corridas, ligar/desligar e "Atualizar agora").
// O fator de preço ao cliente NÃO se edita aqui (é dinheiro: só por migração).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../models/pedido_impressao.dart';
import '../../services/impressao_service.dart';
import '../partner/impressao/parceiro_impressoes_screen.dart' show ParceiroImpressaoPrecos;

String _dataHora(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class AdminImpressaoScreen extends StatelessWidget {
  const AdminImpressaoScreen({super.key, this.abaInicial = 0});
  final int abaInicial;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: abaInicial,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Impressão e personalizados'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Pedidos'),
            Tab(text: 'Lojas'),
            Tab(text: 'Preços'),
            Tab(text: 'Robô A3'),
          ]),
        ),
        body: const TabBarView(children: [_AbaPedidos(), _AbaLojas(), _AbaPrecos(), AdminRoboA3Aba()]),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── pedidos

class _AbaPedidos extends StatefulWidget {
  const _AbaPedidos();
  @override
  State<_AbaPedidos> createState() => _AbaPedidosState();
}

class _AbaPedidosState extends State<_AbaPedidos> {
  final _svc = ImpressaoService();
  String? _estado;
  late Future<List<PedidoImpressao>> _f = _svc.adminListar();

  void _recarregar() => setState(() => _f = _svc.adminListar(estado: _estado));

  Future<void> _abrir(String path) async {
    final url = await _svc.urlAssinado(path);
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          const Text('Status: '),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            value: _estado,
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos')),
              DropdownMenuItem(value: 'enviado', child: Text('Enviado (aguardando a loja)')),
              DropdownMenuItem(value: 'orcamentado', child: Text('Orçamento enviado')),
              DropdownMenuItem(value: 'aceite', child: Text('Aceito / em preparo')),
              DropdownMenuItem(value: 'pronto', child: Text('Pronto')),
              DropdownMenuItem(value: 'entregue', child: Text('Entregue')),
              DropdownMenuItem(value: 'recusado', child: Text('Recusado')),
              DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
            ],
            onChanged: (v) {
              _estado = v;
              _recarregar();
            },
          ),
          const Spacer(),
          IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<PedidoImpressao>>(
          future: _f,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Erro: ${ImpressaoService.mensagemDe(snap.error!)}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final l = snap.data!;
            if (l.isEmpty) return const Center(child: Text('Nenhum pedido.'));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: l.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = l[i];
                return Card(
                  child: ExpansionTile(
                    leading: Icon(p.personalizado ? Icons.card_giftcard : Icons.print, color: AppColors.primary),
                    title: Text('${p.restaurantId} · ${impressaoEstadoTexto(p.estado, personalizado: p.personalizado)}'),
                    subtitle: Text('${_dataHora(p.createdAt)} · ${p.resumo}${p.isDemo ? ' · TESTE (não cobrado)' : ''}'),
                    trailing: Text(euros(p.totalCents ?? p.artigoCents), style: const TextStyle(fontWeight: FontWeight.w800)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Pedido ${p.id}'),
                          Text('Cliente (user_id): ${p.userId}'),
                          Text('Retirada: ${p.entrega ? 'entrega Bora — ${p.morada ?? ''}' : 'na loja, código ${p.codigoLevantamento ?? '-'}'}'),
                          Text('Pagamento: ${p.metodoPagamento ?? '-'} · artigo ${euros(p.artigoCents)} · taxa serviço ${euros(p.taxaServicoCents)} · entrega ${euros(p.taxaEntregaCents)}'),
                          if (p.precoProvisorio) const Text('Calculado com a tabela PROVISÓRIA.'),
                          if (p.motivoRecusa != null) Text('Motivo da recusa: ${p.motivoRecusa}'),
                          for (final f in p.ficheiros)
                            TextButton.icon(onPressed: () => _abrir(f.path), icon: const Icon(Icons.download), label: Text('${f.nome} (${f.paginas} pág.)')),
                          if (p.fotoPath != null)
                            TextButton.icon(onPressed: () => _abrir(p.fotoPath!), icon: const Icon(Icons.image), label: const Text('Foto do cliente')),
                          if (p.ficheiros.isEmpty && !p.personalizado) const Text('Arquivos já apagados (30 dias, LGPD/RGPD).'),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────────────── lojas

class _AbaLojas extends StatefulWidget {
  const _AbaLojas();
  @override
  State<_AbaLojas> createState() => _AbaLojasState();
}

class _AbaLojasState extends State<_AbaLojas> {
  final _svc = ImpressaoService();
  late Future<List<Map<String, dynamic>>> _f = _svc.adminLojas();
  final _novaLoja = TextEditingController();

  @override
  void dispose() {
    _novaLoja.dispose();
    super.dispose();
  }

  Future<void> _definir(String id, {required bool ligado, bool? personalizados}) async {
    try {
      await _svc.adminLojaDefinir(id, ligado: ligado, personalizados: personalizados);
      setState(() => _f = _svc.adminLojas());
    } on ImpressaoErro catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensagem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final l = snap.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('O serviço é ligado loja a loja. Numa loja escondida os pedidos são de TESTE (nada é cobrado). '
              'Numa loja aberta ao público os pedidos pela app ficam bloqueados até a cobrança real ser ligada.'),
          const SizedBox(height: 12),
          for (final r in l)
            Card(
              child: Column(children: [
                SwitchListTile(
                  title: Text('${(r['restaurants'] as Map?)?['name'] ?? r['restaurant_id']} — Imprimir documentos'),
                  subtitle: Text('Fator de preço ao cliente: ${r['fator_cliente']} (não editável aqui)'),
                  value: r['ligado'] == true,
                  onChanged: (v) => _definir(r['restaurant_id'] as String, ligado: v),
                ),
                SwitchListTile(
                  title: const Text('Personalizados'),
                  value: r['personalizados_ligado'] == true,
                  onChanged: (v) => _definir(r['restaurant_id'] as String, ligado: r['ligado'] == true, personalizados: v),
                ),
              ]),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _novaLoja,
                decoration: const InputDecoration(labelText: 'Ligar em outra loja (id, ex.: a3-guarda)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final id = _novaLoja.text.trim();
                if (id.isNotEmpty) _definir(id, ligado: true);
              },
              child: const Text('Ligar'),
            ),
          ]),
        ]);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────── preços

class _AbaPrecos extends StatefulWidget {
  const _AbaPrecos();
  @override
  State<_AbaPrecos> createState() => _AbaPrecosState();
}

class _AbaPrecosState extends State<_AbaPrecos> {
  late final Future<List<Map<String, dynamic>>> _f = ImpressaoService().adminLojas();
  String? _loja;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final l = snap.data!;
        if (l.isEmpty) return const Center(child: Text('Nenhuma loja com o serviço.'));
        _loja ??= l.first['restaurant_id'] as String;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButton<String>(
              value: _loja,
              isExpanded: true,
              items: [
                for (final r in l)
                  DropdownMenuItem(
                    value: r['restaurant_id'] as String,
                    child: Text('${(r['restaurants'] as Map?)?['name'] ?? r['restaurant_id']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _loja = v),
            ),
          ),
          Expanded(
            child: ParceiroImpressaoPrecos(
              key: ValueKey(_loja),
              restaurantId: _loja!,
              titulo: 'Tabela de preços (balcão) da loja',
            ),
          ),
        ]);
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────── robô A3

class AdminRoboA3Aba extends StatefulWidget {
  const AdminRoboA3Aba({super.key});
  @override
  State<AdminRoboA3Aba> createState() => _AdminRoboA3AbaState();
}

class _AdminRoboA3AbaState extends State<AdminRoboA3Aba> {
  final _sb = Supabase.instance.client;
  late Future<Map<String, dynamic>> _f = _ler();
  bool _ocupado = false;

  Future<Map<String, dynamic>> _ler() async {
    final r = await _sb.rpc('admin_robo_a3_estado', params: {'p_limite': 20});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> _fazer(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
      setState(() => _f = _ler());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ImpressaoService.mensagemDe(e))));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Erro: ${ImpressaoService.mensagemDe(snap.error!)}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final corridas = (d['corridas'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Robô do catálogo da A3 Guarda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Todo dia às 07:00 (Lisboa) lê a loja online da A3 (a3guarda.com/loja) e atualiza preço e esgotado. '
              'Nunca sobrescreve preço, esgotado, foto ou nome alterados à mão. Produto novo só entra com foto copiada para o nosso Storage.'),
          const SizedBox(height: 12),
          Text('Produtos: ${d['produtos']} · fotos ainda no site da A3: ${d['fotos_fora']} · ignorados: ${d['ignorados']}'),
          Text('Fator de preço (balcão × ${d['fator_preco']}) — não editável aqui.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Robô ligado'),
            value: d['ligado'] == true,
            onChanged: _ocupado ? null : (v) => _fazer(() async => _sb.rpc('admin_robo_a3_ligar', params: {'p_ligado': v})),
          ),
          FilledButton.icon(
            onPressed: _ocupado || d['ligado'] != true ? null : () => _fazer(() async => _sb.rpc('admin_robo_a3_agora')),
            icon: const Icon(Icons.sync),
            label: const Text('Atualizar agora'),
          ),
          const SizedBox(height: 16),
          const Text('Últimas execuções', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final c in corridas)
            Card(
              child: ListTile(
                title: Text('#${c['id']} · ${c['estado']} · ${c['origem']}'),
                subtitle: Text(
                  'Início ${c['iniciada_em'] != null ? _dataHora(DateTime.parse(c['iniciada_em'] as String).toLocal()) : '-'} · '
                  'lidos ${c['lidos'] ?? '-'} · preço mudou ${c['mudou_preco'] ?? 0} · esgotou ${c['esgotou'] ?? 0} · '
                  'voltou ${c['voltou'] ?? 0} · sumiu ${c['desapareceu'] ?? 0} · novos ${c['novos'] ?? 0} · '
                  'mão humana ${c['mao'] ?? 0} · suspeitos ${c['suspeitos'] ?? 0} · fotos ${c['fotos_copiadas'] ?? 0}'
                  '${c['erro'] != null ? '\nErro: ${c['erro']}' : ''}',
                ),
              ),
            ),
          if (corridas.isEmpty) const Text('Ainda não houve execuções.'),
        ]);
      },
    );
  }
}
