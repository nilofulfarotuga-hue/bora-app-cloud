// Bloco D (2026-09-05) — painel admin PT-BR das correções de preço por talão
// e do estado das imagens do catálogo.
//
// Aba 1 — Correções de preço: ver, aprovar, rejeitar e reverter o que o OCR
//         propôs a partir do talão. As três ações chamam RPCs que já auditam
//         em `admin_audit_log` (entity_id_text, porque `products.id` é TEXT).
// Aba 2 — Imagens: produtos sem foto ou com foto fora do Storage, por loja.
//         Nasceu da queixa da cliente Letícia (05/09): as fotos apontavam para
//         CDNs de terceiros que bloqueiam hotlink e a loja aparecia vazia.
//
// Idioma PT-BR: é painel admin, só o Danilo usa.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

class AdminCorrecoesPrecoScreen extends StatefulWidget {
  const AdminCorrecoesPrecoScreen({super.key});

  @override
  State<AdminCorrecoesPrecoScreen> createState() =>
      _AdminCorrecoesPrecoScreenState();
}

class _AdminCorrecoesPrecoScreenState extends State<AdminCorrecoesPrecoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preços por talão'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.price_change_outlined), text: 'Correções'),
            Tab(icon: Icon(Icons.image_outlined), text: 'Imagens'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_AbaCorrecoes(), _AbaImagens()],
      ),
    );
  }
}

// ───────────────────────── Aba 1 — correções de preço ─────────────────────

class _AbaCorrecoes extends StatefulWidget {
  const _AbaCorrecoes();

  @override
  State<_AbaCorrecoes> createState() => _AbaCorrecoesState();
}

