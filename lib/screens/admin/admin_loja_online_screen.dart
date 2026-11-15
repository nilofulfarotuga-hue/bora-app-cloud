// lib/screens/admin/admin_loja_online_screen.dart
//
// Painel (PT-BR) da categoria Loja Online (15/11/2026, fechar-tudo-15-11
// ponto E, caixa 10): o interruptor `loja_online_ativa` (pela RPC
// `admin_update_setting`, a mesma do resto do painel, auditada), o nicho da
// semana e a lista de produtos com os botões Ativo / Destaque. Toda ação
// pede um motivo e passa pelas RPCs propostas em
// docs/propostas/fechar-tudo-15-11/E_loja_online.PROPOSTA.sql
// (SECURITY DEFINER, is_admin(), log_admin_action). Enquanto a proposta não
// for aplicada, a tela diz "Esta parte ainda não foi instalada no servidor.".
// Não mexe em preço (o preço = 2x o custo vem da importação da Shopify) nem
// em pagamentos.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/loja_online_produto.dart';
import '../../services/loja_online_service.dart';
import 'admin_loja_online_encomendas_screen.dart';
import '_admin_rpc_errors.dart';

/// Tradução dos erros desta tela: tabela, função ou chave por instalar dão a
/// frase única do painel; o resto segue [humanizeAdminRpcError].
String erroAdminLojaOnline(Object e) {
  if (lojaOnlineServidorEmFalta(e)) return kLojaOnlineNaoInstalada;
  if (e is PostgrestException && e.message.startsWith('unknown_setting')) {
    return kLojaOnlineNaoInstalada;
  }
  return humanizeAdminRpcError(e);
}

/// Resumo de um produto para a lista: nicho, preço na Bora, custo e prazo.
String resumoProdutoLojaOnline(LojaOnlineProduto p, String nomeNicho) {
  final partes = <String>[
    if (nomeNicho.isNotEmpty) nomeNicho,
    'Preço na Bora ${p.precoTexto}',
    'custo ${p.custoTexto}',
  ];
  if (p.prazoMinDias > 0 || p.prazoMaxDias > 0) {
    final a = p.prazoMinDias > 0 ? p.prazoMinDias : p.prazoMaxDias;
    final b = p.prazoMaxDias > 0 ? p.prazoMaxDias : p.prazoMinDias;
    partes.add(a == b ? 'correio $a dias' : 'correio $a a $b dias');
  }
  return partes.join(' · ');
}

String _diaMes(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(l.day)}/${dois(l.month)}';
}

class AdminLojaOnlineScreen extends StatefulWidget {
  const AdminLojaOnlineScreen({super.key, this.service});

  /// Por omissão fala com o Supabase. Existe para os testes.
  final LojaOnlineAdminService? service;

  @override
  State<AdminLojaOnlineScreen> createState() => _AdminLojaOnlineScreenState();
}

class _AdminLojaOnlineScreenState extends State<AdminLojaOnlineScreen> {
  late final LojaOnlineAdminService _svc;

  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  bool? _interruptor;
  List<LojaOnlineNicho> _nichos = const [];
  List<LojaOnlineProduto> _produtos = const [];
  List<LojaOnlineSubcategoria> _subcategorias = const [];

