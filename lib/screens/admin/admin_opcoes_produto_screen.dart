// Opções/variantes de produto por loja (ronda 04/10/2026, agente admin-geral).
// O parceiro gere as opções (tamanho, extras, molhos) na app dele; o painel não
// as via. Aqui: escolher a loja, ver os grupos de opções de cada produto e
// editar um item (nome, disponível, acréscimo €) — admin_opcao_item_atualizar,
// com auditoria antes/depois.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Escolha de loja reutilizada pelos ecrãs simples (opções, mesas).
class AdminEscolherLoja extends StatefulWidget {
  const AdminEscolherLoja({super.key, required this.onEscolhida, this.valor});
  final ValueChanged<String?> onEscolhida;
  final String? valor;

  @override
  State<AdminEscolherLoja> createState() => _AdminEscolherLojaState();
}

class _AdminEscolherLojaState extends State<AdminEscolherLoja> {
  List<Map<String, dynamic>> _lojas = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('restaurants')
          .select('id, name')
          .order('name')
          .limit(1000);
      if (!mounted) return;
      setState(() => _lojas = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('[AdminEscolherLoja] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _lojas.any((l) => l['id'] == widget.valor) ? widget.valor : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Loja'),
      items: [
        for (final l in _lojas)
          DropdownMenuItem(
            value: l['id'] as String,
            child: Text('${l['name'] ?? l['id']}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.onEscolhida,
    );
  }
}

class AdminOpcoesProdutoScreen extends StatefulWidget {
  const AdminOpcoesProdutoScreen({super.key});

  @override
  State<AdminOpcoesProdutoScreen> createState() =>
      _AdminOpcoesProdutoScreenState();
}

class _AdminOpcoesProdutoScreenState extends State<AdminOpcoesProdutoScreen> {
  String? _loja;
  List<Map<String, dynamic>> _grupos = const [];
  bool _loading = false;
  String _filtro = '';

  Future<void> _load() async {
    final loja = _loja;
    if (loja == null) return;
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .rpc('admin_opcoes_loja', params: {'p_restaurant_id': loja});
      if (!mounted) return;
      setState(() {
        _grupos = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminOpcoesProduto] $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui carregar as opções.')));
    }
  }

  Future<void> _editar(Map<String, dynamic> item) async {
    final nome = TextEditingController(text: '${item['name'] ?? ''}');
    final preco = TextEditingController(
        text: ((item['price_add'] as num?) ?? 0).toStringAsFixed(2));
    var disp = item['is_available'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Editar opção'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nome,
                decoration: const InputDecoration(labelText: 'Nome')),
            TextField(
              controller: preco,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Acréscimo (€)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponível'),
              value: disp,
              onChanged: (v) => setSt(() => disp = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final novoNome = nome.text.trim();
    final novoPreco = double.tryParse(preco.text.trim().replaceAll(',', '.'));
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await Supabase.instance.client
          .rpc('admin_opcao_item_atualizar', params: {
        'p_item_id': item['id'],
        'p_name': novoNome,
        'p_price_add': novoPreco,
        'p_is_available': disp,
      });
      final m = (res is Map) ? res : const {};
      messenger.showSnackBar(SnackBar(
          content: Text(m['ok'] == true
              ? 'Opção gravada.'
              : (m['erro']?.toString() ?? 'Não consegui gravar.'))));
      await _load();
    } catch (e) {
      debugPrint('[AdminOpcoesProduto] editar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui gravar.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtro.toLowerCase();
    final grupos = f.isEmpty
        ? _grupos
        : _grupos
            .where((g) => '${g['produto']} ${g['name']}'
                .toLowerCase()
                .contains(f))
            .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Opções de produto',
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loja == null ? null : _load),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AdminEscolherLoja(
            valor: _loja,
            onEscolhida: (v) {
              setState(() => _loja = v);
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Procurar produto ou grupo'),
            onChanged: (v) => setState(() => _filtro = v),
          ),
        ),
        Expanded(
          child: _loja == null
              ? const Center(child: Text('Escolha uma loja.'))
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : grupos.isEmpty
                      ? const Center(child: Text('Esta loja não tem opções.'))
                      : ListView.builder(
                          itemCount: grupos.length,
                          itemBuilder: (_, i) {
                            final g = grupos[i];
                            final itens = ((g['itens'] as List?) ?? const [])
                                .map((e) => Map<String, dynamic>.from(e as Map))
                                .toList();
                            return ExpansionTile(
                              title: Text('${g['produto']} — ${g['name']}'),
                              subtitle: Text(
                                  '${g['is_required'] == true ? 'Obrigatório' : 'Opcional'} · '
                                  'escolher ${g['min_choices'] ?? 0} a ${g['max_choices'] ?? '—'} · '
                                  '${itens.length} opções'),
                              children: [
                                for (final it in itens)
                                  ListTile(
                                    dense: true,
                                    title: Text('${it['name']}',
                                        style: TextStyle(
                                            decoration: it['is_available'] == false
                                                ? TextDecoration.lineThrough
                                                : null)),
                                    subtitle: it['is_available'] == false
                                        ? const Text('Indisponível')
                                        : null,
                                    trailing: Text(
                                        '+€${((it['price_add'] as num?) ?? 0).toStringAsFixed(2)}'),
                                    onTap: () => _editar(it),
                                  ),
                              ],
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
