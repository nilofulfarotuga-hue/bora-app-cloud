// Painel admin (PT-BR) — "Pesquisas sem resultado" (09/11/2026, missão m11,
// adendo 2, parte A). O que os clientes procuraram e não acharam, por loja,
// com os produtos que eles acabaram por pôr no carrinho; botão para criar um
// sinônimo (fica na auditoria) e a lista de sinônimos para ligar/desligar.
//
// RPCs (migração 20261109070000_pesquisa_inteligente.sql):
//   admin_pesquisas_sem_resultado(p_dias) · admin_pesquisa_sinonimos(p_busca)
//   admin_pesquisa_criar_sinonimo(p_termo, p_alvo, p_restaurant_id, p_product_id)
//   admin_pesquisa_sinonimo_ativo(p_id, p_ativo)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

typedef CarregarPesquisas = Future<Map<String, dynamic>> Function(int dias);
typedef ListarSinonimos = Future<List<Map<String, dynamic>>> Function(String? busca);
typedef CriarSinonimo = Future<Map<String, dynamic>> Function({
  required String termo,
  String? alvo,
  String? restaurantId,
  String? productId,
});
typedef AtivarSinonimo = Future<Map<String, dynamic>> Function(int id, bool ativo);

class AdminPesquisasSemResultadoScreen extends StatefulWidget {
  const AdminPesquisasSemResultadoScreen({
    super.key,
    this.carregar,
    this.listar,
    this.criar,
    this.ativar,
  });

  final CarregarPesquisas? carregar;
  final ListarSinonimos? listar;
  final CriarSinonimo? criar;
  final AtivarSinonimo? ativar;

  @override
  State<AdminPesquisasSemResultadoScreen> createState() =>
      _AdminPesquisasSemResultadoScreenState();
}

Map<String, dynamic> _mapa(dynamic r) =>
    r is Map ? r.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};

List<Map<String, dynamic>> _lista(dynamic r) =>
    r is List ? r.map(_mapa).toList() : const <Map<String, dynamic>>[];

Future<Map<String, dynamic>> _carregarSupabase(int dias) async =>
    _mapa(await Supabase.instance.client
        .rpc('admin_pesquisas_sem_resultado', params: {'p_dias': dias}));

Future<List<Map<String, dynamic>>> _listarSupabase(String? busca) async =>
    _lista(await Supabase.instance.client
        .rpc('admin_pesquisa_sinonimos', params: {'p_busca': busca}));

Future<Map<String, dynamic>> _criarSupabase({
  required String termo,
  String? alvo,
  String? restaurantId,
  String? productId,
}) async =>
    _mapa(await Supabase.instance.client.rpc('admin_pesquisa_criar_sinonimo', params: {
      'p_termo': termo,
      'p_alvo': alvo,
      'p_restaurant_id': restaurantId,
      'p_product_id': productId,
    }));

Future<Map<String, dynamic>> _ativarSupabase(int id, bool ativo) async =>
    _mapa(await Supabase.instance.client
        .rpc('admin_pesquisa_sinonimo_ativo', params: {'p_id': id, 'p_ativo': ativo}));

