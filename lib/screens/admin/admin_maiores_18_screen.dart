// Missão maiores-18 (07/10/2026) — painel admin (PT-BR).
//
// Três abas:
//   Produtos      → admin_list_products_maior_18 (busca + filtro, paginado);
//                   toggle por linha via admin_set_product_age_restricted.
//   Por categoria → admin_maior_18_por_categoria; "Marcar todos"/"Desmarcar
//                   todos" por linha via admin_set_age_restricted_by_category.
//   Verificações  → order_age_checks (select direto; o admin tem policy).
//
// Só lê e chama as RPCs admin_* da migration
// `20261007180000_maiores_18_verificacao_idade.sql`. Não toca em dinheiro.
import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import 'admin_order_detail_screen.dart';

class AdminMaiores18Screen extends StatelessWidget {
  const AdminMaiores18Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const BoraScreenAppBar(
          title: 'Maiores de 18',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Produtos'),
              Tab(text: 'Por categoria'),
              Tab(text: 'Verificações'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProdutosTab(),
            _PorCategoriaTab(),
            _VerificacoesTab(),
          ],
        ),
      ),
    );
  }
}

// ── Aba 1 — Produtos ─────────────────────────────────────────────────────────

class _ProdutosTab extends StatefulWidget {
  const _ProdutosTab();

  @override
  State<_ProdutosTab> createState() => _ProdutosTabState();
}

