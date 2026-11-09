// Painel admin (PT-BR) — "Depósito Volta" (09/11/2026, ramo
// ai/2026-11-09-volta-deposito-kfc). Latas e garrafas de plástico (até 3 L)
// com depósito de 0,10 € por embalagem, cobrado ao cliente numa linha à parte
// (fora do subtotal, sem margem, taxas nem tokens).
//
// Três separadores:
//  · Resumo — a configuração (ligado/valor) e quantos produtos/opções de cada
//    loja têm depósito ou estão por rever (admin_volta_resumo_lojas).
//  · Produtos — lista paginada com filtro de loja, Todos/Com/Sem/Rever e
//    busca; toque muda o número de embalagens (admin_volta_definir); exporta
//    o filtro atual em CSV (admin_volta_produtos, todas as páginas).
//  · Relatório — o mês: cobrado, acertos, lido nos talões, parceiros e Bora
//    (admin_volta_relatorio_mensal).
//
// Sem as funções publicadas no servidor, cada parte diz "Função ainda não
// está no servidor" em vez de partir o ecrã. A lógica pura está em
// lib/utils/deposito_volta_admin.dart (testes: test/admin_volta_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../utils/deposito_volta_admin.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_platform_settings_screen.dart';
import 'admin_taloes_screen.dart' show AdminTaloesScreen;

/// Erro de uma RPC em PT-BR. Função/coluna que ainda não existe no servidor
/// → mensagem calma, não um erro cru.
String mensagemErroVolta(Object erro, String funcao) {
  if (servidorAindaSemIsto(erro)) {
    return '$kVoltaFuncaoNaoPublicada ($funcao). Assim que for publicada, '
        'esta parte aparece sozinha.';
  }
  final msg = erro is PostgrestException ? erro.message : '$erro';
  if (msg.contains('not_admin') || msg.contains('admin_required')) {
    return 'Sem permissão de administrador (a sessão não é de admin).';
  }
  return 'Erro do servidor: $msg';
}

/// As chamadas ao servidor. Os testes trocam-na por uma falsa.
class VoltaAdminApi {
  const VoltaAdminApi();

  SupabaseClient get _db => Supabase.instance.client;

  static List<Map<String, dynamic>> _lista(Object? r) => r is List
      ? r.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];

  static Map<String, dynamic> _mapa(Object? r) {
    if (r is Map) return Map<String, dynamic>.from(r);
    if (r is List && r.isNotEmpty && r.first is Map) {
      return Map<String, dynamic>.from(r.first as Map);
    }
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> resumoLojas() async =>
      _lista(await _db.rpc('admin_volta_resumo_lojas'));

  Future<List<Map<String, dynamic>>> produtos({
    String? loja,
    FiltroVolta filtro = FiltroVolta.todos,
    String? busca,
    int limite = 50,
    int offset = 0,
  }) async =>
      _lista(await _db.rpc('admin_volta_produtos', params: {
        'p_loja': loja,
        'p_filtro': filtroVoltaParaRpc(filtro),
        'p_busca': (busca == null || busca.trim().isEmpty) ? null : busca.trim(),
        'p_limite': limite,
        'p_offset': offset,
      }));

  Future<Map<String, dynamic>> definir({
    required String tipo,
    required String id,
    required int unidades,
  }) async =>
      _mapa(await _db.rpc('admin_volta_definir',
          params: {'p_tipo': tipo, 'p_id': id, 'p_units': unidades}));

  Future<Map<String, dynamic>> relatorioMensal(int ano, int mes) async =>
      _mapa(await _db.rpc('admin_volta_relatorio_mensal',
          params: {'p_ano': ano, 'p_mes': mes}));

  /// As chaves `volta_deposit_*` de platform_settings.
  Future<List<Map<String, dynamic>>> configuracao() async {
    final r = _lista(
        await _db.rpc('admin_list_settings', params: {'p_category': null}));
    return r.where((s) => '${s['key']}'.startsWith('volta_deposit_')).toList();
  }
}

