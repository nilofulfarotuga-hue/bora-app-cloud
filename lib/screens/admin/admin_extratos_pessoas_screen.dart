// Contas claras (20/09/2026) — EXTRATOS POR PESSOA (painel admin, PT-BR).
//
// O mesmo extrato que o estafeta/motorista vê (RPC extrato_prestador, com
// p_user_id) e o mesmo que o parceiro vê (RPC extrato_parceiro), abertos pelo
// admin para qualquer pessoa: ver, exportar CSV e auditar. A tela não calcula
// nada — mostra o que o servidor devolve.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/extrato_prestador_section.dart';

class AdminExtratosPessoasScreen extends StatefulWidget {
  const AdminExtratosPessoasScreen({super.key});

  @override
  State<AdminExtratosPessoasScreen> createState() => _AdminExtratosPessoasScreenState();
}

class _AdminExtratosPessoasScreenState extends State<AdminExtratosPessoasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _drivers = const [];
  List<Map<String, dynamic>> _partners = const [];
  bool _loading = true;
  String? _erro;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final sb = Supabase.instance.client;
      final d = await sb
          .from('drivers')
          .select('user_id, name, phone, approval_status')
          .order('name');
      final p = await sb
          .from('restaurants')
          .select('id, name, is_partner')
          .eq('is_partner', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _drivers = List<Map<String, dynamic>>.from(d as List)
            .where((e) => e['user_id'] != null)
            .toList();
        _partners = List<Map<String, dynamic>>.from(p as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Extratos por pessoa'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.delivery_dining), text: 'Estafetas e motoristas'),
            Tab(icon: Icon(Icons.storefront), text: 'Parceiros'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Procurar por nome',
                            border: OutlineInputBorder(),
                            isDense: true),
                        onChanged: (v) => setState(() => _filtro = v.toLowerCase()),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(controller: _tab, children: [
                        _lista(_drivers, (r) => r['name'] as String? ?? '—',
                            (r) => (r['phone'] as String? ?? '') +
                                (r['approval_status'] != 'approved' ? ' · ${r['approval_status']}' : ''),
                            (r) => _AdminExtratoPrestadorPage(
                                userId: r['user_id'] as String, nome: r['name'] as String? ?? '')),
                        _lista(_partners, (r) => r['name'] as String? ?? '—', (r) => r['id'] as String? ?? '',
                            (r) => _AdminExtratoParceiroPage(
                                restaurantId: r['id'] as String, nome: r['name'] as String? ?? '')),
                      ]),
                    ),
                  ],
                ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> rows, String Function(Map) titulo,
      String Function(Map) sub, Widget Function(Map) page) {
    final f = rows.where((r) => _filtro.isEmpty || titulo(r).toLowerCase().contains(_filtro)).toList();
    if (f.isEmpty) return const Center(child: Text('Ninguém.'));
    return ListView.builder(
      itemCount: f.length,
      itemBuilder: (_, i) => ListTile(
        title: Text(titulo(f[i])),
        subtitle: Text(sub(f[i]), style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page(f[i]))),
      ),
    );
  }
}

class _AdminExtratoPrestadorPage extends StatelessWidget {
  const _AdminExtratoPrestadorPage({required this.userId, required this.nome});
  final String userId;
  final String nome;

  Future<void> _csv(BuildContext context) async {
    try {
      final r = await Supabase.instance.client
          .rpc('extrato_prestador', params: {'p_semanas': 12, 'p_user_id': userId});
      final m = Map<String, dynamic>.from(r as Map);
      final b = StringBuffer('quando;tipo;descricao;pagamento;cliente_pagou_eur;ganhou_eur;parte_bora_eur;recebeu_em_mao_eur;fica_para_a_bora_eur\n');
      for (final t in (m['trabalhos'] as List? ?? const [])) {
        final x = t as Map;
        String e(dynamic c) => c == null ? '' : ((c as num) / 100).toStringAsFixed(2).replaceAll('.', ',');
        b.writeln('${x['quando_txt']};${x['tipo']};${x['descricao']};${x['pagamento'] ?? ''};${e(x['cliente_pagou_cents'])};${e(x['ganhou_cents'])};${e(x['parte_bora_cents'])};${e(x['recebeu_em_mao_cents'])};${e(x['fica_para_a_bora_cents'])}');
      }
      await Clipboard.setData(ClipboardData(text: b.toString()));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copiado')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Extrato · $nome'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Exportar CSV', onPressed: () => _csv(context), icon: const Icon(Icons.download_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [ExtratoPrestadorSection(userId: userId, admin: true)],
      ),
    );
  }
}

class _AdminExtratoParceiroPage extends StatefulWidget {
  const _AdminExtratoParceiroPage({required this.restaurantId, required this.nome});
  final String restaurantId;
  final String nome;

  @override
  State<_AdminExtratoParceiroPage> createState() => _AdminExtratoParceiroPageState();
}

class _AdminExtratoParceiroPageState extends State<_AdminExtratoParceiroPage> {
  Map<String, dynamic>? _x;
  String? _erro;
  int _dias = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String eur(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt();
    final abs = n.abs();
    return '${n < 0 ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
  }