class _AbaCorrecoesState extends State<_AbaCorrecoes> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _linhas = [];
  List<String> _lojas = [];
  String? _lojaFiltro;
  String _statusFiltro = 'pending';
  bool _carregando = true;
  String? _erro;
  String? _aTratar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var q = _supabase
          .from('catalog_price_updates')
          .select('id, product_id, restaurant_id, order_id, receipt_id, '
              'old_base, new_base, confianca, linha_talao, status, '
              'created_at, decided_at');

      if (_statusFiltro != 'todos') q = q.eq('status', _statusFiltro);
      if (_lojaFiltro != null) q = q.eq('restaurant_id', _lojaFiltro!);

      final dados = await q.order('created_at', ascending: false).limit(300);
      final linhas = List<Map<String, dynamic>>.from(dados);

      // nomes dos produtos numa só ida à base
      final ids = linhas.map((l) => l['product_id'] as String).toSet().toList();
      final nomes = <String, String>{};
      if (ids.isNotEmpty) {
        final prods = await _supabase
            .from('products')
            .select('id, name')
            .inFilter('id', ids);
        for (final p in List<Map<String, dynamic>>.from(prods)) {
          nomes[p['id'] as String] = (p['name'] as String?) ?? '(sem nome)';
        }
      }
      for (final l in linhas) {
        l['_nome'] = nomes[l['product_id']] ?? l['product_id'];
      }

      final todasLojas = await _supabase
          .from('catalog_price_updates')
          .select('restaurant_id');
      final setLojas = <String>{};
      for (final r in List<Map<String, dynamic>>.from(todasLojas)) {
        final v = r['restaurant_id'] as String?;
        if (v != null && v.isNotEmpty) setLojas.add(v);
      }

      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _lojas = setLojas.toList()..sort();
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

  Future<void> _acao(String rpc, Map<String, dynamic> linha, String feito) async {
    setState(() => _aTratar = linha['id'] as String);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await _supabase
          .rpc(rpc, params: {'p_update_id': linha['id']}) as Map<String, dynamic>;
      if (r['ok'] == true) {
        messenger.showSnackBar(SnackBar(content: Text('$feito ✅')));
        await _carregar();
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text('Não deu: ${r['error'] ?? 'erro'}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _aTratar = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Erro ao carregar: $_erro'),
      ));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Situação',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pendentes')),
                    DropdownMenuItem(value: 'applied', child: Text('Aplicadas')),
                    DropdownMenuItem(value: 'approved', child: Text('Aprovadas')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejeitadas')),
                    DropdownMenuItem(value: 'reverted', child: Text('Revertidas')),
                    DropdownMenuItem(value: 'todos', child: Text('Todas')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFiltro = v ?? 'pending');
                    _carregar();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _lojaFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Loja',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todas')),
                    ..._lojas.map((l) =>
                        DropdownMenuItem<String?>(value: l, child: Text(l))),
                  ],
                  onChanged: (v) {
                    setState(() => _lojaFiltro = v);
                    _carregar();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _linhas.isEmpty
              ? const Center(child: Text('Nada aqui. Fila limpa.'))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _linhas.length,
                    itemBuilder: (_, i) => _cartao(_linhas[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _cartao(Map<String, dynamic> l) {
    final velho = (l['old_base'] as num?)?.toDouble() ?? 0;
    final novo = (l['new_base'] as num?)?.toDouble() ?? 0;
    final subiu = novo > velho;
    final status = l['status'] as String? ?? '';
    final ocupado = _aTratar == l['id'];
    final conf = (l['confianca'] as num?)?.toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(subiu ? Icons.trending_up : Icons.trending_down,
                    color: subiu ? Colors.red.shade700 : Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l['_nome'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(status, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '€${velho.toStringAsFixed(2)}  →  €${novo.toStringAsFixed(2)}'
              '${subiu ? '   (talão MAIS CARO que o catálogo)' : '   (talão mais barato)'}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: subiu ? Colors.red.shade700 : Colors.green.shade800,
              ),
            ),
            const SizedBox(height: 4),
            Text('Loja: ${l['restaurant_id'] ?? '—'}',
                style: const TextStyle(fontSize: 12)),
            if (l['linha_talao'] != null)
              Text('Linha do talão: "${l['linha_talao']}"',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (conf != null)
              Text('Confiança do match: ${(conf * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text('Pedido: ${l['order_id'] ?? '—'}',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 8),
            if (ocupado)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  if (status == 'pending') ...[
                    FilledButton.icon(
                      onPressed: () => _acao('admin_approve_catalog_price_update',
                          l, 'Preço aprovado'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aprovar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _acao('admin_rejeitar_catalog_price_update',
                          l, 'Sugestão rejeitada'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rejeitar'),
                    ),
                  ],
                  if (status == 'applied' || status == 'approved')
                    OutlinedButton.icon(
                      onPressed: () => _acao('admin_revert_catalog_price_update',
                          l, 'Preço revertido'),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Reverter'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade800),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Aba 2 — estado das imagens ─────────────────────

class _AbaImagens extends StatefulWidget {
  const _AbaImagens();

  @override
  State<_AbaImagens> createState() => _AbaImagensState();
}

class _AbaImagensState extends State<_AbaImagens> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _lojas = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await _supabase.rpc('admin_estado_imagens_catalogo');
      if (!mounted) return;
      setState(() {
        _lojas = List<Map<String, dynamic>>.from(dados as List);
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

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Erro ao carregar: $_erro'),
      ));
    }
    if (_lojas.isEmpty) {
      return const Center(child: Text('Sem lojas para mostrar.'));
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _lojas.length,
        itemBuilder: (_, i) {
          final l = _lojas[i];
          final total = (l['total'] as num?)?.toInt() ?? 0;
          final ok = (l['no_storage'] as num?)?.toInt() ?? 0;
          final terceiros = (l['fora_do_storage'] as num?)?.toInt() ?? 0;
          final semFoto = (l['sem_foto'] as num?)?.toInt() ?? 0;
          final saudavel = terceiros == 0 && semFoto == 0;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                saudavel ? Icons.check_circle : Icons.warning_amber_rounded,
                color: saudavel ? AppColors.primary : Colors.orange.shade800,
              ),
              title: Text(
                (l['loja_nome'] as String?) ?? (l['restaurant_id'] as String),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$ok de $total no Storage'),
                  if (terceiros > 0)
                    Text('⚠️ $terceiros ainda apontam para fora (hotlink)',
                        style: TextStyle(color: Colors.red.shade700)),
                  if (semFoto > 0)
                    Text('📷 $semFoto sem foto nenhuma',
                        style: TextStyle(color: Colors.orange.shade800)),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
