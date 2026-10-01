// Painel admin (PT-BR) — Assistentes (funcionário digital), 01/10/2026.
//
// O assistente de WhatsApp que atende os clientes de um negócio (ex.: barbearia) em nome do
// dono. Cada negócio é uma linha de `assistant_tenants`; as mensagens vivem em
// `assistant_messages` e os contactos em `assistant_contacts`. RLS: só admin (is_admin()).
//
// Aqui o Danilo vê o resumo do mês (RPC admin_assistente_resumo), muda o modo
// (teste / ligado / desligado), edita listas de números, a ficha do negócio e as perguntas
// aprendidas, lê as conversas e limpa as marcações de teste (RPC admin_assistente_limpar_testes).
// Mudanças de modo e limpezas ficam registadas em admin_audit_log.
//
// Padrão igual aos outros ecrãs admin: chamada direta ao Supabase, sem Store.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

final _numeroValido = RegExp(r'^\d{9,15}$');

String _euros(dynamic v) {
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return '${n.toStringAsFixed(2).replaceAll('.', ',')} €';
}

String _hora(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '—';
  String p(int x) => x.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
}

Color _corModo(String? m) {
  switch (m) {
    case 'ligado':
      return AppColors.success;
    case 'teste':
      return AppColors.warning;
    default:
      return AppColors.textSubtle;
  }
}

Widget _chipModo(String? m) {
  final c = _corModo(m);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c),
    ),
    child: Text((m ?? '—').toUpperCase(),
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
  );
}

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