  Future<void> _load() async {
    setState(() {
      _x = null;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('extrato_parceiro',
          params: {'p_restaurant_id': widget.restaurantId, 'p_dias': _dias});
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] != true) throw Exception(m['error'] ?? 'sem resposta');
      if (!mounted) return;
      setState(() => _x = m);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString());
    }
  }

  Future<void> _csv() async {
    final x = _x;
    if (x == null) return;
    final b = StringBuffer('quando;cliente;pagamento;cliente_pagou_eur;produtos_eur;entrega_e_taxas_eur;parte_bora_eur;fica_para_o_parceiro_eur\n');
    String e(dynamic c) => c == null ? '' : ((c as num) / 100).toStringAsFixed(2).replaceAll('.', ',');
    for (final p in (x['pedidos'] as List? ?? const [])) {
      final m = p as Map;
      b.writeln('${m['quando_txt']};${m['cliente'] ?? ''};${m['pagamento'] ?? ''};${e(m['cliente_pagou_cents'])};${e(m['produtos_cents'])};${e(m['entrega_e_taxas_cents'])};${e(m['parte_bora_cents'])};${e(m['fica_para_o_parceiro_cents'])}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copiado')));
  }

  Widget _linha(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final x = _x;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Extrato · ${widget.nome}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Exportar CSV', onPressed: x == null ? null : _csv, icon: const Icon(Icons.download_outlined)),
        ],
      ),
      body: _erro != null
          ? Center(child: Text('Erro: $_erro'))
          : x == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final n in const [7, 30, 90])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                            label: Text('$n dias'),
                            selected: _dias == n,
                            onSelected: (_) {
                              setState(() => _dias = n);
                              _load();
                            }),
                      ),
                  ]),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Totais do período', style: TextStyle(fontWeight: FontWeight.w800)),
                        _linha('Pedidos', '${(x['totais'] as Map)['pedidos'] ?? '—'}'),
                        _linha('Clientes pagaram', eur((x['totais'] as Map)['cliente_pagou_cents'])),
                        _linha('Produtos', eur((x['totais'] as Map)['produtos_cents'])),
                        _linha('Entrega e taxas (da Bora)', eur((x['totais'] as Map)['entrega_e_taxas_cents'])),
                        _linha('Parte da Bora sobre os produtos', eur((x['totais'] as Map)['parte_bora_cents'])),
                        _linha('Fica para o parceiro', eur((x['totais'] as Map)['fica_para_o_parceiro_cents']), bold: true),
                        const Divider(height: 18),
                        _linha('Já transferido', '${eur((x['transferido'] as Map)['total_cents'])} (${(x['transferido'] as Map)['semanas']} semanas)'),
                        _linha('Por transferir', '${eur((x['por_transferir'] as Map)['total_cents'])} (${(x['por_transferir'] as Map)['semanas']} semanas)', bold: true),
                        _linha('Stripe Connect', '${(x['stripe'] as Map)['estado'] ?? '—'} · transferências ${(x['stripe'] as Map)['transferencias_activas'] == true ? 'ativas' : 'desligadas'}'),
                        _linha('Arcas batem (ledger = order_financials)', (x['arcas'] as Map)['bate'] == true ? 'sim' : 'NÃO'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(padding: EdgeInsets.only(left: 4, bottom: 4), child: Text('Semanas (acertos)', style: TextStyle(fontWeight: FontWeight.w700))),
                  for (final s in (x['semanas'] as List? ?? const []))
                    Card(
                      child: ListTile(
                        dense: true,
                        title: Text('Semana ${(s as Map)['semana']} · ${s['pedidos']} pedidos · vendas ${eur(s['vendas_cents'])}'),
                        subtitle: Text('Parte da Bora ${eur(s['parte_bora_cents'])} ${s['sobre_txt']} · fica ${eur(s['fica_para_o_parceiro_cents'])} · ${s['estado']}${s['pago_em_txt'] != null ? ' · pago a ${s['pago_em_txt']}' : ''}${s['referencia'] != null ? ' · ref ${s['referencia']}' : ''}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text(eur(s['liquido_cents']), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Padding(padding: EdgeInsets.only(left: 4, bottom: 4), child: Text('Pedidos, um a um', style: TextStyle(fontWeight: FontWeight.w700))),
                  for (final p in (x['pedidos'] as List? ?? const []))
                    Card(
                      child: ListTile(
                        dense: true,
                        title: Text('${(p as Map)['quando_txt']} · ${p['cliente'] ?? 'Cliente'} · ${p['pagamento'] ?? ''}'),
                        subtitle: Text('cliente pagou ${eur(p['cliente_pagou_cents'])} · produtos ${eur(p['produtos_cents'])} · parte da Bora ${eur(p['parte_bora_cents'])} ${p['sobre_txt']} (${p['parte_bora_pct'] ?? '—'} %)',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text(eur(p['fica_para_o_parceiro_cents']), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ),
                    ),
                ]),
    );
  }
}