class _ProdutosTabState extends State<_ProdutosTab> {
  static const _pageSize = 50;

  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _filtro = 'marcados'; // marcados | desmarcados | sugeridos | todos
  int _offset = 0;
  int _total = 0;
  bool _loading = false;
  String? _erro;
  List<Map<String, dynamic>> _rows = const [];
  final Set<String> _aGravar = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_list_products_maior_18',
        params: {
          'p_search': _buscaCtrl.text.trim().isEmpty
              ? null
              : _buscaCtrl.text.trim(),
          'p_filtro': _filtro,
          'p_limit': _pageSize,
          'p_offset': _offset,
        },
      );
      if (!mounted) return;
      final rows = ((res as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _rows = rows;
        _total = rows.isEmpty ? 0 : ((rows.first['total'] as num?)?.toInt() ?? 0);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = humanizeAdminRpcError(e);
      });
    }
  }

  void _onBusca(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _offset = 0;
      _load();
    });
  }

  Future<void> _toggle(Map<String, dynamic> row, bool value) async {
    final id = row['id'] as String;
    setState(() => _aGravar.add(id));
    try {
      await Supabase.instance.client.rpc(
        'admin_set_product_age_restricted',
        params: {
          'p_product_id': id,
          'p_value': value,
          'p_reason': 'painel admin — Maiores de 18',
        },
      );
      if (!mounted) return;
      setState(() => row['age_restricted'] = value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeAdminRpcError(e))));
    } finally {
      if (mounted) setState(() => _aGravar.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginas = _total == 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;
    final pagina = (_offset ~/ _pageSize) + 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _buscaCtrl,
            onChanged: _onBusca,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar produto ou loja',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _buscaCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscaCtrl.clear();
                        _onBusca('');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in const [
                  ('marcados', 'Marcados'),
                  ('desmarcados', 'Não marcados'),
                  ('sugeridos', 'Sugeridos'),
                  ('todos', 'Todos'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filtro == f.$1,
                      onSelected: (_) {
                        setState(() {
                          _filtro = f.$1;
                          _offset = 0;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Text('$_total produto(s)',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              IconButton(
                tooltip: 'Página anterior',
                onPressed: _offset == 0 || _loading
                    ? null
                    : () {
                        setState(() => _offset -= _pageSize);
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$pagina / $paginas'),
              IconButton(
                tooltip: 'Próxima página',
                onPressed: pagina >= paginas || _loading
                    ? null
                    : () {
                        setState(() => _offset += _pageSize);
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? _Erro(texto: _erro!, onRetry: _load)
                  : _rows.isEmpty
                      ? const Center(
                          child: Text('Nenhum produto neste filtro.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => _ProdutoLinha(
                              row: _rows[i],
                              gravando: _aGravar.contains(_rows[i]['id']),
                              onToggle: (v) => _toggle(_rows[i], v),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _ProdutoLinha extends StatelessWidget {
  const _ProdutoLinha({
    required this.row,
    required this.gravando,
    required this.onToggle,
  });

  final Map<String, dynamic> row;
  final bool gravando;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final marcado = row['age_restricted'] == true;
    final sugerido = row['sugerido'] == true;
    final foto = (row['photo_url'] ?? '').toString();
    final categoria = [
      row['taxonomy_section'],
      row['category_root'],
      row['category'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' › ');
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: foto.isEmpty
              ? Container(
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.image_outlined, color: Colors.grey))
              : Image.network(foto, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF0F0F0),
                      child: const Icon(Icons.image_outlined,
                          color: Colors.grey))),
        ),
      ),
      title: Text('${row['name'] ?? ''}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if ((row['loja'] ?? '').toString().isNotEmpty) row['loja'],
          if (categoria.isNotEmpty) categoria,
          if (sugerido && !marcado) 'sugerido pelo classificador',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: gravando
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(
              value: marcado,
              activeColor: Colors.black,
              onChanged: onToggle,
            ),
    );
  }
}

// ── Aba 2 — Por categoria ────────────────────────────────────────────────────

class _PorCategoriaTab extends StatefulWidget {
  const _PorCategoriaTab();

  @override
  State<_PorCategoriaTab> createState() => _PorCategoriaTabState();
}

class _PorCategoriaTabState extends State<_PorCategoriaTab> {
  bool _loading = false;
  String? _erro;
  List<Map<String, dynamic>> _rows = const [];
  final Set<String> _aGravar = <String>{};

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
      final res =
          await Supabase.instance.client.rpc('admin_maior_18_por_categoria');
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = humanizeAdminRpcError(e);
      });
    }
  }

  String _chave(Map<String, dynamic> r) =>
      '${r['taxonomy_section']}|${r['category_root']}';

  Future<void> _marcar(Map<String, dynamic> r, bool valor) async {
    final root = (r['category_root'] ?? '').toString();
    final acao = valor ? 'Marcar todos' : 'Desmarcar todos';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$acao como +18?'),
        content: Text(
            'Categoria "$root" (${r['total']} produtos). Fica registrado no histórico de ações.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(acao)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final k = _chave(r);
    setState(() => _aGravar.add(k));
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_set_age_restricted_by_category',
        params: {
          'p_field': 'category_root',
          'p_value': root,
          'p_age': valor,
          'p_reason': 'painel admin — Maiores de 18 (por categoria)',
        },
      );
      if (!mounted) return;
      final n = res is Map ? (res['updated'] ?? 0) : 0;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n produto(s) atualizado(s).')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeAdminRpcError(e))));
    } finally {
      if (mounted) setState(() => _aGravar.remove(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_erro != null) return _Erro(texto: _erro!, onRetry: _load);
    if (_rows.isEmpty) {
      return const Center(child: Text('Nenhuma categoria com produtos +18.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final total = (r['total'] as num?)?.toInt() ?? 0;
          final marcados = (r['marcados'] as num?)?.toInt() ?? 0;
          final gravando = _aGravar.contains(_chave(r));
          return ListTile(
            title: Text('${r['category_root'] ?? '—'}'),
            subtitle: Text(
                '${r['taxonomy_section'] ?? '—'} · $marcados de $total marcados'),
            trailing: gravando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: marcados == total
                            ? null
                            : () => _marcar(r, true),
                        child: const Text('Marcar todos'),
                      ),
                      TextButton(
                        onPressed:
                            marcados == 0 ? null : () => _marcar(r, false),
                        child: const Text('Desmarcar todos'),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// ── Aba 3 — Verificações ─────────────────────────────────────────────────────

class _VerificacoesTab extends StatefulWidget {
  const _VerificacoesTab();

  @override
  State<_VerificacoesTab> createState() => _VerificacoesTabState();
}

class _VerificacoesTabState extends State<_VerificacoesTab> {
  bool _loading = false;
  String? _erro;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, String> _nomes = const {};

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
      final res = await Supabase.instance.client
          .from('order_age_checks')
          .select(
              'order_id, status, checked_at, driver_uid, order_status_at_check, service_type, cancellation_request_id')
          .order('checked_at', ascending: false)
          .limit(200);
      final rows = List<Map<String, dynamic>>.from(res);
      // Nome do estafeta (drivers.user_id manda — regra de identidade).
      final uids = rows
          .map((r) => r['driver_uid']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      var nomes = <String, String>{};
      if (uids.isNotEmpty) {
        try {
          final d = await Supabase.instance.client
              .from('drivers')
              .select('user_id, name')
              .inFilter('user_id', uids);
          nomes = {
            for (final x in List<Map<String, dynamic>>.from(d))
              x['user_id'].toString(): (x['name'] ?? '').toString(),
          };
        } catch (e) {
          debugPrint('[AdminMaiores18] nomes: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _nomes = nomes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = humanizeAdminRpcError(e);
      });
    }
  }

  static String _fmt(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_erro != null) return _Erro(texto: _erro!, onRetry: _load);
    if (_rows.isEmpty) {
      return const Center(child: Text('Ainda não houve verificações.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final recusado = r['status'] == 'recusado';
          final orderId = r['order_id'].toString();
          final uid = r['driver_uid']?.toString() ?? '';
          final nome = _nomes[uid]?.trim().isNotEmpty == true
              ? _nomes[uid]!
              : (uid.length >= 8 ? uid.substring(0, 8) : uid);
          return ListTile(
            leading: Icon(
              recusado ? Icons.block : Icons.verified_user,
              color: recusado ? Colors.red.shade700 : AppColors.primary,
            ),
            title: Text(
                'Pedido #${orderId.length >= 8 ? orderId.substring(0, 8) : orderId} · ${recusado ? 'Recusado' : 'Confirmado'}'),
            subtitle: Text(
              '$nome · ${_fmt(r['checked_at'])}'
              '${r['service_type'] != null ? ' · ${r['service_type']}' : ''}'
              '${recusado && r['cancellation_request_id'] != null ? ' · cancelamento aberto' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminOrderDetailScreen(orderId: orderId),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.texto, required this.onRetry});
  final String texto;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