class _AdminPesquisasSemResultadoScreenState
    extends State<AdminPesquisasSemResultadoScreen> {
  int _dias = 30;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _dados = const {};
  List<Map<String, dynamic>> _sinonimos = const [];
  String _busca = '';

  CarregarPesquisas get _carregar => widget.carregar ?? _carregarSupabase;
  ListarSinonimos get _listar => widget.listar ?? _listarSupabase;
  CriarSinonimo get _criar => widget.criar ?? _criarSupabase;
  AtivarSinonimo get _ativar => widget.ativar ?? _ativarSupabase;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final d = await _carregar(_dias);
      final s = await _listar(_busca.isEmpty ? null : _busca);
      if (!mounted) return;
      setState(() {
        _dados = d;
        _sinonimos = s;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirCriar({
    required String termo,
    String? restaurantId,
    String? loja,
    List<Map<String, dynamic>> sugestoes = const [],
  }) async {
    final criado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoSinonimo(
        termo: termo,
        restaurantId: restaurantId,
        loja: loja,
        sugestoes: sugestoes,
        criar: _criar,
      ),
    );
    if (criado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sinônimo criado. A pesquisa já usa.')),
      );
      _recarregar();
    }
  }

  Future<void> _mudarAtivo(Map<String, dynamic> s, bool ativo) async {
    final id = (s['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final r = await _ativar(id, ativo);
      if (!mounted) return;
      if (r['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não deu: ${r['erro'] ?? 'erro desconhecido'}')),
        );
      }
      _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final termos = _lista(_dados['termos']);
    final aprendidos = _lista(_dados['aprendidos']);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pesquisas sem resultado',
        actions: [
          IconButton(
            tooltip: 'Criar sinônimo',
            icon: const Icon(Icons.add),
            onPressed: () => _abrirCriar(termo: ''),
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _recarregar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'O que os clientes procuraram dentro das lojas e na lupa da home e não acharam nenhum produto. '
              'Crie um sinônimo para a pesquisa passar a achar (ex.: "gelado" → "McFlurry"). '
              'Quando 3 clientes diferentes escolhem o mesmo produto depois de uma pesquisa sem resultado, '
              'o sinônimo entra sozinho.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 dias')),
                ButtonSegment(value: 30, label: Text('30 dias')),
                ButtonSegment(value: 90, label: Text('90 dias')),
              ],
              selected: {_dias},
              onSelectionChanged: (s) {
                setState(() => _dias = s.first);
                _recarregar();
              },
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Text('Erro ao carregar: $_erro',
                  style: const TextStyle(color: AppColors.error))
            else ...[
              Text(
                '${_dados['total'] ?? 0} pesquisas sem resultado · '
                '${_dados['termos_distintos'] ?? 0} termos diferentes',
                key: const Key('pesquisas-resumo'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (termos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Nenhuma pesquisa sem resultado neste período.'),
                ),
              for (final t in termos) _linhaTermo(t),
              const SizedBox(height: 24),
              const Text('Aprendidos sozinhos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (aprendidos.isEmpty)
                const Text('Ainda nenhum.',
                    style: TextStyle(color: AppColors.textSecondary)),
              for (final a in aprendidos)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                  title: Text('"${a['termo']}" → ${a['produto'] ?? '?'}'),
                  subtitle: Text('${a['loja'] ?? ''} · ${a['vezes'] ?? 0} clientes'),
                ),
              const SizedBox(height: 24),
              const Text('Sinônimos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar sinônimo (ex.: gelado)',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  _busca = v.trim();
                  _recarregar();
                },
              ),
              for (final s in _sinonimos)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: s['ativo'] == true,
                  onChanged: (v) => _mudarAtivo(s, v),
                  title: Text('${s['termo']} → ${s['alvo'] ?? s['produto'] ?? '?'}'),
                  subtitle: Text([
                    s['loja'] ?? 'todas as lojas',
                    switch (s['origem']) {
                      'aprendido' => 'aprendido',
                      'admin' => 'criado no painel',
                      _ => 'de fábrica',
                    },
                  ].join(' · ')),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linhaTermo(Map<String, dynamic> t) {
    final sugestoes = _lista(t['sugestoes']);
    final temSinonimo = t['tem_sinonimo'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '"${t['termo']}"',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                if (temSinonimo)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text('já tem sinônimo'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                TextButton.icon(
                  key: Key('criar-sinonimo-${t['chave']}-${t['restaurant_id']}'),
                  onPressed: () => _abrirCriar(
                    termo: '${t['termo'] ?? ''}',
                    restaurantId: t['restaurant_id'] as String?,
                    loja: t['loja'] as String?,
                    sugestoes: sugestoes,
                  ),
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Criar sinônimo'),
                ),
              ],
            ),
            Text(
              '${t['loja'] ?? 'Lupa da home'} · ${t['vezes'] ?? 0} vezes · '
              '${t['pessoas'] ?? 0} clientes · resolvidas ${t['resolvidas'] ?? 0}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (sugestoes.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Depois, puseram no carrinho:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in sugestoes)
                    Chip(
                      label: Text('${s['nome']} (${s['vezes']})'),
                      visualDensity: VisualDensity.compact,
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

class _DialogoSinonimo extends StatefulWidget {
  const _DialogoSinonimo({
    required this.termo,
    required this.restaurantId,
    required this.loja,
    required this.sugestoes,
    required this.criar,
  });

  final String termo;
  final String? restaurantId;
  final String? loja;
  final List<Map<String, dynamic>> sugestoes;
  final CriarSinonimo criar;

  @override
  State<_DialogoSinonimo> createState() => _DialogoSinonimoState();
}

class _DialogoSinonimoState extends State<_DialogoSinonimo> {
  late final TextEditingController _termo = TextEditingController(text: widget.termo);
  final TextEditingController _alvo = TextEditingController();
  late bool _soNestaLoja = widget.restaurantId != null;
  String? _produto;
  bool _aGravar = false;
  String? _erro;

  @override
  void dispose() {
    _termo.dispose();
    _alvo.dispose();
    super.dispose();
  }

  Future<void> _gravar() async {
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      final r = await widget.criar(
        termo: _termo.text.trim(),
        alvo: _alvo.text.trim().isEmpty ? null : _alvo.text.trim(),
        restaurantId: _soNestaLoja ? widget.restaurantId : null,
        productId: _produto,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _aGravar = false;
          _erro = '${r['erro'] ?? 'Não foi possível criar.'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aGravar = false;
        _erro = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Criar sinônimo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('sinonimo-termo'),
              controller: _termo,
              decoration: const InputDecoration(
                labelText: 'Quando o cliente escreve',
                hintText: 'ex.: gelado',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('sinonimo-alvo'),
              controller: _alvo,
              decoration: const InputDecoration(
                labelText: 'Procurar também por',
                hintText: 'ex.: mcflurry',
              ),
            ),
            if (widget.sugestoes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Ou mostrar este produto:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in widget.sugestoes)
                    ChoiceChip(
                      label: Text('${s['nome']}'),
                      selected: _produto == s['product_id'],
                      onSelected: (v) =>
                          setState(() => _produto = v ? s['product_id'] as String? : null),
                    ),
                ],
              ),
            ],
            if (widget.restaurantId != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _soNestaLoja,
                onChanged: (v) => setState(() => _soNestaLoja = v ?? false),
                title: Text('Só em ${widget.loja ?? 'esta loja'}'),
              ),
            if (_erro != null)
              Text(_erro!, style: const TextStyle(color: AppColors.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _aGravar ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('sinonimo-gravar'),
          onPressed: _aGravar ? null : _gravar,
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