class AdminVoltaScreen extends StatefulWidget {
  const AdminVoltaScreen({
    super.key,
    this.api = const VoltaAdminApi(),
    this.agora,
    this.exportar,
  });

  final VoltaAdminApi api;
  final DateTime Function()? agora;

  /// Nos testes: recebe o CSV em vez de partilhar/descarregar.
  final Future<void> Function(String nomeFicheiro, String csv)? exportar;

  @override
  State<AdminVoltaScreen> createState() => _AdminVoltaScreenState();
}

class _AdminVoltaScreenState extends State<AdminVoltaScreen>
    with SingleTickerProviderStateMixin {
  static const _porPagina = 50;
  static const _pequeno =
      TextStyle(fontSize: 12, color: AppColors.textSecondary);

  late final TabController _tab = TabController(length: 3, vsync: this);
  final _buscaCtrl = TextEditingController();

  // Resumo
  List<Map<String, dynamic>>? _resumo;
  String? _erroResumo;
  ({bool? ligado, int? centimos})? _config;
  String? _erroConfig;

  // Produtos
  String? _loja;
  FiltroVolta _filtro = FiltroVolta.todos;
  String _busca = '';
  final List<Map<String, dynamic>> _itens = [];
  int _total = 0;
  int _geracaoProd = 0;
  bool _carregandoProd = false;
  String? _erroProd;
  bool _exportando = false;

  // Relatório
  late final List<String> _meses =
      AdminTaloesScreen.ultimosMeses((widget.agora ?? DateTime.now)());
  late String _mes = _meses.first;
  Map<String, dynamic>? _rel;
  bool _carregandoRel = false;
  String? _erroRel;

  @override
  void initState() {
    super.initState();
    _carregarResumo();
    _carregarProdutos(doZero: true);
    _carregarRelatorio();
  }

  @override
  void dispose() {
    _tab.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── dados ─────────────────────────

  Future<void> _carregarResumo() async {
    List<Map<String, dynamic>>? resumo;
    String? erro;
    try {
      resumo = await widget.api.resumoLojas();
    } catch (e) {
      erro = mensagemErroVolta(e, 'admin_volta_resumo_lojas');
    }
    ({bool? ligado, int? centimos})? config;
    String? erroConfig;
    try {
      config = lerConfigVolta(await widget.api.configuracao());
    } catch (e) {
      erroConfig = mensagemErroVolta(e, 'admin_list_settings');
    }
    if (!mounted) return;
    setState(() {
      _resumo = resumo;
      _erroResumo = erro;
      _config = config;
      _erroConfig = erroConfig;
    });
  }

  Future<void> _carregarProdutos({bool doZero = false}) async {
    final geracao = doZero ? ++_geracaoProd : _geracaoProd;
    setState(() {
      _carregandoProd = true;
      _erroProd = null;
      if (doZero) {
        _itens.clear();
        _total = 0;
      }
    });
    try {
      final pagina = await widget.api.produtos(
        loja: _loja,
        filtro: _filtro,
        busca: _busca,
        limite: _porPagina,
        offset: _itens.length,
      );
      if (!mounted || geracao != _geracaoProd) return;
      setState(() {
        _itens.addAll(pagina);
        _total = pagina.isEmpty
            ? _itens.length
            : numVolta(pagina.first['total'])?.toInt() ?? _itens.length;
      });
    } catch (e) {
      if (!mounted || geracao != _geracaoProd) return;
      setState(() => _erroProd = mensagemErroVolta(e, 'admin_volta_produtos'));
    } finally {
      if (mounted && geracao == _geracaoProd) {
        setState(() => _carregandoProd = false);
      }
    }
  }

  Future<void> _carregarRelatorio() async {
    final mes = _mes;
    setState(() {
      _carregandoRel = true;
      _erroRel = null;
      _rel = null;
    });
    try {
      final p = mes.split('-');
      final r = await widget.api.relatorioMensal(int.parse(p[0]), int.parse(p[1]));
      if (!mounted || mes != _mes) return;
      setState(() => _rel = r);
    } catch (e) {
      if (!mounted || mes != _mes) return;
      setState(() =>
          _erroRel = mensagemErroVolta(e, 'admin_volta_relatorio_mensal'));
    } finally {
      if (mounted && mes == _mes) setState(() => _carregandoRel = false);
    }
  }

  void _abrirLoja(String lojaId) {
    setState(() => _loja = lojaId);
    _tab.animateTo(1);
    _carregarProdutos(doZero: true);
  }

  Future<void> _editar(Map<String, dynamic> item) async {
    final atual = numVolta(item['deposit_units'])?.toInt() ?? 0;
    final ctrl = TextEditingController(text: '$atual');
    final valor = eurosDeCentimos(_config?.centimos ?? 10);
    final novo = await showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setD) {
        final valido = validarUnidadesVolta(ctrl.text);
        return AlertDialog(
          title: const Text('Embalagens com depósito'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['nome'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${item['loja_nome'] ?? item['loja_id'] ?? ''}'
                    '${item['tipo'] == 'opcao' ? ' · opção' : ''}',
                    style: _pequeno),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('volta_unidades'),
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Embalagens (0 a $kVoltaUnidadesMax)',
                    helperText: '0 = sem depósito. Pack de 6 latas = 6.',
                    errorText: valido == null
                        ? 'Número inteiro de 0 a $kVoltaUnidadesMax'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setD(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cada embalagem cobra $valor ao cliente, numa linha à parte '
                  '(sem margem, taxas nem tokens). Conta só latas e garrafas de '
                  'plástico até 3 L.',
                  style: _pequeno,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: valido == null ? null : () => Navigator.pop(ctx, valido),
              child: const Text('Salvar'),
            ),
          ],
        );
      }),
    );
    if (novo == null || !mounted) return;
    try {
      final r = await widget.api.definir(
          tipo: '${item['tipo']}', id: '${item['id']}', unidades: novo);
      if (r['ok'] == false) {
        throw Exception(r['erro'] ?? r['error'] ?? 'o servidor recusou');
      }
      if (!mounted) return;
      final unidades = numVolta(r['deposit_units'])?.toInt() ?? novo;
      setState(() {
        final i = _itens.indexOf(item);
        if (i >= 0) {
          _itens[i] = {
            ...item,
            'deposit_units': unidades,
            'deposit_review': false,
            'deposit_origem': 'admin',
          };
        }
      });
      _aviso('Salvo: $unidades embalagens em "${item['nome'] ?? item['id']}".');
      _carregarResumo();
    } catch (e) {
      _aviso(mensagemErroVolta(e, 'admin_volta_definir'), erro: true);
    }
  }

  Future<void> _gravarCsv(String nome, String csv, String assunto) async {
    final f = widget.exportar;
    if (f != null) return f(nome, csv);
    await AdminExportService.instance
        .exportCsvText(filename: nome, csv: csv, subject: assunto);
  }

  Future<void> _exportarProdutos() async {
    setState(() => _exportando = true);
    try {
      final linhas = await buscarTodasAsPaginasVolta(
        (offset, limite) => widget.api.produtos(
            loja: _loja,
            filtro: _filtro,
            busca: _busca,
            limite: limite,
            offset: offset),
      );
      await _gravarCsv(
        'deposito-volta-${filtroVoltaParaRpc(_filtro)}-${_loja ?? 'todas-as-lojas'}.csv',
        csvDepositoVolta(linhas),
        'Depósito Volta — produtos e opções',
      );
      _aviso('CSV exportado: ${linhas.length} '
          '${linhas.length == 1 ? 'linha' : 'linhas'}.');
    } catch (e) {
      _aviso(mensagemErroVolta(e, 'admin_volta_produtos'), erro: true);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarRelatorio() async {
    final r = _rel;
    if (r == null) return;
    try {
      await _gravarCsv('deposito-volta-relatorio-$_mes.csv',
          csvRelatorioVolta(_mes, r), 'Depósito Volta — relatório $_mes');
      _aviso('Relatório exportado.');
    } catch (e) {
      _aviso('Erro a exportar: $e', erro: true);
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  // ───────────────────────── ecrã ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Depósito Volta',
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Resumo'),
            Tab(text: 'Produtos'),
            Tab(text: 'Relatório'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_abaResumo(), _abaProdutos(), _abaRelatorio()],
      ),
    );
  }

  Widget _abaResumo() {
    final resumo = _resumo;
    int n(Object? v) => numVolta(v)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: _carregarResumo,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cartaoConfig(),
          const SizedBox(height: 16),
          const Text('Embalagens com depósito por loja',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text('Toque numa loja para ver e mudar os produtos dela.',
              style: _pequeno),
          const SizedBox(height: 8),
          if (_erroResumo != null)
            _caixaErro(_erroResumo!)
          else if (resumo == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (resumo.isEmpty)
            _caixaVazia('Nenhuma loja com produtos marcados ainda.')
          else ...[
            Text(
              '${resumo.fold<int>(0, (s, l) => s + n(l['produtos_com']))} produtos · '
              '${resumo.fold<int>(0, (s, l) => s + n(l['opcoes_com']))} opções · '
              '${resumo.fold<int>(0, (s, l) => s + n(l['rever']))} para rever',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final l in resumo)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${l['loja_nome'] ?? l['loja_id'] ?? '—'}'),
                  subtitle: Text('${n(l['produtos_com'])} produtos · '
                      '${n(l['opcoes_com'])} opções com depósito'),
                  trailing: n(l['rever']) > 0
                      ? _selo('${n(l['rever'])} para rever', AppColors.warning)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _abrirLoja('${l['loja_id']}'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _cartaoConfig() {
    final c = _config;
    final List<String> linhas;
    if (_erroConfig != null) {
      linhas = [_erroConfig!];
    } else if (c == null) {
      linhas = ['Carregando a configuração…'];
    } else {
      linhas = [
        switch (c.ligado) {
          null => 'Cobrança ao cliente: a chave volta_deposit_enabled ainda '
              'não existe no servidor.',
          true => 'Cobrança ao cliente: LIGADA',
          false => 'Cobrança ao cliente: DESLIGADA',
        },
        c.centimos == null
            ? 'Valor por embalagem: a chave volta_deposit_cents ainda não '
                'existe no servidor.'
            : 'Valor por embalagem: ${eurosDeCentimos(c.centimos)}',
      ];
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.recycling, color: AppColors.success),
              SizedBox(width: 8),
              Text('Depósito Volta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            for (final l in linhas)
              Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Linha à parte na conta do cliente (fora do subtotal, sem margem, '
              'taxas nem tokens). Parceiro: recebe 100% no acerto semanal. '
              'Não-parceiro: fica com a Bora, porque o entregador pagou o '
              'depósito no balcão.',
              style: _pequeno,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Ligar/desligar e valor (Configurações)'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdminPlatformSettingsScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _abaProdutos() {
    final lojas = <(String, String)>[
      for (final l in _resumo ?? const <Map<String, dynamic>>[])
        ('${l['loja_id']}', '${l['loja_nome'] ?? l['loja_id']}'),
    ];
    final lojaNaLista = lojas.any((l) => l.$1 == _loja) ? _loja : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: lojaNaLista,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Todas as lojas')),
                        for (final l in lojas)
                          DropdownMenuItem<String?>(
                            value: l.$1,
                            child: Text(l.$2, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _loja = v);
                        _carregarProdutos(doZero: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _exportando || _itens.isEmpty
                        ? null
                        : _exportarProdutos,
                    icon: _exportando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Exportar CSV'),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final f in FiltroVolta.values)
                    ChoiceChip(
                      label: Text(rotuloFiltroVolta(f)),
                      selected: _filtro == f,
                      onSelected: (_) {
                        setState(() => _filtro = f);
                        _carregarProdutos(doZero: true);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _buscaCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar pelo nome (Enter para buscar)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _buscaCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar a busca',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _buscaCtrl.clear();
                            _busca = '';
                            _carregarProdutos(doZero: true);
                          },
                        ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (t) {
                  _busca = t.trim();
                  _carregarProdutos(doZero: true);
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _carregandoProd && _itens.isEmpty
                      ? 'Carregando…'
                      : '${_itens.length} de $_total · toque para mudar as embalagens',
                  style: _pequeno,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _erroProd != null && _itens.isEmpty
              ? ListView(padding: const EdgeInsets.all(12), children: [
                  _caixaErro(_erroProd!),
                ])
              : !_carregandoProd && _itens.isEmpty
                  ? ListView(padding: const EdgeInsets.all(12), children: [
                      _caixaVazia('Nada com este filtro.'),
                    ])
                  : ListView.builder(
                      itemCount: _itens.length + 1,
                      itemBuilder: (_, i) =>
                          i == _itens.length ? _rodape() : _linhaProduto(_itens[i]),
                    ),
        ),
      ],
    );
  }

  Widget _rodape() {
    if (_carregandoProd) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erroProd != null) {
      return Padding(
          padding: const EdgeInsets.all(12), child: _caixaErro(_erroProd!));
    }
    if (_itens.length < _total) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: TextButton(
            onPressed: () => _carregarProdutos(),
            child: Text('Carregar mais (${_itens.length} de $_total)'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }

  Widget _linhaProduto(Map<String, dynamic> p) {
    final unidades = numVolta(p['deposit_units'])?.toInt() ?? 0;
    final detalhe = [
      p['loja_nome'],
      p['categoria'],
      precoVolta(numVolta(p['preco'])),
    ].where((s) => s != null && '$s'.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _miniatura(p['image_url'] as String?),
        title: Text('${p['nome'] ?? '—'}',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detalhe,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _pequeno),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              if (p['tipo'] == 'opcao') _selo('opção', AppColors.info),
              _selo(rotuloOrigemVolta(p['deposit_origem'] as String?),
                  AppColors.textSecondary),
              if (p['deposit_review'] == true) _selo('rever', AppColors.warning),
            ]),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$unidades',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: unidades > 0
                        ? AppColors.success
                        : AppColors.textSecondary)),
            const Text('emb.', style: TextStyle(fontSize: 10)),
          ],
        ),
        onTap: () => _editar(p),
      ),
    );
  }

  Widget _abaRelatorio() {
    final rel = _rel;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _mes,
                items: [
                  for (final m in _meses)
                    DropdownMenuItem(
                        value: m, child: Text(AdminTaloesScreen.nomeDoMes(m))),
                ],
                onChanged: (m) {
                  if (m == null || m == _mes) return;
                  setState(() => _mes = m);
                  _carregarRelatorio();
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: rel == null ? null : _exportarRelatorio,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_carregandoRel)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_erroRel != null)
          _caixaErro(_erroRel!)
        else if (rel != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                for (final l in linhasRelatorioVolta(rel))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(l.$1)),
                      Text(l.$2,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Como ler: "Cobrado aos clientes" é o depósito cobrado quando o pedido '
          'é criado. "Acertos" é o que mudou depois (produto em falta, talão com '
          'mais ou menos depósito): positivo = cobrado a mais, negativo = '
          'devolvido. Os parceiros recebem 100% do depósito no acerto semanal; '
          'nos não-parceiros o entregador pagou o depósito no balcão, por isso '
          'fica com a Bora.',
          style: _pequeno,
        ),
      ],
    );
  }

  // ───────────────────────── peças ─────────────────────────

  Widget _miniatura(String? url) {
    const tam = 44.0;
    final icone = Container(
      width: tam,
      height: tam,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.local_drink_outlined,
          color: AppColors.textSecondary),
    );
    if (url == null || url.isEmpty) return icone;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: tam,
          height: tam,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => icone),
    );
  }

  Widget _selo(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 10, color: cor, fontWeight: FontWeight.w700)),
      );

  Widget _caixaErro(String texto) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined,
              size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _caixaVazia(String texto) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(texto, style: _pequeno)),
      );
}
