// Faixas da home (ronda 05/10/2026, agente admin).
// As faixas (banners) que o cliente vê no topo da página inicial vivem na
// tabela `home_banners` (escrita só is_admin()). Aqui o Danilo lista por ordem,
// cria, edita, apaga, liga/desliga e reordena arrastando, escolhe o destino do
// toque, envia a imagem (Edge `upload-restaurant-asset`, igual ao ecrã do
// parceiro) e vê vistas/cliques/CTR (admin_banner_stats). Cada acção fica no
// histórico (log_admin_action, sobrecarga com entity_id uuid).
// Os códigos promocionais só se LEEM (admin_list_promo_codes); value_cents são
// tokens, por isso aqui não aparece valor nenhum, só o código.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/safe_image_picker.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_opcoes_produto_screen.dart' show AdminEscolherLoja;

const _tiposDestino = <String, String>{
  'loja': 'Loja (abre a página de uma loja)',
  'categoria': 'Categoria (abre uma secção da home)',
  'cozinha': 'Cozinha (filtra por tipo de comida)',
  'produto': 'Produto (abre um produto)',
  'codigo': 'Código promocional (mostra o código)',
  'nenhum': 'Nenhum (só informativa, sem toque)',
};

const _categorias = <String, String>{
  'restaurantes': 'Restaurantes',
  'supermercados': 'Supermercados',
  'farmacia': 'Farmácia',
  'lojas': 'Lojas',
  'festas': 'Festas',
  'sobremesas': 'Sobremesas',
  'servicos': 'Serviços',
  'limpeza': 'Limpeza',
  'motorista': 'Bora Motorista',
};

final _hexRe = RegExp(r'^#[0-9A-Fa-f]{6}$');

