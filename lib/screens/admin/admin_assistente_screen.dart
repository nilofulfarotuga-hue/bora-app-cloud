// BORA ASSISTENTE (07/10/2026) — painel admin do assistente de compras do
// cliente (PT-BR, só o Danilo usa).
//
// Separadores: Visão geral (interruptor + números do RPC
// admin_assistant_overview) · Conversas (com as mensagens) · Propostas ·
// Conhecimento (assistant_knowledge) · Lacunas (assistant_gaps) ·
// Correspondências (product_matches + canonical_products).
//
// O interruptor grava por `admin_update_setting('assistant_enabled', bool)`
// — o mesmo caminho das outras configurações do painel.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAssistenteScreen extends StatelessWidget {
  const AdminAssistenteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(
          title: 'Bora Assistente (cliente)',
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Visão geral'),
              Tab(text: 'Conversas'),
              Tab(text: 'Propostas'),
              Tab(text: 'Conhecimento'),
              Tab(text: 'Lacunas'),
              Tab(text: 'Correspondências'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VisaoGeralTab(),
            _ConversasTab(),
            _PropostasTab(),
            _ConhecimentoTab(),
            _LacunasTab(),
            _CorrespondenciasTab(),
          ],
        ),
      ),
    );
  }
}

SupabaseClient get _c => Supabase.instance.client;

String _dt(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  if (d == null) return '—';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)}';
}

String _eur(dynamic v) => '€${((v as num?) ?? 0).toStringAsFixed(2)}';
String _eurCents(dynamic v) => '€${(((v as num?) ?? 0) / 100).toStringAsFixed(2)}';
String _curto(dynamic v) {
  final s = v?.toString() ?? '';
  return s.length > 8 ? s.substring(0, 8) : s;
}

List<Map<String, dynamic>> _rows(dynamic r) => (r as List)
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Widget _erroWidget(String erro, VoidCallback tentar) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(erro, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(onPressed: tentar, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );

// ── Visão geral ──────────────────────────────────────────────────────────

class _VisaoGeralTab extends StatefulWidget {
  const _VisaoGeralTab();
  @override
  State<_VisaoGeralTab> createState() => _VisaoGeralTabState();
}

class _VisaoGeralTabState extends State<_VisaoGeralTab>
    with AutomaticKeepAliveClientMixin {
  int _dias = 30;
  bool _carregando = true;
  bool _gravando = false;
  String? _erro;
  Map<String, dynamic> _o = const {};

  @override
  bool get wantKeepAlive => true;

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
      final r = await _c.rpc('admin_assistant_overview', params: {'p_days': _dias});
      if (!mounted) return;
      setState(() {
        _o = r is Map ? Map<String, dynamic>.from(r) : const {};
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para carregar: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _ligar(bool v) async {
    setState(() => _gravando = true);
    try {
      await _c.rpc('admin_update_setting',
          params: {'p_key': 'assistant_enabled', 'p_value': v});
      if (!mounted) return;
      _snack(context, v ? 'Assistente ligado' : 'Assistente desligado');
      await _carregar();
    } catch (e) {
      if (mounted) _snack(context, 'Não deu para gravar: $e');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) return _erroWidget(_erro!, _carregar);
    final o = _o;
    final ligado = (o['enabled'] as bool?) ?? true;
    final emb = (o['embeddings_done'] as num?) ?? 0;
    final tot = (o['products_total'] as num?) ?? 0;
    final pct = tot > 0 ? (emb * 100 / tot) : 0.0;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              value: ligado,
              onChanged: _gravando ? null : _ligar,
              activeThumbColor: AppColors.primary,
              title: const Text('Assistente ligado para os clientes',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(ligado
                  ? 'O botão aparece no app e a Edge Function responde.'
                  : 'Desligado: o botão some do app e a função responde 503.'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Período:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              for (final d in const [7, 30, 90])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$d dias'),
                    selected: _dias == d,
                    onSelected: (_) {
                      setState(() => _dias = d);
                      _carregar();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Kpis(itens: [
            _Kpi('Conversas', '${o['conversations'] ?? 0}'),
            _Kpi('Mensagens', '${o['messages'] ?? 0}'),
            _Kpi('Clientes', '${o['users'] ?? 0}'),
            _Kpi('Propostas', '${o['proposals'] ?? 0}'),
            _Kpi('Abertas no carrinho', '${o['proposals_opened'] ?? 0}'),
            _Kpi('Viraram pedido', '${o['proposals_ordered'] ?? 0}'),
            _Kpi('Conversão', '${o['conversion_pct'] ?? 0}%'),
            _Kpi('Poupança mostrada', _eurCents(o['savings_shown_cents'])),
            _Kpi('Poupança realizada', _eurCents(o['savings_realized_cents'])),
            _Kpi('Custo total', 'US\$ ${((o['cost_usd'] as num?) ?? 0).toStringAsFixed(4)}'),
            _Kpi('Custo por conversa',
                'US\$ ${((o['cost_per_conversation_usd'] as num?) ?? 0).toStringAsFixed(5)}'),
            _Kpi('Tokens (entrada / saída)',
                '${o['tokens_in'] ?? 0} / ${o['tokens_out'] ?? 0}'),
            _Kpi('Passou ao humano', '${o['handoffs'] ?? 0}'),
            _Kpi('Lacunas abertas', '${o['gaps_open'] ?? 0}'),
            _Kpi('Embeddings', '$emb / $tot (${pct.toStringAsFixed(1)}%)'),
          ]),
        ],
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.rotulo, this.valor);
  final String rotulo;
  final String valor;
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.itens});
  final List<_Kpi> itens;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final k in itens)
          SizedBox(
            width: 170,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k.rotulo,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(k.valor,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Lista genérica (carrega uma vez, puxa para atualizar) ────────────────

class _ListaTab extends StatefulWidget {
  const _ListaTab({
    required this.carregar,
    required this.item,
    this.vazio = 'Nada por aqui.',
    this.acoes,
  });

  final Future<List<Map<String, dynamic>>> Function() carregar;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback recarregar) item;
  final String vazio;
  final List<Widget> Function(VoidCallback recarregar)? acoes;

  @override
  State<_ListaTab> createState() => _ListaTabState();
}

class _ListaTabState extends State<_ListaTab> with AutomaticKeepAliveClientMixin {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = const [];

  @override
  bool get wantKeepAlive => true;

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
      final l = await widget.carregar();
      if (!mounted) return;
      setState(() {
        _linhas = l;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para carregar: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) return _erroWidget(_erro!, _carregar);
    final acoes = widget.acoes?.call(_carregar) ?? const <Widget>[];
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (acoes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, children: acoes),
            ),
          if (_linhas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(widget.vazio,
                      style: const TextStyle(color: AppColors.textSecondary))),
            ),
          for (final l in _linhas) widget.item(context, l, _carregar),
        ],
      ),
    );
  }
}