  /// Juiz 15/11 (9): sem a N1 no servidor não se mostram os controlos dos nichos.
  bool _n1Instalado = false;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? LojaOnlineAdminService();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final interruptor = await _svc.lerInterruptor();
      final nichos = await _svc.listarNichos();
      // loja-nichos-15-11: a mesma ordem do cliente (mais vendidos primeiro).
      final produtos = [...await _svc.listarProdutos()]
        ..sort(compararMaisVendidos);
      final subcategorias = await _svc.listarSubcategorias();
      final n1 = subcategorias != null;
      if (!mounted) return;
      setState(() {
        _interruptor = interruptor;
        _nichos = nichos;
        _produtos = produtos;
        _subcategorias = subcategorias ?? const [];
        _n1Instalado = n1;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = erroAdminLojaOnline(e);
        _carregando = false;
      });
    }
  }

  void _msg(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red : null,
      ));
  }

  LojaOnlineNicho? get _nichoDaSemana {
    LojaOnlineNicho? atual;
    for (final n in _nichos) {
      if (!n.ativo || n.destaqueDesde == null) continue;
      if (atual == null || n.destaqueDesde!.isAfter(atual.destaqueDesde!)) {
        atual = n;
      }
    }
    return atual;
  }

  String _nomeDoNicho(String id) {
    for (final n in _nichos) {
      if (n.id == id) return n.nome;
    }
    return '';
  }

  Future<String?> _pedirMotivo(String titulo, {String? explicacao}) async {
    final r = await showDialog<String>(
      context: context,
      builder: (_) =>
          _MotivoLojaOnlineDialog(titulo: titulo, explicacao: explicacao),
    );
    if (r == null) return null;
    if (r.length < 3) {
      _msg('Escreva o motivo (mínimo 3 letras).', erro: true);
      return null;
    }
    return r;
  }

  Future<void> _mudarInterruptor(bool ligado) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ligado
            ? 'Ligar a Loja Online no app?'
            : 'Desligar a Loja Online no app?'),
        content: Text(ligado
            ? 'O ladrilho "Loja Online" passa a aparecer na tela inicial do '
                'cliente com os produtos ativos. O botão de encomendar continua '
                'desligado (sem pagamentos nesta versão).'
            : 'O ladrilho "Loja Online" deixa de aparecer para o cliente. Os '
                'produtos ficam guardados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.mudarInterruptor(ligado);
      _msg(ligado ? 'Loja Online ligada no app.' : 'Loja Online desligada.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _produtoEstado(LojaOnlineProduto p,
      {bool? ativo, bool? destaque}) async {
    final String titulo;
    if (ativo != null) {
      titulo = ativo
          ? 'Mostrar "${p.titulo}" ao cliente?'
          : 'Esconder "${p.titulo}" do cliente?';
    } else {
      titulo = (destaque ?? false)
          ? 'Pôr "${p.titulo}" em destaque?'
          : 'Tirar "${p.titulo}" do destaque?';
    }
    final motivo = await _pedirMotivo(titulo);
    if (motivo == null) return;
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.produtoEstado(
          id: p.id, ativo: ativo, destaque: destaque, motivo: motivo);
      _msg('Produto atualizado (fica no registro).');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _tornarNichoDaSemana(LojaOnlineNicho n) async {
    final motivo = await _pedirMotivo(
      'Tornar "${n.nome}" o nicho da semana?',
      explicacao: 'Os produtos em destaque deste nicho passam a abrir a loja '
          'do cliente como "Novidade da semana".',
    );
    if (motivo == null) return;
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.nichoDaSemana(nichoId: n.id, motivo: motivo);
      _msg('Nicho da semana atualizado: ${n.nome}.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// loja-nichos-15-11: abrir o nicho a todos os clientes ou fechar.
  Future<void> _nichoPublico(LojaOnlineNicho n, bool publico) async {
    final motivo = await _pedirMotivo(
      publico ? 'Abrir "${n.nome}" para todos os clientes?' : 'Fechar "${n.nome}"?',
      explicacao: publico
          ? 'Os clientes passam a ver este nicho na Loja Online (com a categoria '
              'ligada no app). Faça isso só depois de o Danilo dizer "abrir".'
          : 'O nicho deixa de aparecer para os clientes. Você e as contas da lista '
              'de permissão continuam vendo.',
    );
    if (motivo == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.nichoPublico(nichoId: n.id, publico: publico, motivo: motivo);
      _msg(publico ? 'Nicho aberto: ${n.nome}.' : 'Nicho fechado: ${n.nome}.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// loja-nichos-15-11: fixar a posição de um produto (vazio = automática).
  Future<void> _produtoPosicao(LojaOnlineProduto p) async {
    final campo = TextEditingController(text: p.ordemManual?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Posição de "${p.titulo}"'),
        content: TextField(
          key: const Key('loja_online_posicao_campo'),
          controller: campo,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Posição (1 = primeiro; vazio = pelas vendas)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar')),
        ],
      ),
    );
    final texto = campo.text.trim();
    campo.dispose();
    if (ok != true || !mounted) return;
    final ordem = texto.isEmpty ? null : int.tryParse(texto);
    if (texto.isNotEmpty && (ordem == null || ordem < 1)) {
      _msg('A posição precisa ser um número a partir de 1.', erro: true);
      return;
    }
    final motivo = await _pedirMotivo(ordem == null
        ? 'Voltar "${p.titulo}" à ordem pelas vendas?'
        : 'Pôr "${p.titulo}" na posição $ordem?');
    if (motivo == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.produtoOrdem(id: p.id, ordemManual: ordem, motivo: motivo);
      _msg('Posição atualizada.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _produtoSubcategoria(LojaOnlineProduto p, String? subId) async {
    final nome = subId == null ? 'sem subcategoria' : _nomeSubcategoria(subId);
    final motivo = await _pedirMotivo('Pôr "${p.titulo}" em $nome?');
    if (motivo == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.produtoSubcategoria(id: p.id, subcategoriaId: subId, motivo: motivo);
      _msg('Subcategoria atualizada.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _subcategoriaAtivo(LojaOnlineSubcategoria sc, bool ativo) async {
    final motivo = await _pedirMotivo(
        ativo ? 'Ligar a subcategoria "${sc.nome}"?' : 'Desligar a subcategoria "${sc.nome}"?',
        explicacao: 'Desligada, some da loja do cliente; os produtos continuam em "Todos".');
    if (motivo == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await _svc.subcategoriaAtivo(id: sc.id, ativo: ativo, motivo: motivo);
      _msg('Subcategoria atualizada.');
      await _carregar();
    } catch (e) {
      _msg(erroAdminLojaOnline(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _nomeSubcategoria(String? id) =>
      _subcategorias.where((s) => s.id == id).map((s) => s.nome).firstOrNull ??
      'sem subcategoria';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loja Online')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _CartaoParaQueServe(),
                  const SizedBox(height: 12),
                  if (_erro != null)
                    _CartaoErro(texto: _erro!, onTentar: _carregar)
                  else ...[
                    _cartaoInterruptor(),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        key: const Key('loja_online_abrir_encomendas'),
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: const Text('Encomendas a fazer ao fornecedor'),
                        subtitle: const Text(
                            'Compras pagas pelos clientes: encomendar na CJ, '
                            'colocar o rastreio e marcar entregue.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const AdminLojaOnlineEncomendasScreen())),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _cartaoNichos(),
                    const SizedBox(height: 12),
                    _cabecalhoProdutos(),
                    const SizedBox(height: 8),
                    if (_produtos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Ainda não há produtos. A sincronização com a loja '
                          'Shopify é o próximo passo (precisa do token da '
                          'Shopify, guardado só no servidor).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final p in _produtos) _cartaoProduto(p),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _cartaoInterruptor() {
    final valor = _interruptor;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('loja_online_interruptor'),
            title: const Text('Categoria visível no app do cliente'),
            subtitle: Text(valor == null
                ? kLojaOnlineNaoInstalada
                : valor
                    ? 'Ligada: o ladrilho "Loja Online" aparece na tela inicial '
                        'do cliente.'
                    : 'Desligada: nada muda para o cliente. Ligue só quando '
                        'houver produtos ativos.'),
            value: valor ?? false,
            onChanged:
                (valor == null || _ocupado) ? null : _mudarInterruptor,
          ),
        ],
      ),
    );
  }

  Widget _cartaoNichos() {
    final semana = _nichoDaSemana;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nicho da semana',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'O nicho em destaque abre a loja do cliente como "Novidade da '
              'semana" (um por semana, como no vídeo do dropshipping). Os '
              'outros nichos continuam visíveis abaixo dele.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (_nichos.isEmpty)
              const Text('Ainda não há nichos.',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              for (final n in _nichos)
                ListTile(
                  key: Key('loja_online_nicho_${n.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(n.nome),
                  subtitle: Text([
                    '${_produtos.where((p) => p.nichoId == n.id && p.ativo).length} '
                        'produto(s) ativo(s)',
                    if (_n1Instalado)
                      n.publico
                          ? 'aberto a todos'
                          : 'fechado: só admin e lista de permissão',
                    if (!n.ativo) 'nicho desligado',
                    if (semana == n && n.destaqueDesde != null)
                      'nicho da semana desde ${_diaMes(n.destaqueDesde)}',
                  ].join(' · ')),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      if (_n1Instalado)
                        Switch(
                          key: Key('loja_online_nicho_publico_${n.id}'),
                          value: n.publico,
                          onChanged: _ocupado ? null : (v) => _nichoPublico(n, v),
                        ),
                      semana == n
                          ? const Chip(label: Text('Em destaque'))
                          : TextButton(
                              onPressed: _ocupado
                                  ? null
                                  : () => _tornarNichoDaSemana(n),
                              child: const Text('Tornar nicho da semana'),
                            ),
                    ],
                  ),
                ),
              for (final n in _nichos)
                if (_subcategorias.any((sc) => sc.nichoId == n.id))
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final sc in _subcategorias.where((sc) => sc.nichoId == n.id))
                        FilterChip(
                          key: Key('loja_online_subcategoria_ativa_${sc.id}'),
                          label: Text('${n.nome} › ${sc.nome}'),
                          selected: sc.ativo,
                          onSelected: _ocupado ? null : (v) => _subcategoriaAtivo(sc, v),
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalhoProdutos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Produtos (${_produtos.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Os produtos chegam da loja Shopify pela sincronização e nascem '
          'desligados. Ativo = aparece ao cliente. Destaque = entra na '
          '"Novidade da semana" do seu nicho. O preço na Bora é 2x o custo do '
          'fornecedor (regra do Danilo de 14/11/2026, aplicada na importação; '
          'aqui não se edita preço).',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _cartaoProduto(LojaOnlineProduto p) {
    final foto = p.fotoPrincipal;
    return Card(
      key: Key('loja_online_produto_${p.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: foto == null
                        ? Container(
                            color: AppColors.primaryWash,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined,
                                color: AppColors.textSecondary),
                          )
                        : Image.network(
                            foto,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primaryWash,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.titulo,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        resumoProdutoLojaOnline(p, _nomeDoNicho(p.nichoId)),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        '${_nomeSubcategoria(p.subcategoriaId)} · '
                        'vendas na loja: ${p.vendasLoja} · ranking CJ: ${p.cjListas}'
                        '${p.ordemManual == null ? '' : ' · posição fixa: ${p.ordemManual}'}',
                        key: Key('loja_online_vendas_${p.id}'),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      if (p.shopifyProductId.isNotEmpty)
                        Text('Shopify: ${p.shopifyProductId}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSubtle)),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _Interruptor(
                    key: Key('loja_online_ativo_${p.id}'),
                    rotulo: 'Ativo',
                    valor: p.ativo,
                    onChanged: _ocupado
                        ? null
                        : (v) => _produtoEstado(p, ativo: v),
                  ),
                ),
                Expanded(
                  child: _Interruptor(
                    key: Key('loja_online_destaque_${p.id}'),
                    rotulo: 'Destaque',
                    valor: p.destaque,
                    onChanged: _ocupado
                        ? null
                        : (v) => _produtoEstado(p, destaque: v),
                  ),
                ),
                if (_subcategorias.any((sc) => sc.nichoId == p.nichoId))
                  DropdownButton<String?>(
                    key: Key('loja_online_subcategoria_${p.id}'),
                    value: _subcategorias.any((sc) => sc.id == p.subcategoriaId)
                        ? p.subcategoriaId
                        : null,
                    hint: const Text('Subcategoria'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('sem subcategoria')),
                      for (final sc in _subcategorias.where((sc) => sc.nichoId == p.nichoId))
                        DropdownMenuItem<String?>(value: sc.id, child: Text(sc.nome)),
                    ],
                    onChanged: _ocupado
                        ? null
                        : (v) {
                            if (v != p.subcategoriaId) _produtoSubcategoria(p, v);
                          },
                  ),
                TextButton(
                  key: Key('loja_online_posicao_${p.id}'),
                  onPressed: _ocupado ? null : () => _produtoPosicao(p),
                  child: const Text('Posição'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Interruptor extends StatelessWidget {
  const _Interruptor({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.onChanged,
  });

  final String rotulo;
  final bool valor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(
          value: valor,
          onChanged: onChanged,
        ),
        Text(rotulo),
      ],
    );
  }
}

class _CartaoParaQueServe extends StatelessWidget {
  const _CartaoParaQueServe();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primaryWash,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.storefront_outlined, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Para que serve: aqui você liga ou desliga a categoria '
                '"Loja Online" no app do cliente e escolhe quais produtos da '
                'loja Shopify da Bora (dropshipping: o fornecedor envia pelo '
                'correio, de qualquer país, no prazo que ele der) aparecem, '
                'quais estão em destaque e qual é o nicho da semana; nesta '
                'primeira versão o cliente só vê, porque o botão "Encomendar" '
                'fica desligado até os pagamentos serem autorizados.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoErro extends StatelessWidget {
  const _CartaoErro({required this.texto, required this.onTentar});

  final String texto;
  final Future<void> Function() onTentar;

  @override
  Widget build(BuildContext context) {
    final naoInstalada = texto == kLojaOnlineNaoInstalada;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(naoInstalada ? Icons.build_outlined : Icons.error_outline,
                    color: naoInstalada ? AppColors.warning : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(texto,
                      key: const Key('loja_online_erro'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (naoInstalada) ...[
              const SizedBox(height: 8),
              const Text(
                'A proposta SQL está em docs/propostas/fechar-tudo-15-11/'
                'E_loja_online.PROPOSTA.sql (tabelas, regras de acesso, '
                'interruptor e funções). Quando a Claude.ai aplicar, esta tela '
                'passa a funcionar sem mudar nada no app.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onTentar,
                child: const Text('Tentar de novo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo do motivo (Juiz 15/11): o próprio diálogo é dono do campo de texto
/// e só o liberta quando sai da árvore, depois da animação de fecho.
class _MotivoLojaOnlineDialog extends StatefulWidget {
  const _MotivoLojaOnlineDialog({required this.titulo, this.explicacao});

  final String titulo;
  final String? explicacao;

  @override
  State<_MotivoLojaOnlineDialog> createState() =>
      _MotivoLojaOnlineDialogState();
}

class _MotivoLojaOnlineDialogState extends State<_MotivoLojaOnlineDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explicacao = widget.explicacao;
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (explicacao != null) ...[
            Text(explicacao),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const Key('loja_online_motivo'),
            controller: _c,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Motivo (fica no registro, mínimo 3 letras)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Confirmar')),
      ],
    );
  }
}