Future<void> _auditar(String acao, String tenantId, Map<String, dynamic> detalhes) async {
  final c = Supabase.instance.client;
  try {
    await c.from('admin_audit_log').insert({
      'admin_id': c.auth.currentUser?.id,
      'admin_email': c.auth.currentUser?.email,
      'action': acao,
      'entity_type': 'assistant_tenant',
      'entity_id': tenantId,
      'details': detalhes,
    });
  } catch (e) {
    debugPrint('[assistentes] auditoria falhou: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lista
// ─────────────────────────────────────────────────────────────────────────────

class AdminAssistentesScreen extends StatefulWidget {
  const AdminAssistentesScreen({super.key});

  @override
  State<AdminAssistentesScreen> createState() => _AdminAssistentesScreenState();
}

class _AdminAssistentesScreenState extends State<AdminAssistentesScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _lista = const [];

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
      final r = await _c.rpc('admin_assistente_resumo');
      if (!mounted) return;
      setState(() {
        _lista = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Assistentes (funcionário digital)',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
              : _lista.isEmpty
                  ? const Center(child: Text('Nenhum assistente cadastrado.'))
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: _lista.map(_cartao).toList(),
                      ),
                    ),
    );
  }

  Widget _cartao(Map<String, dynamic> t) {
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AdminAssistenteDetalheScreen(
              tenantId: t['tenant_id'] as String,
              nome: (t['nome'] ?? '') as String,
            ),
          ));
          _carregar();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${t['nome'] ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  _chipModo(t['mode'] as String?),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _kv('Custo do mês', '${_euros(t['custo_mes_eur'])} de ${_euros(t['orcamento_eur'])}'),
                  _kv('Conversas no mês', '${t['conversas_mes'] ?? 0}'),
                  _kv('Mensagens no mês', '${t['mensagens_mes'] ?? 0}'),
                  _kv('Marcações no mês', '${t['marcacoes_mes'] ?? 0}'),
                  _kv('Marcações de teste ativas', '${t['marcacoes_teste_ativas'] ?? 0}'),
                  _kv('Tarefas abertas', '${t['tarefas_abertas'] ?? 0}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Detalhe
// ─────────────────────────────────────────────────────────────────────────────

class AdminAssistenteDetalheScreen extends StatefulWidget {
  const AdminAssistenteDetalheScreen({super.key, required this.tenantId, required this.nome});

  final String tenantId;
  final String nome;

  @override
  State<AdminAssistenteDetalheScreen> createState() => _AdminAssistenteDetalheScreenState();
}

class _AdminAssistenteDetalheScreenState extends State<AdminAssistenteDetalheScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _t;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _c
          .from('assistant_tenants')
          .select('id, slug, nome, sessao, mode, allowlist, blocklist, owner_number, dono_destino, '
              'knowledge, motor, motores_reserva, orcamento_mensal_eur, tom, link_avaliacao, updated_at')
          .eq('id', widget.tenantId)
          .single();
      if (!mounted) return;
      setState(() {
        _t = Map<String, dynamic>.from(r);
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(
          title: widget.nome.isEmpty ? 'Assistente' : widget.nome,
          actions: [
            IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Configuração'),
              Tab(text: 'Ficha'),
              Tab(text: 'Conversas'),
            ],
          ),
        ),
        body: _erro != null
            ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
            : _t == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _ConfigTab(key: ValueKey('cfg${_t!['updated_at']}'), tenant: _t!, onMudou: _carregar),
                      _FichaTab(key: ValueKey('ficha${_t!['updated_at']}'), tenant: _t!, onMudou: _carregar),
                      _ConversasTab(tenantId: widget.tenantId),
                    ],
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Separador: Configuração
// ─────────────────────────────────────────────────────────────────────────────

class _ConfigTab extends StatefulWidget {
  const _ConfigTab({super.key, required this.tenant, required this.onMudou});

  final Map<String, dynamic> tenant;
  final Future<void> Function() onMudou;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  final _c = Supabase.instance.client;
  late final TextEditingController _donoDestino;
  late final TextEditingController _ownerNumber;
  late final TextEditingController _orcamento;
  late final TextEditingController _link;
  late final TextEditingController _tom;
  bool _gravando = false;

  String get _id => widget.tenant['id'] as String;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    _donoDestino = TextEditingController(text: '${t['dono_destino'] ?? ''}');
    _ownerNumber = TextEditingController(text: '${t['owner_number'] ?? ''}');
    final orc = t['orcamento_mensal_eur'];
    _orcamento = TextEditingController(
        text: orc == null ? '' : (orc as num).toStringAsFixed(2).replaceAll('.', ','));
    _link = TextEditingController(text: '${t['link_avaliacao'] ?? ''}');
    _tom = TextEditingController(text: '${t['tom'] ?? ''}');
  }

  @override
  void dispose() {
    _donoDestino.dispose();
    _ownerNumber.dispose();
    _orcamento.dispose();
    _link.dispose();
    _tom.dispose();
    super.dispose();
  }

  Future<void> _mudarModo(String novo) async {
    final atual = widget.tenant['mode'] as String?;
    if (novo == atual) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mudar para "$novo"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modo atual: ${atual ?? '—'}. Novo modo: $novo.'),
            if (novo == 'teste')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Em teste só responde aos números da lista de permitidos.'),
              ),
            if (novo == 'desligado')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Desligado não responde a ninguém.'),
              ),
            if (novo == 'ligado')
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error),
                ),
                child: const Text(
                  'Ligado responde a TODOS os números que escreverem para esta sessão (exceto a lista '
                  'de bloqueio). Na sessão partilhada com a Bora isto atende os clientes da Bora.',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: novo == 'ligado' ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _c.from('assistant_tenants').update({'mode': novo}).eq('id', _id);
      await _auditar('assistente_mudar_modo', _id, {'de': atual, 'para': novo});
      if (!mounted) return;
      _aviso(context, 'Modo alterado para $novo.');
      await widget.onMudou();
    } catch (e) {
      if (!mounted) return;
      _aviso(context, 'Erro: $e');
    }
  }

  Future<void> _gravarLista(String coluna, List<String> nova) async {
    try {
      await _c.from('assistant_tenants').update({coluna: nova}).eq('id', _id);
      await _auditar('assistente_editar_$coluna', _id, {coluna: nova});
      if (!mounted) return;
      _aviso(context, 'Lista gravada.');
      await widget.onMudou();
    } catch (e) {
      if (!mounted) return;
      _aviso(context, 'Erro: $e');
    }
  }

  Future<void> _gravarCampos() async {
    final orcTxt = _orcamento.text.trim().replaceAll(',', '.');
    final orc = orcTxt.isEmpty ? null : double.tryParse(orcTxt);
    if (orcTxt.isNotEmpty && orc == null) {
      _aviso(context, 'Orçamento inválido. Use um número, ex.: 5,00');
      return;
    }
    final owner = _ownerNumber.text.trim();
    if (owner.isNotEmpty && !_numeroValido.hasMatch(owner)) {
      _aviso(context, 'Número do dono inválido: só dígitos com indicativo, ex.: 351912345678');
      return;
    }
    String? vazio(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _gravando = true);
    try {
      final dados = {
        'dono_destino': vazio(_donoDestino),
        'owner_number': vazio(_ownerNumber),
        'orcamento_mensal_eur': orc,
        'link_avaliacao': vazio(_link),
        'tom': vazio(_tom),
      };
      await _c.from('assistant_tenants').update(dados).eq('id', _id);
      await _auditar('assistente_editar_config', _id, dados);
      if (!mounted) return;
      _aviso(context, 'Configuração gravada.');
      await widget.onMudou();
    } catch (e) {
      if (!mounted) return;
      _aviso(context, 'Erro: $e');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _limparTestes() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar marcações de teste?'),
        content: const Text(
            'Cancela as marcações e tarefas criadas em teste por este assistente. Marcações reais não são tocadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Limpar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _c.rpc('admin_assistente_limpar_testes', params: {'p_tenant': _id});
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      await _auditar('assistente_limpar_testes', _id, m);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(m['ok'] == true ? 'Limpeza feita' : 'Resultado'),
          content: Text('Marcações canceladas: ${m['marcacoes_canceladas'] ?? 0}\n'
              'Tarefas canceladas: ${m['tarefas_canceladas'] ?? 0}'
              '${m['ok'] == true ? '' : '\n\nResposta: $m'}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _aviso(context, 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;
    final modo = t['mode'] as String?;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('Modo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  _chipModo(modo),
                ]),
                const SizedBox(height: 4),
                Text('Sessão: ${t['sessao'] ?? '—'} · Motor: ${t['motor'] ?? '—'}'
                    '${(t['motores_reserva'] as List?)?.isNotEmpty == true ? ' (reserva: ${(t['motores_reserva'] as List).join(', ')})' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ['teste', 'ligado', 'desligado']
                      .map((m) => ChoiceChip(
                            label: Text(m),
                            selected: modo == m,
                            selectedColor: _corModo(m).withValues(alpha: 0.25),
                            onSelected: (_) => _mudarModo(m),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        _ListaNumeros(
          titulo: 'Lista de permitidos (allowlist)',
          ajuda: 'Em teste, só estes números recebem resposta.',
          numeros: List<String>.from((t['allowlist'] as List?) ?? const []),
          onGravar: (l) => _gravarLista('allowlist', l),
        ),
        _ListaNumeros(
          titulo: 'Lista de bloqueio (blocklist)',
          ajuda: 'Estes números nunca recebem resposta, em nenhum modo.',
          numeros: List<String>.from((t['blocklist'] as List?) ?? const []),
          onGravar: (l) => _gravarLista('blocklist', l),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dono e ajustes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                _campo(_donoDestino, 'Destino das perguntas ao dono (dono_destino)'),
                _campo(_ownerNumber, 'Número do dono (owner_number), ex.: 351912345678',
                    teclado: TextInputType.number),
                _campo(_orcamento, 'Orçamento mensal (€)',
                    teclado: const TextInputType.numberWithOptions(decimal: true)),
                _campo(_link, 'Link de avaliação Google'),
                _campo(_tom, 'Tom (como o assistente fala)', linhas: 3),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _gravando ? null : _gravarCampos,
                  icon: const Icon(Icons.save),
                  label: Text(_gravando ? 'Gravando…' : 'Gravar'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _limparTestes,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('Limpar marcações de teste'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _campo(TextEditingController c, String rotulo, {TextInputType? teclado, int linhas = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          minLines: 1,
          maxLines: linhas,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder(), isDense: true),
        ),
      );
}

class _ListaNumeros extends StatefulWidget {
  const _ListaNumeros({
    required this.titulo,
    required this.ajuda,
    required this.numeros,
    required this.onGravar,
  });

  final String titulo;
  final String ajuda;
  final List<String> numeros;
  final Future<void> Function(List<String>) onGravar;

  @override
  State<_ListaNumeros> createState() => _ListaNumerosState();
}

class _ListaNumerosState extends State<_ListaNumeros> {
  final _novo = TextEditingController();

  @override
  void dispose() {
    _novo.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    final n = _novo.text.replaceAll(RegExp(r'[\s+\-]'), '');
    if (!_numeroValido.hasMatch(n)) {
      _aviso(context, 'Só dígitos com indicativo, ex.: 351912345678');
      return;
    }
    if (widget.numeros.contains(n)) {
      _aviso(context, 'Esse número já está na lista.');
      return;
    }
    _novo.clear();
    await widget.onGravar([...widget.numeros, n]);
  }

  Future<void> _remover(String n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover número?'),
        content: Text('Tirar $n de "${widget.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onGravar(widget.numeros.where((x) => x != n).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(widget.ajuda, style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            const SizedBox(height: 8),
            if (widget.numeros.isEmpty)
              const Text('Lista vazia.', style: TextStyle(color: AppColors.textSubtle))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.numeros
                    .map((n) => InputChip(label: Text(n), onDeleted: () => _remover(n)))
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _novo,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Novo número (ex.: 351912345678)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _adicionar(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _adicionar, icon: const Icon(Icons.add), tooltip: 'Adicionar'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Separador: Ficha (knowledge.ficha + knowledge.perguntas_aprendidas)
// ─────────────────────────────────────────────────────────────────────────────

class _FichaTab extends StatefulWidget {
  const _FichaTab({super.key, required this.tenant, required this.onMudou});

  final Map<String, dynamic> tenant;
  final Future<void> Function() onMudou;

  @override
  State<_FichaTab> createState() => _FichaTabState();
}

class _FichaTabState extends State<_FichaTab> {
  final _c = Supabase.instance.client;

  static const _camposTexto = <String, String>{
    'nome': 'Nome do negócio',
    'dono': 'Dono',
    'morada': 'Morada',
    'telefone': 'Telefone',
    'instagram': 'Instagram',
    'site': 'Site',
    'pagamento': 'Pagamento',
    'apos_marcacao': 'Depois da marcação (o que dizer ao cliente)',
  };

  final Map<String, TextEditingController> _ctl = {};
  late List<String> _notas;
  late List<Map<String, dynamic>> _perguntas;
  late List<Map<String, dynamic>> _perguntasOriginais;
  bool _sujo = false;
  bool _gravando = false;

  String get _id => widget.tenant['id'] as String;

  Map<String, dynamic> get _knowledge =>
      Map<String, dynamic>.from((widget.tenant['knowledge'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    final ficha = Map<String, dynamic>.from((_knowledge['ficha'] as Map?) ?? const {});
    for (final k in _camposTexto.keys) {
      final v = ficha[k];
      _ctl[k] = TextEditingController(text: v == null ? '' : '$v')..addListener(_marcarSujo);
    }
    _notas = ((ficha['notas'] as List?) ?? const []).map((e) => '$e').toList();
    _perguntasOriginais = ((_knowledge['perguntas_aprendidas'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _perguntas = _perguntasOriginais.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _marcarSujo() {
    if (!_sujo && mounted) setState(() => _sujo = true);
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _chavePergunta(Map p) => '${p['pergunta']}|${p['data']}';

  Future<void> _gravar() async {
    setState(() => _gravando = true);
    try {
      // Relê o knowledge atual: o assistente pode ter aprendido perguntas novas desde que o ecrã abriu.
      final fresco = await _c.from('assistant_tenants').select('knowledge').eq('id', _id).single();
      final k = Map<String, dynamic>.from((fresco['knowledge'] as Map?) ?? const {});
      final fichaAtual = Map<String, dynamic>.from((k['ficha'] as Map?) ?? const {});
      for (final e in _ctl.entries) {
        final v = e.value.text.trim();
        if (v.isEmpty) {
          fichaAtual.remove(e.key);
        } else {
          fichaAtual[e.key] = v;
        }
      }
      fichaAtual['notas'] = _notas.where((n) => n.trim().isNotEmpty).toList();
      k['ficha'] = fichaAtual;

      final conhecidas = _perguntasOriginais.map(_chavePergunta).toSet();
      final novasNoServidor = ((k['perguntas_aprendidas'] as List?) ?? const [])
          .whereType<Map>()
          .where((p) => !conhecidas.contains(_chavePergunta(p)))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      k['perguntas_aprendidas'] = [..._perguntas, ...novasNoServidor];

      await _c.from('assistant_tenants').update({'knowledge': k}).eq('id', _id);
      await _auditar('assistente_editar_ficha', _id, {
        'perguntas': (k['perguntas_aprendidas'] as List).length,
        'notas': (fichaAtual['notas'] as List).length,
      });
      if (!mounted) return;
      _aviso(context, novasNoServidor.isEmpty
          ? 'Ficha gravada.'
          : 'Ficha gravada. ${novasNoServidor.length} pergunta(s) nova(s) aprendida(s) entretanto foram mantidas.');
      await widget.onMudou();
    } catch (e) {
      if (!mounted) return;
      _aviso(context, 'Erro: $e');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<String?> _editarTexto(String titulo, String inicial) async {
    final ctl = TextEditingController(text: inicial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(controller: ctl, autofocus: true, minLines: 2, maxLines: 6),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    return r;
  }

  Future<void> _editarPergunta(int i) async {
    final p = _perguntas[i];
    final q = TextEditingController(text: '${p['pergunta'] ?? ''}');
    final a = TextEditingController(text: '${p['resposta'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar pergunta aprendida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: q, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Pergunta')),
            const SizedBox(height: 8),
            TextField(controller: a, minLines: 2, maxLines: 8, decoration: const InputDecoration(labelText: 'Resposta')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _perguntas[i] = {...p, 'pergunta': q.text.trim(), 'resposta': a.text.trim()};
        _sujo = true;
      });
    }
  }

  Future<void> _apagarPergunta(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar pergunta aprendida?'),
        content: Text('${_perguntas[i]['pergunta'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _perguntas.removeAt(i);
        _sujo = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_sujo)
          Container(
            width: double.infinity,
            color: AppColors.warning.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text('Há alterações por gravar. Toque em "Gravar ficha".',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ficha do negócio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      ..._camposTexto.entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: _ctl[e.key],
                              minLines: 1,
                              maxLines: e.key == 'apos_marcacao' ? 5 : 2,
                              decoration: InputDecoration(
                                  labelText: e.value, border: const OutlineInputBorder(), isDense: true),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Notas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        IconButton(
                          tooltip: 'Adicionar nota',
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            final r = await _editarTexto('Nova nota', '');
                            if (r != null && r.isNotEmpty) {
                              setState(() {
                                _notas.add(r);
                                _sujo = true;
                              });
                            }
                          },
                        ),
                      ]),
                      if (_notas.isEmpty)
                        const Text('Sem notas.', style: TextStyle(color: AppColors.textSubtle)),
                      ..._notas.asMap().entries.map((e) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.value),
                            onTap: () async {
                              final r = await _editarTexto('Editar nota', e.value);
                              if (r != null && r.isNotEmpty) {
                                setState(() {
                                  _notas[e.key] = r;
                                  _sujo = true;
                                });
                              }
                            },
                            trailing: IconButton(
                              tooltip: 'Remover nota',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() {
                                _notas.removeAt(e.key);
                                _sujo = true;
                              }),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Perguntas aprendidas (${_perguntas.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const Text('O que o dono respondeu e o assistente passou a saber.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
                      const SizedBox(height: 6),
                      if (_perguntas.isEmpty)
                        const Text('Nenhuma ainda.', style: TextStyle(color: AppColors.textSubtle)),
                      ..._perguntas.asMap().entries.map((e) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${e.value['pergunta'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${e.value['resposta'] ?? ''}'
                                '${e.value['data'] != null ? '\n${e.value['data']}' : ''}'),
                            isThreeLine: e.value['data'] != null,
                            onTap: () => _editarPergunta(e.key),
                            trailing: IconButton(
                              tooltip: 'Apagar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _apagarPergunta(e.key),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _gravando || !_sujo ? null : _gravar,
                icon: const Icon(Icons.save),
                label: Text(_gravando ? 'Gravando…' : 'Gravar ficha'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Separador: Conversas
// ─────────────────────────────────────────────────────────────────────────────

class _ConversasTab extends StatefulWidget {
  const _ConversasTab({required this.tenantId});

  final String tenantId;

  @override
  State<_ConversasTab> createState() => _ConversasTabState();
}

class _ConversasTabState extends State<_ConversasTab> {
  final _c = Supabase.instance.client;
  bool _mostrarSimulacoes = false;
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _conversas = const [];
  Map<String, String> _nomes = const {};

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
      var q = _c
          .from('assistant_messages')
          .select('numero, direcao, texto, simulado, created_at')
          .eq('tenant_id', widget.tenantId);
      if (!_mostrarSimulacoes) q = q.eq('simulado', false);
      final msgs = await q.order('created_at', ascending: false).limit(1500);
      final contactos = await _c
          .from('assistant_contacts')
          .select('numero, nome')
          .eq('tenant_id', widget.tenantId);

      // Agrupa por número, mantendo a ordem (mais recente primeiro).
      final porNumero = <String, Map<String, dynamic>>{};
      for (final raw in msgs) {
        final m = Map<String, dynamic>.from(raw);
        final n = '${m['numero'] ?? '—'}';
        final g = porNumero.putIfAbsent(n, () => {
              'numero': n,
              'ultima': m,
              'total': 0,
              'simuladas': 0,
            });
        g['total'] = (g['total'] as int) + 1;
        if (m['simulado'] == true) g['simuladas'] = (g['simuladas'] as int) + 1;
      }
      if (!mounted) return;
      setState(() {
        _conversas = porNumero.values.toList();
        _nomes = {
          for (final c in contactos)
            if (c['nome'] != null && '${c['nome']}'.trim().isNotEmpty) '${c['numero']}': '${c['nome']}'
        };
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Mostrar simulações'),
          subtitle: const Text('Mensagens de teste geradas pelo simulador'),
          value: _mostrarSimulacoes,
          onChanged: (v) {
            setState(() => _mostrarSimulacoes = v);
            _carregar();
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
                  : _conversas.isEmpty
                      ? const Center(child: Text('Sem conversas.'))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView.separated(
                            itemCount: _conversas.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final g = _conversas[i];
                              final n = g['numero'] as String;
                              final u = g['ultima'] as Map<String, dynamic>;
                              final nome = _nomes[n];
                              final entrada = u['direcao'] == 'entrada';
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                  child: const Icon(Icons.person_outline, color: AppColors.primary),
                                ),
                                title: Text(nome == null ? n : '$nome · $n',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${entrada ? '' : 'Assistente: '}${u['texto'] ?? ''}',
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_hora(u['created_at']), style: const TextStyle(fontSize: 11)),
                                    Text('${g['total']} msg'
                                        '${(g['simuladas'] as int) > 0 ? ' · ${g['simuladas']} sim.' : ''}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSubtle)),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => _FioScreen(
                                    tenantId: widget.tenantId,
                                    numero: n,
                                    nome: nome,
                                    mostrarSimulacoes: _mostrarSimulacoes,
                                  ),
                                )),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _FioScreen extends StatefulWidget {
  const _FioScreen({
    required this.tenantId,
    required this.numero,
    required this.nome,
    required this.mostrarSimulacoes,
  });

  final String tenantId;
  final String numero;
  final String? nome;
  final bool mostrarSimulacoes;

  @override
  State<_FioScreen> createState() => _FioScreenState();
}

class _FioScreenState extends State<_FioScreen> {
  final _c = Supabase.instance.client;
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _msgs = const [];

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
      var q = _c
          .from('assistant_messages')
          .select('id, direcao, texto, motivo, decisao, modelo, custo_eur, simulado, entrega_estado, created_at')
          .eq('tenant_id', widget.tenantId)
          .eq('numero', widget.numero);
      if (!widget.mostrarSimulacoes) q = q.eq('simulado', false);
      final r = await q.order('created_at', ascending: false).limit(500);
      if (!mounted) return;
      setState(() {
        _msgs = List<Map<String, dynamic>>.from(r).reversed.toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: widget.nome == null ? widget.numero : '${widget.nome} · ${widget.numero}',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
              : _msgs.isEmpty
                  ? const Center(child: Text('Sem mensagens.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) => _balao(_msgs[i]),
                    ),
    );
  }

  Widget _balao(Map<String, dynamic> m) {
    final saida = m['direcao'] == 'saida';
    final meta = <String>[
      _hora(m['created_at']),
      if (m['modelo'] != null) '${m['modelo']}',
      if (m['entrega_estado'] != null) 'entrega: ${m['entrega_estado']}',
      if (m['decisao'] != null) 'decisão: ${m['decisao']}',
      if (m['motivo'] != null) 'motivo: ${m['motivo']}',
      if (m['custo_eur'] != null && (m['custo_eur'] as num) > 0) _euros(m['custo_eur']),
      if (m['simulado'] == true) 'SIMULAÇÃO',
    ].join(' · ');
    return Align(
      alignment: saida ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: saida ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: saida ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              SelectableText('${m['texto'] ?? ''}'),
              const SizedBox(height: 4),
              Text(meta, style: const TextStyle(fontSize: 10, color: AppColors.textSubtle)),
            ],
          ),
        ),
      ),
    );
  }
}