Color _corHex(String? hex, Color padrao) {
  final h = (hex ?? '').trim();
  if (!_hexRe.hasMatch(h)) return padrao;
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

Future<void> _logFaixa(
    String acao, String bannerId, Map<String, dynamic> detalhes) async {
  await Supabase.instance.client.rpc('log_admin_action', params: {
    'p_action': acao,
    'p_entity_type': 'home_banner',
    'p_entity_id': bannerId,
    'p_details': detalhes,
  });
}

/// Pré-visualização igual à do cliente: gradiente cor_inicio→cor_fim, imagem
/// de fundo se houver, título branco bold 20, subtítulo branco 14, cantos 16,
/// altura 120.
class HomeBannerPreview extends StatelessWidget {
  const HomeBannerPreview({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.imagemUrl,
    this.corInicio,
    this.corFim,
  });

  final String titulo;
  final String? subtitulo;
  final String? imagemUrl;
  final String? corInicio;
  final String? corFim;

  @override
  Widget build(BuildContext context) {
    final c1 = _corHex(corInicio, AppColors.primary);
    final c2 = _corHex(corFim, AppColors.primaryDark);
    final temImagem = (imagemUrl ?? '').isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 120,
        child: Stack(fit: StackFit.expand, children: [
          if (temImagem)
            Image.network(imagemUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: temImagem
                    ? [c1.withValues(alpha: 0.85), c2.withValues(alpha: 0.55)]
                    : [c1, c2],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo.isEmpty ? 'Título da faixa' : titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                if ((subtitulo ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitulo!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class AdminHomeBannersScreen extends StatefulWidget {
  const AdminHomeBannersScreen({super.key});

  @override
  State<AdminHomeBannersScreen> createState() => _AdminHomeBannersScreenState();
}

class _AdminHomeBannersScreenState extends State<AdminHomeBannersScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _faixas = [];
  final Map<String, Map<String, num>> _stats = {};
  final Map<String, String> _nomesLojas = {};
  final Map<String, String> _nomesProdutos = {};
  bool _loading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final rows = await _sb
          .from('home_banners')
          .select()
          .order('ordem')
          .order('criado_em');
      final faixas = List<Map<String, dynamic>>.from(rows);

      final lojaIds = <String>{
        for (final f in faixas) ...[
          if (f['tipo_destino'] == 'loja' && f['destino'] != null)
            '${f['destino']}',
          if (f['parceiro_id'] != null) '${f['parceiro_id']}',
        ]
      }.toList();
      if (lojaIds.isNotEmpty) {
        final lojas = await _sb
            .from('restaurants')
            .select('id, name')
            .inFilter('id', lojaIds);
        for (final l in List<Map<String, dynamic>>.from(lojas)) {
          _nomesLojas['${l['id']}'] = '${l['name'] ?? l['id']}';
        }
      }
      final prodIds = [
        for (final f in faixas)
          if (f['tipo_destino'] == 'produto' && f['destino'] != null)
            '${f['destino']}'
      ];
      if (prodIds.isNotEmpty) {
        final prods = await _sb
            .from('products')
            .select('id, name')
            .inFilter('id', prodIds);
        for (final p in List<Map<String, dynamic>>.from(prods)) {
          _nomesProdutos['${p['id']}'] = '${p['name'] ?? p['id']}';
        }
      }
      if (!mounted) return;
      setState(() {
        _faixas = faixas;
        _loading = false;
      });
      await _loadStats();
    } catch (e) {
      debugPrint('[AdminHomeBanners] $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = 'Não consegui carregar as faixas: $e';
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await _sb.rpc('admin_banner_stats', params: {'p_dias': 30});
      final linhas = ((res as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map));
      _stats.clear();
      for (final l in linhas) {
        final id = '${l['banner_id'] ?? l['id'] ?? ''}';
        if (id.isEmpty) continue;
        final vistas = _num(l['vistas']);
        final cliques = _num(l['cliques']);
        // CTR recalculado das contagens (não depende de vir em 0–1 ou 0–100).
        final ctr = vistas > 0 ? cliques * 100 / vistas : _num(l['ctr']);
        _stats[id] = {'vistas': vistas, 'cliques': cliques, 'ctr': ctr};
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[AdminHomeBanners] stats: $e');
    }
  }

  String _destinoLegivel(Map<String, dynamic> f) {
    final tipo = '${f['tipo_destino'] ?? 'nenhum'}';
    final d = '${f['destino'] ?? ''}';
    switch (tipo) {
      case 'loja':
        return 'Loja: ${_nomesLojas[d] ?? d}';
      case 'produto':
        return 'Produto: ${_nomesProdutos[d] ?? d}';
      case 'categoria':
        return 'Categoria: ${_categorias[d] ?? d}';
      case 'cozinha':
        return 'Cozinha: $d';
      case 'codigo':
        return 'Código: $d';
      default:
        return 'Sem destino';
    }
  }

  String _janela(Map<String, dynamic> f) {
    final i = f['inicio'];
    final fim = f['fim'];
    if (i == null && fim == null) return 'Sempre';
    return '${i == null ? 'já' : dataHoraLisboa(i)} → '
        '${fim == null ? 'sem fim' : dataHoraLisboa(fim)}';
  }

  Future<void> _abrirEditor([Map<String, dynamic>? faixa]) async {
    final proximaOrdem = _faixas.isEmpty
        ? 10
        : (_faixas.map((f) => _num(f['ordem']).toInt()).reduce(
                (a, b) => a > b ? a : b) +
            10);
    final gravou = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) =>
          _EditorFaixaScreen(faixa: faixa, ordemNova: proximaOrdem),
    ));
    if (gravou == true) await _load();
  }

  Future<void> _alternarAtivo(Map<String, dynamic> f, bool ativo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sb.from('home_banners').update({
        'ativo': ativo,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', f['id']);
      await _logFaixa(ativo ? 'faixa_ligada' : 'faixa_desligada', '${f['id']}',
          {'titulo': f['titulo'], 'antes': f['ativo'], 'depois': ativo});
      if (mounted) setState(() => f['ativo'] = ativo);
      messenger.showSnackBar(SnackBar(
          content: Text(ativo ? 'Faixa ligada.' : 'Faixa desligada.')));
    } catch (e) {
      debugPrint('[AdminHomeBanners] ativo: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui mudar a faixa.')));
    }
  }

  Future<void> _apagar(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar faixa?'),
        content: Text(
            'A faixa "${f['titulo'] ?? ''}" sai da home do cliente e não volta. '
            'Se só quer escondê-la por agora, use o interruptor.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sb.from('home_banners').delete().eq('id', f['id']);
      await _logFaixa('faixa_apagada', '${f['id']}', {'antes': f});
      messenger.showSnackBar(const SnackBar(content: Text('Faixa apagada.')));
      await _load();
    } catch (e) {
      debugPrint('[AdminHomeBanners] apagar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui apagar a faixa.')));
    }
  }

  Future<void> _reordenar(int de, int para) async {
    if (para > de) para -= 1;
    if (de == para) return;
    final lista = List<Map<String, dynamic>>.from(_faixas);
    final movida = lista.removeAt(de);
    lista.insert(para, movida);
    final antes = {for (final f in _faixas) '${f['id']}': f['ordem']};
    setState(() => _faixas = lista);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final agora = DateTime.now().toUtc().toIso8601String();
      final depois = <String, int>{};
      for (var i = 0; i < lista.length; i++) {
        final nova = (i + 1) * 10;
        final f = lista[i];
        depois['${f['id']}'] = nova;
        if (_num(f['ordem']).toInt() == nova) continue;
        await _sb
            .from('home_banners')
            .update({'ordem': nova, 'atualizado_em': agora}).eq('id', f['id']);
        f['ordem'] = nova;
      }
      await _logFaixa('faixa_reordenada', '${movida['id']}', {
        'titulo': movida['titulo'],
        'de_posicao': de + 1,
        'para_posicao': para + 1,
        'ordem_antes': antes,
        'ordem_depois': depois,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Ordem gravada.')));
    } catch (e) {
      debugPrint('[AdminHomeBanners] reordenar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui gravar a ordem.')));
      await _load();
    }
  }

  Future<void> _maisPedidos() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: FutureBuilder<dynamic>(
          future: _sb.rpc('home_mais_pedidos', params: {'p_limit': 10}),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Não consegui ler as lojas mais pedidas: '
                    '${snap.error}'),
              );
            }
            final linhas = ((snap.data as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: ListView(shrinkWrap: true, children: [
                const ListTile(
                  title: Text('Lojas mais pedidas',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Só leitura. Pedidos nos últimos 30 dias — é a mesma '
                      'lista que o cliente vê em "Mais pedidas". Útil para '
                      'escolher a loja de uma faixa.'),
                ),
                if (linhas.isEmpty)
                  const ListTile(title: Text('Sem pedidos nos últimos 30 dias.')),
                for (var i = 0; i < linhas.length; i++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primaryLight,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 12))),
                    title: Text('${linhas[i]['name'] ?? linhas[i]['nome'] ?? linhas[i]['restaurant_name'] ?? linhas[i]['id'] ?? '—'}'),
                    trailing: Text(
                        '${_num(linhas[i]['pedidos_30d']).toInt()} pedidos',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'As faixas coloridas do topo da página inicial do cliente. '
          'Arraste pela pega (≡) para mudar a ordem. Números dos últimos 30 dias: '
          'vistas (quantas vezes apareceu), cliques (quantas vezes tocaram) e '
          'CTR (percentagem de quem viu e clicou).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _maisPedidos,
          icon: const Icon(Icons.local_fire_department_outlined),
          label: const Text('Ver lojas mais pedidas'),
        ),
      ]),
    );
  }

  Widget _cartao(Map<String, dynamic> f, int index) {
    final id = '${f['id']}';
    final st = _stats[id];
    final ativo = f['ativo'] == true;
    return Card(
      key: ValueKey(id),
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(
            opacity: ativo ? 1 : 0.45,
            child: HomeBannerPreview(
              titulo: '${f['titulo'] ?? ''}',
              subtitulo: f['subtitulo'] as String?,
              imagemUrl: f['imagem_url'] as String?,
              corInicio: f['cor_inicio'] as String?,
              corFim: f['cor_fim'] as String?,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '#${index + 1} · ${_destinoLegivel(f)}'
                        '${f['patrocinado'] == true ? ' · Patrocinada' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('Quando: ${_janela(f)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    if (f['patrocinado'] == true && f['parceiro_id'] != null)
                      Text(
                          'Parceiro: ${_nomesLojas['${f['parceiro_id']}'] ?? f['parceiro_id']}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                        st == null
                            ? 'Sem números ainda (30 dias).'
                            : 'Vistas ${st['vistas']!.toInt()} · '
                                'Cliques ${st['cliques']!.toInt()} · '
                                'CTR ${st['ctr']!.toStringAsFixed(1).replaceAll('.', ',')}%',
                        style: const TextStyle(fontSize: 12)),
                  ]),
            ),
            Switch(value: ativo, onChanged: (v) => _alternarAtivo(f, v)),
            IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _abrirEditor(f)),
            IconButton(
                tooltip: 'Apagar',
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _apagar(f)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Faixas da home',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nova faixa'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24), child: Text(_erro!)))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(bottom: 96),
                  header: Column(children: [
                    _cabecalho(),
                    if (_faixas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Ainda não há faixas. Toque em "Nova faixa".'),
                      ),
                  ]),
                  itemCount: _faixas.length,
                  // O CI compila com Flutter 3.41.2: `onReorderItem` pode não
                  // existir lá; `onReorder` existe nos dois.
                  // ignore: deprecated_member_use
                  onReorder: _reordenar,
                  itemBuilder: (_, i) => _cartao(_faixas[i], i),
                ),
    );
  }
}