Widget _chipStatus(String s) {
  Color cor;
  switch (s) {
    case 'ordered':
    case 'closed':
      cor = AppColors.primary;
    case 'opened':
    case 'open':
      cor = AppColors.info;
    case 'handoff':
    case 'expired':
      cor = AppColors.error;
    default:
      cor = AppColors.textSecondary;
  }
  const rotulos = {
    'proposed': 'proposta',
    'opened': 'aberta no carrinho',
    'ordered': 'virou pedido',
    'expired': 'expirou',
    'open': 'aberta',
    'closed': 'fechada',
    'handoff': 'passou ao humano',
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: cor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(rotulos[s] ?? s,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
  );
}

// ── Conversas ────────────────────────────────────────────────────────────

class _ConversasTab extends StatelessWidget {
  const _ConversasTab();

  @override
  Widget build(BuildContext context) {
    return _ListaTab(
      vazio: 'Ainda não há conversas.',
      carregar: () async => _rows(await _c
          .from('assistant_conversations')
          .select()
          .order('last_message_at', ascending: false)
          .limit(100)),
      item: (context, c, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
          title: Row(
            children: [
              Expanded(
                child: Text('Cliente ${_curto(c['user_id'])} · ${c['platform'] ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _chipStatus(c['status']?.toString() ?? ''),
            ],
          ),
          subtitle: Text(
            '${c['messages_count'] ?? 0} msgs · ${c['proposals_count'] ?? 0} propostas · '
            'poupança ${_eurCents(c['savings_shown_cents'])} · '
            'US\$ ${((c['cost_usd'] as num?) ?? 0).toStringAsFixed(4)} · '
            '${_dt(c['last_message_at'])}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _MensagensScreen(conversa: c),
            ),
          ),
        ),
      ),
    );
  }
}

class _MensagensScreen extends StatelessWidget {
  const _MensagensScreen({required this.conversa});
  final Map<String, dynamic> conversa;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Conversa ${_curto(conversa['id'])}'),
      body: _ListaTab(
        vazio: 'Sem mensagens.',
        carregar: () async => _rows(await _c
            .from('assistant_chat_messages')
            .select('role, content, tool_name, tool_input, structured, tokens_in, tokens_out, model, latency_ms, created_at')
            .eq('conversation_id', conversa['id'])
            .order('created_at', ascending: true)
            .limit(300)),
        item: (context, m, _) {
          final role = m['role']?.toString() ?? '';
          final doCliente = role == 'user';
          final st = m['structured'];
          final props = st is Map ? (st['propostas'] as List?) : null;
          return Align(
            alignment: doCliente ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: doCliente
                    ? AppColors.primaryLight
                    : role == 'assistant'
                        ? AppColors.surface
                        : AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role == 'tool'
                        ? 'ferramenta: ${m['tool_name'] ?? ''}'
                        : role,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if ((m['content']?.toString() ?? '').isNotEmpty)
                    Text(m['content'].toString()),
                  if (role == 'tool' && m['tool_input'] != null)
                    Text(m['tool_input'].toString(),
                        style: const TextStyle(fontSize: 11)),
                  if (props != null && props.isNotEmpty)
                    Text('${props.length} proposta(s) desenhada(s)',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.primaryDark)),
                  Text(
                    '${_dt(m['created_at'])} · ${m['model'] ?? ''} · '
                    '${m['tokens_in'] ?? 0}/${m['tokens_out'] ?? 0} tokens · '
                    '${m['latency_ms'] ?? 0} ms',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSubtle),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Propostas ────────────────────────────────────────────────────────────

class _PropostasTab extends StatelessWidget {
  const _PropostasTab();

  @override
  Widget build(BuildContext context) {
    return _ListaTab(
      vazio: 'Ainda não há propostas.',
      carregar: () async => _rows(await _c
          .from('assistant_cart_proposals')
          .select('id, user_id, restaurant_name, is_partner, service_type, items, coverage_pct, customer_total, savings_cents, rank, kind, status, order_id, created_at')
          .order('created_at', ascending: false)
          .limit(150)),
      item: (context, p, _) {
        final itens = (p['items'] as List?)?.length ?? 0;
        return Card(
          child: ListTile(
            leading: Icon(
              p['is_partner'] == true ? Icons.handshake_outlined : Icons.store_outlined,
              color: AppColors.primary,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${p['restaurant_name']} · ${_eur(p['customer_total'])}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _chipStatus(p['status']?.toString() ?? ''),
              ],
            ),
            subtitle: Text(
              '$itens itens · ${p['coverage_pct'] ?? 100}% da lista · '
              'poupança ${_eurCents(p['savings_cents'])} · ${p['kind']} #${p['rank']} · '
              'cliente ${_curto(p['user_id'])} · ${_dt(p['created_at'])}'
              '${p['order_id'] != null ? ' · pedido ${_curto(p['order_id'])}' : ''}',
            ),
          ),
        );
      },
    );
  }
}

// ── Conhecimento ─────────────────────────────────────────────────────────

class _ConhecimentoTab extends StatelessWidget {
  const _ConhecimentoTab();

  Future<void> _editar(BuildContext context, Map<String, dynamic>? k,
      VoidCallback recarregar) async {
    final topic = TextEditingController(text: k?['topic']?.toString() ?? '');
    final title = TextEditingController(text: k?['title']?.toString() ?? '');
    final content = TextEditingController(text: k?['content']?.toString() ?? '');
    final ordem = TextEditingController(text: '${k?['sort_order'] ?? 100}');
    var ativo = (k?['active'] as bool?) ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(k == null ? 'Novo texto' : 'Editar texto'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: topic,
                      decoration: const InputDecoration(labelText: 'Tema (chave curta, ex. favores)')),
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Título')),
                  TextField(
                      controller: content,
                      minLines: 4,
                      maxLines: 12,
                      decoration: const InputDecoration(
                          labelText: 'Conteúdo (o que o assistente pode dizer)')),
                  TextField(
                      controller: ordem,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Ordem')),
                  SwitchListTile(
                    value: ativo,
                    onChanged: (v) => setSt(() => ativo = v),
                    title: const Text('Ativo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (topic.text.trim().isEmpty || title.text.trim().isEmpty || content.text.trim().isEmpty) {
      if (context.mounted) _snack(context, 'Tema, título e conteúdo são obrigatórios.');
      return;
    }
    final dados = {
      'topic': topic.text.trim(),
      'title': title.text.trim(),
      'content': content.text.trim(),
      'sort_order': int.tryParse(ordem.text.trim()) ?? 100,
      'active': ativo,
      'updated_by': _c.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (k == null) {
        await _c.from('assistant_knowledge').insert(dados);
      } else {
        await _c.from('assistant_knowledge').update(dados).eq('id', k['id']);
      }
      if (context.mounted) _snack(context, 'Salvo');
      recarregar();
    } catch (e) {
      if (context.mounted) _snack(context, 'Não deu para salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ListaTab(
      vazio: 'Sem textos. Crie o primeiro.',
      carregar: () async => _rows(await _c
          .from('assistant_knowledge')
          .select()
          .order('sort_order', ascending: true)
          .order('title', ascending: true)),
      acoes: (recarregar) => [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => _editar(context, null, recarregar),
          icon: const Icon(Icons.add),
          label: const Text('Novo texto'),
        ),
      ],
      item: (context, k, recarregar) => Card(
        child: ListTile(
          leading: Switch(
            value: (k['active'] as bool?) ?? true,
            activeThumbColor: AppColors.primary,
            onChanged: (v) async {
              try {
                await _c.from('assistant_knowledge').update({'active': v}).eq('id', k['id']);
                recarregar();
              } catch (e) {
                if (context.mounted) _snack(context, 'Não deu para gravar: $e');
              }
            },
          ),
          title: Text('${k['title']}  ·  ${k['topic']}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(k['content']?.toString() ?? '',
              maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editar(context, k, recarregar),
          ),
        ),
      ),
    );
  }
}

// ── Lacunas (perguntas sem resposta) ─────────────────────────────────────

class _LacunasTab extends StatelessWidget {
  const _LacunasTab();

  @override
  Widget build(BuildContext context) {
    return _ListaTab(
      vazio: 'Nenhuma pergunta sem resposta. Bom sinal.',
      carregar: () async => _rows(await _c
          .from('assistant_gaps')
          .select()
          .order('resolved', ascending: true)
          .order('created_at', ascending: false)
          .limit(200)),
      item: (context, g, recarregar) {
        final resolvida = (g['resolved'] as bool?) ?? false;
        return Card(
          child: ListTile(
            leading: Icon(
              resolvida ? Icons.check_circle_outline : Icons.help_outline,
              color: resolvida ? AppColors.primary : AppColors.warning,
            ),
            title: Text(g['question']?.toString() ?? ''),
            subtitle: Text(
                '${g['reason'] ?? ''} · cliente ${_curto(g['user_id'])} · ${_dt(g['created_at'])}'),
            trailing: resolvida
                ? null
                : TextButton(
                    onPressed: () async {
                      try {
                        await _c.from('assistant_gaps').update({'resolved': true}).eq('id', g['id']);
                        recarregar();
                      } catch (e) {
                        if (context.mounted) _snack(context, 'Não deu para gravar: $e');
                      }
                    },
                    child: const Text('Resolver'),
                  ),
          ),
        );
      },
    );
  }
}

// ── Correspondências entre lojas ─────────────────────────────────────────

class _CorrespondenciasTab extends StatelessWidget {
  const _CorrespondenciasTab();

  @override
  Widget build(BuildContext context) {
    return _ListaTab(
      vazio: 'Ainda não há correspondências entre lojas.',
      carregar: () async => _rows(await _c
          .from('product_matches')
          .select('product_id, confidence, method, reviewed, created_at, canonical_products(canonical_name, brand, quantity, unit), products(name, restaurant_id, price)')
          .order('reviewed', ascending: true)
          .order('confidence', ascending: true)
          .limit(200)),
      item: (context, m, recarregar) {
        final can = m['canonical_products'];
        final prod = m['products'];
        final canNome = can is Map ? '${can['canonical_name']}${can['brand'] != null ? ' · ${can['brand']}' : ''}' : '—';
        final prodNome = prod is Map ? '${prod['name']} (${_curto(prod['restaurant_id'])}, ${_eur(prod['price'])})' : m['product_id'].toString();
        final revista = (m['reviewed'] as bool?) ?? false;
        return Card(
          child: ListTile(
            leading: Icon(revista ? Icons.verified_outlined : Icons.link,
                color: revista ? AppColors.primary : AppColors.textSecondary),
            title: Text(prodNome, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '→ $canNome · ${m['method']} · confiança ${(((m['confidence'] as num?) ?? 0) * 100).toStringAsFixed(0)}%'),
            trailing: revista
                ? const Text('revista', style: TextStyle(color: AppColors.primary, fontSize: 12))
                : TextButton(
                    onPressed: () async {
                      try {
                        await _c
                            .from('product_matches')
                            .update({'reviewed': true}).eq('product_id', m['product_id']);
                        recarregar();
                      } catch (e) {
                        if (context.mounted) _snack(context, 'Não deu para gravar: $e');
                      }
                    },
                    child: const Text('Marcar revista'),
                  ),
          ),
        );
      },
    );
  }
}