class _EditorFaixaScreen extends StatefulWidget {
  const _EditorFaixaScreen({this.faixa, required this.ordemNova});
  final Map<String, dynamic>? faixa;
  final int ordemNova;

  @override
  State<_EditorFaixaScreen> createState() => _EditorFaixaScreenState();
}

class _EditorFaixaScreenState extends State<_EditorFaixaScreen> {
  final _sb = Supabase.instance.client;
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _corInicio;
  late final TextEditingController _corFim;
  late final TextEditingController _cozinha;
  late String _tipo;
  String? _destino;
  String? _nomeProduto;
  String? _imagemUrl;
  late bool _ativo;
  late bool _patrocinado;
  String? _parceiroId;
  DateTime? _inicio; // instante UTC
  DateTime? _fim; // instante UTC
  bool _enviandoImagem = false;
  bool _gravando = false;
  List<Map<String, dynamic>> _codigos = const [];

  bool get _nova => widget.faixa == null;

  @override
  void initState() {
    super.initState();
    final f = widget.faixa ?? const <String, dynamic>{};
    _titulo = TextEditingController(text: '${f['titulo'] ?? ''}');
    _subtitulo = TextEditingController(text: '${f['subtitulo'] ?? ''}');
    _corInicio = TextEditingController(text: '${f['cor_inicio'] ?? '#16A34A'}');
    _corFim = TextEditingController(text: '${f['cor_fim'] ?? '#15803D'}');
    _tipo = _tiposDestino.containsKey(f['tipo_destino'])
        ? f['tipo_destino'] as String
        : 'nenhum';
    _destino = f['destino'] as String?;
    _cozinha =
        TextEditingController(text: _tipo == 'cozinha' ? (_destino ?? '') : '');
    _imagemUrl = f['imagem_url'] as String?;
    _ativo = f['ativo'] != false;
    _patrocinado = f['patrocinado'] == true;
    _parceiroId = f['parceiro_id'] as String?;
    _inicio = DateTime.tryParse('${f['inicio'] ?? ''}');
    _fim = DateTime.tryParse('${f['fim'] ?? ''}');
    _carregarCodigos();
    if (_tipo == 'produto' && _destino != null) _carregarNomeProduto();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _subtitulo.dispose();
    _corInicio.dispose();
    _corFim.dispose();
    _cozinha.dispose();
    super.dispose();
  }

  Future<void> _carregarCodigos() async {
    try {
      // Só leitura dos códigos promocionais (nunca se escreve em promo_codes).
      final res = await _sb.rpc('admin_list_promo_codes', params: {
        'p_active_only': false,
        'p_search': null,
        'p_limit': 200,
        'p_offset': 0,
      });
      final lista = ((res as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _codigos = lista);
    } catch (e) {
      debugPrint('[AdminHomeBanners] codigos: $e');
    }
  }

  Future<void> _carregarNomeProduto() async {
    try {
      final p = await _sb
          .from('products')
          .select('id, name')
          .eq('id', _destino!)
          .maybeSingle();
      if (mounted && p != null) {
        setState(() => _nomeProduto = '${p['name'] ?? p['id']}');
      }
    } catch (e) {
      debugPrint('[AdminHomeBanners] produto: $e');
    }
  }

  Future<void> _escolherProduto() async {
    final busca = TextEditingController();
    List<Map<String, dynamic>> res = const [];
    var procurando = false;
    final escolhido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          Future<void> procurar() async {
            final q = busca.text.trim();
            if (q.length < 2) return;
            setSt(() => procurando = true);
            try {
              final rows = await _sb
                  .from('products')
                  .select('id, name, restaurant_id')
                  .ilike('name', '%$q%')
                  .order('name')
                  .limit(30);
              setSt(() => res = List<Map<String, dynamic>>.from(rows));
            } catch (e) {
              debugPrint('[AdminHomeBanners] busca produto: $e');
            } finally {
              setSt(() => procurando = false);
            }
          }

          return AlertDialog(
            title: const Text('Escolher produto'),
            content: SizedBox(
              width: 420,
              height: 380,
              child: Column(children: [
                TextField(
                  controller: busca,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => procurar(),
                  decoration: InputDecoration(
                    labelText: 'Nome do produto (mín. 2 letras)',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.search), onPressed: procurar),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: procurando
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(children: [
                          for (final p in res)
                            ListTile(
                              dense: true,
                              title: Text('${p['name'] ?? p['id']}'),
                              subtitle: Text('Loja: ${p['restaurant_id'] ?? '—'}',
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.pop(ctx, p),
                            ),
                        ]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
    // O controlador não se descarta aqui: o diálogo ainda está a fechar
    // (animação) e usá-lo depois de dispose rebenta.
    if (escolhido == null || !mounted) return;
    setState(() {
      _destino = '${escolhido['id']}';
      _nomeProduto = '${escolhido['name'] ?? escolhido['id']}';
    });
  }

  Future<void> _enviarImagem() async {
    final file = await SafeImagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Imagem muito grande (máx 8 MB).')));
      return;
    }
    var ext = file.name.split('.').last.toLowerCase();
    if (ext == 'jpg') ext = 'jpeg';
    if (!['jpeg', 'png', 'webp'].contains(ext)) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Formato inválido. Use JPEG, PNG ou WebP.')));
      return;
    }
    setState(() => _enviandoImagem = true);
    try {
      // Mesmo caminho do ecrã do parceiro (admin_partner_detail_screen):
      // Edge `upload-restaurant-asset`. Admin pode usar qualquer pasta;
      // as faixas ficam em restaurant-assets/home-banners/.
      final response = await _sb.functions.invoke(
        'upload-restaurant-asset',
        body: {
          'restaurantId': 'home-banners',
          'kind': 'banner',
          'fileBase64': base64Encode(bytes),
          'contentType': 'image/$ext',
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw Exception(
            'upload-restaurant-asset HTTP ${response.status}: ${response.data}');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) {
        throw Exception('Upload falhou: ${data['error'] ?? 'unknown'}');
      }
      if (!mounted) return;
      setState(() => _imagemUrl = data['public_url'] as String);
      messenger.showSnackBar(
          const SnackBar(content: Text('Imagem enviada. Falta salvar.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Erro ao enviar imagem: $e')));
    } finally {
      if (mounted) setState(() => _enviandoImagem = false);
    }
  }

  Future<void> _escolherData({required bool inicio}) async {
    final atual = inicio ? _inicio : _fim;
    final base = horaLisboa(atual ?? DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (d == null) return;
    setState(() {
      if (inicio) {
        // 00:00 de Lisboa desse dia.
        _inicio = inicioDiaLisboaUtc(DateTime.utc(d.year, d.month, d.day, 12));
      } else {
        // 23:59:59 de Lisboa desse dia.
        _fim = inicioDiaLisboaUtc(DateTime.utc(d.year, d.month, d.day + 1, 12))
            .subtract(const Duration(seconds: 1));
      }
    });
  }

  String? _validar() {
    if (_titulo.text.trim().isEmpty) return 'Falta o título.';
    if (!_hexRe.hasMatch(_corInicio.text.trim()) ||
        !_hexRe.hasMatch(_corFim.text.trim())) {
      return 'As cores têm de ser no formato #RRGGBB (ex.: #16A34A).';
    }
    if (_tipo == 'cozinha' && _cozinha.text.trim().isEmpty) {
      return 'Escreva a cozinha (ex.: sushi).';
    }
    if (_tipo != 'nenhum' && _tipo != 'cozinha' && (_destino ?? '').isEmpty) {
      return 'Escolha o destino da faixa.';
    }
    if (_inicio != null && _fim != null && !_fim!.isAfter(_inicio!)) {
      return 'A data de fim tem de ser depois do início.';
    }
    if (_patrocinado && (_parceiroId ?? '').isEmpty) {
      return 'Faixa patrocinada precisa do parceiro que paga.';
    }
    return null;
  }

  Future<void> _salvar() async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = _validar();
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    final destino = switch (_tipo) {
      'nenhum' => null,
      'cozinha' => _cozinha.text.trim().toLowerCase(),
      _ => _destino,
    };
    final dados = <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'subtitulo':
          _subtitulo.text.trim().isEmpty ? null : _subtitulo.text.trim(),
      'imagem_url': (_imagemUrl ?? '').isEmpty ? null : _imagemUrl,
      'cor_inicio': _corInicio.text.trim().toUpperCase(),
      'cor_fim': _corFim.text.trim().toUpperCase(),
      'tipo_destino': _tipo,
      'destino': destino,
      'ativo': _ativo,
      'inicio': _inicio?.toUtc().toIso8601String(),
      'fim': _fim?.toUtc().toIso8601String(),
      'patrocinado': _patrocinado,
      'parceiro_id': _patrocinado ? _parceiroId : null,
    };
    setState(() => _gravando = true);
    try {
      if (_nova) {
        dados['ordem'] = widget.ordemNova;
        final row = await _sb
            .from('home_banners')
            .insert(dados)
            .select('id')
            .single();
        await _logFaixa('faixa_criada', '${row['id']}', {'depois': dados});
      } else {
        final f = widget.faixa!;
        dados['atualizado_em'] = DateTime.now().toUtc().toIso8601String();
        await _sb.from('home_banners').update(dados).eq('id', f['id']);
        await _logFaixa('faixa_editada', '${f['id']}', {
          'antes': {for (final k in dados.keys) k: f[k]},
          'depois': dados,
        });
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Faixa gravada.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[AdminHomeBanners] salvar: $e');
      messenger.showSnackBar(
          SnackBar(content: Text('Não consegui gravar a faixa: $e')));
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Widget _campoCor(String rotulo, TextEditingController c) {
    final valida = _hexRe.hasMatch(c.text.trim());
    return Expanded(
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _corHex(c.text, Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: rotulo,
              hintText: '#16A34A',
              errorText: valida ? null : 'Formato #RRGGBB',
            ),
          ),
        ),
      ]),
    );
  }

  Widget _seletorDestino() {
    switch (_tipo) {
      case 'loja':
        return AdminEscolherLoja(
          valor: _destino,
          onEscolhida: (v) => setState(() => _destino = v),
        );
      case 'produto':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_nomeProduto ?? _destino ?? 'Nenhum produto escolhido'),
          subtitle: _destino == null ? null : Text('id: $_destino'),
          trailing: OutlinedButton.icon(
            onPressed: _escolherProduto,
            icon: const Icon(Icons.search),
            label: const Text('Procurar'),
          ),
        );
      case 'cozinha':
        return TextField(
          controller: _cozinha,
          decoration: const InputDecoration(
            labelText: 'Cozinha (tipo de comida)',
            hintText: 'ex.: sushi, pizza, hamburguer',
          ),
        );
      case 'categoria':
        return DropdownButtonFormField<String>(
          key: const ValueKey('categoria'),
          initialValue: _categorias.containsKey(_destino) ? _destino : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: [
            for (final e in _categorias.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _destino = v),
        );
      case 'codigo':
        final codigos = [
          for (final c in _codigos)
            if ('${c['code'] ?? ''}'.isNotEmpty) c,
        ];
        return DropdownButtonFormField<String>(
          key: ValueKey('codigo_${codigos.length}'),
          initialValue:
              codigos.any((c) => c['code'] == _destino) ? _destino : null,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Código promocional (só os que já existem)'),
          items: [
            for (final c in codigos)
              DropdownMenuItem(
                value: '${c['code']}',
                child: Text(
                    '${c['code']}${c['is_active'] == false ? ' (desligado)' : ''}'),
              ),
          ],
          onChanged: (v) => setState(() => _destino = v),
        );
      default:
        return const Text('A faixa só mostra a mensagem; tocar não abre nada.',
            style: TextStyle(color: AppColors.textSecondary));
    }
  }

  Widget _linhaData(String rotulo, DateTime? valor, bool inicio) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(rotulo),
      subtitle: Text(valor == null
          ? (inicio ? 'Já (sem data de início)' : 'Sem fim')
          : '${dataHoraLisboa(valor.toIso8601String())} (hora de Lisboa)'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: 'Escolher data',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => _escolherData(inicio: inicio)),
        if (valor != null)
          IconButton(
              tooltip: 'Tirar data',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                    if (inicio) {
                      _inicio = null;
                    } else {
                      _fim = null;
                    }
                  })),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const secao = TextStyle(fontWeight: FontWeight.bold, fontSize: 15);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: _nova ? 'Nova faixa' : 'Editar faixa'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Como o cliente vê', style: secao),
        const SizedBox(height: 8),
        HomeBannerPreview(
          titulo: _titulo.text.trim(),
          subtitulo: _subtitulo.text.trim(),
          imagemUrl: _imagemUrl,
          corInicio: _corInicio.text.trim(),
          corFim: _corFim.text.trim(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titulo,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Título *'),
        ),
        TextField(
          controller: _subtitulo,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Subtítulo (opcional)'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _campoCor('Cor de início', _corInicio),
          const SizedBox(width: 12),
          _campoCor('Cor de fim', _corFim),
        ]),
        const SizedBox(height: 16),
        const Text('Imagem de fundo (opcional)', style: secao),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _enviandoImagem ? null : _enviarImagem,
            icon: _enviandoImagem
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined),
            label: Text((_imagemUrl ?? '').isEmpty
                ? 'Enviar imagem'
                : 'Trocar imagem'),
          ),
          if ((_imagemUrl ?? '').isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => setState(() => _imagemUrl = null),
              icon: const Icon(Icons.hide_image_outlined),
              label: const Text('Tirar imagem'),
            ),
        ]),
        const SizedBox(height: 16),
        const Text('Para onde vai quando o cliente toca', style: secao),
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tipo de destino'),
          items: [
            for (final e in _tiposDestino.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() {
            if (v == null || v == _tipo) return;
            _tipo = v;
            _destino = null;
            _nomeProduto = null;
          }),
        ),
        const SizedBox(height: 8),
        _seletorDestino(),
        const SizedBox(height: 16),
        const Text('Quando aparece', style: secao),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativa'),
          subtitle: const Text('Desligada = não aparece a ninguém.'),
          value: _ativo,
          onChanged: (v) => setState(() => _ativo = v),
        ),
        _linhaData('Início', _inicio, true),
        _linhaData('Fim', _fim, false),
        const SizedBox(height: 8),
        const Text('Patrocínio', style: secao),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Patrocinada'),
          subtitle: const Text(
              'Faixa paga por um parceiro (fica marcada como patrocinada).'),
          value: _patrocinado,
          onChanged: (v) => setState(() => _patrocinado = v),
        ),
        if (_patrocinado) ...[
          const Text('Parceiro que paga a faixa',
              style: TextStyle(color: AppColors.textSecondary)),
          AdminEscolherLoja(
            valor: _parceiroId,
            onEscolhida: (v) => setState(() => _parceiroId = v),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _gravando ? null : _salvar,
          icon: _gravando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: const Text('Salvar faixa'),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
