// Prêmios dos marcos do check-in (Bloco D, 21/10/2026). PT-BR.
// Sequência contínua de check-ins: 7 dias = os tokens do Dia 7 (só mostra),
// 10 dias = 2 salgados da Keli, 15 = um açaí do Goola, 30 = 2 h de limpeza ou
// lavagem exterior. Aqui o Danilo:
//  - liga/desliga os marcos, o teto mensal dos prêmios de 30 dias e a regra do
//    pedido pago; muda validade, ciclo, dia/título/valor/custo de cada marco
//    (platform_settings com prefixo checkin_marco_, via admin_update_setting);
//  - vê o resumo (por estado, por marco, custo do mês e total);
//  - paga às lojas os prêmios usados (lista "A pagar às lojas" — enquanto o
//    acerto semanal da loja não inclui o prêmio sozinho);
//  - lista os vales, anula, marca "entregue à mão", dá um vale à mão, exporta CSV.
// Servidor: admin_checkin_premios_resumo, admin_checkin_premios_lista,
// admin_checkin_premio_anular / _dar / _marcar_usado, admin_checkin_premios_pagar_loja.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

class AdminCheckinPremiosScreen extends StatefulWidget {
  const AdminCheckinPremiosScreen({super.key});

  @override
  State<AdminCheckinPremiosScreen> createState() => _AdminCheckinPremiosScreenState();
}

const _estados = <String, String>{
  '': 'Todos',
  'por_usar': 'Por usar',
  'reservado': 'No carrinho',
  'guardado': 'Guardado (teto)',
  'a_espera_pedido': 'Esperando pedido',
  'usado': 'Usado',
  'expirado': 'Expirado',
  'anulado': 'Anulado',
};

const _chavesMarcos = ['semana', 'salgados', 'acai', 'mes'];

class _AdminCheckinPremiosScreenState extends State<AdminCheckinPremiosScreen> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _loading = true;
  bool _salvando = false;
  String? _error;

  Map<String, dynamic> _defs = {};
  Map<String, dynamic>? _resumo;
  List<Map<String, dynamic>> _vales = [];
  String _filtro = '';

  bool _ativo = false;
  bool _tetoAtivo = true;
  bool _exigePedido = true;
  final _teto = TextEditingController();
  final _validade = TextEditingController();
  final _ciclo = TextEditingController();
  final _pedidoDias = TextEditingController();
  final _lembreteDias = TextEditingController();
  final _busca = TextEditingController();
  final Map<String, Map<String, TextEditingController>> _marcoCampos = {};
  final Map<String, bool> _marcoAtivo = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_teto, _validade, _ciclo, _pedidoDias, _lembreteDias, _busca]) {
      c.dispose();
    }
    for (final m in _marcoCampos.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  dynamic _v(String k) => _defs[k];
  bool _bool(String k, bool d) => _v(k) is bool ? _v(k) as bool : d;
  int _int(String k, int d) => _v(k) is num ? (_v(k) as num).toInt() : int.tryParse('${_v(k)}') ?? d;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final defs = await _db.rpc('admin_list_settings', params: {'p_category': 'marketing'});
      final mapa = <String, dynamic>{};
      for (final r in (defs as List)) {
        final row = Map<String, dynamic>.from(r as Map);
        final k = '${row['key']}';
        if (k.startsWith('checkin_marco_')) mapa[k] = row['value'];
      }
      final resumo = await _db.rpc('admin_checkin_premios_resumo');
      _defs = mapa;
      _resumo = Map<String, dynamic>.from(resumo as Map);
      _ativo = _bool('checkin_marco_ativo', false);
      _tetoAtivo = _bool('checkin_marco_tecto_ativo', true);
      _exigePedido = _bool('checkin_marco_exige_pedido_pago', true);
      _teto.text = '${_int('checkin_marco_tecto_mensal', 10)}';
      _validade.text = '${_int('checkin_marco_validade_dias', 30)}';
      _ciclo.text = '${_int('checkin_marco_ciclo_dias', 30)}';
      _pedidoDias.text = '${_int('checkin_marco_pedido_pago_dias', 30)}';
      _lembreteDias.text = '${_int('checkin_marco_lembrete_dias', 3)}';
      for (final c in _chavesMarcos) {
        final m = _v('checkin_marco_$c');
        if (m is! Map) continue;
        _marcoAtivo[c] = m['ativo'] != false;
        final campos = _marcoCampos.putIfAbsent(c, () => {
              'dia': TextEditingController(),
              'titulo': TextEditingController(),
              'descricao': TextEditingController(),
              'valor_cents': TextEditingController(),
              'custo_cents': TextEditingController(),
            });
        campos['dia']!.text = '${m['dia'] ?? ''}';
        campos['titulo']!.text = '${m['titulo'] ?? ''}';
        campos['descricao']!.text = '${m['descricao'] ?? ''}';
        campos['valor_cents']!.text = '${m['valor_cents'] ?? ''}';
        campos['custo_cents']!.text = '${m['custo_cents'] ?? ''}';
      }
      await _loadVales();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = humanizeAdminRpcError(e);
      });
    }
  }

  Future<void> _loadVales() async {
    final r = await _db.rpc('admin_checkin_premios_lista', params: {
      'p_estado': _filtro.isEmpty ? null : _filtro,
      'p_busca': _busca.text.trim().isEmpty ? null : _busca.text.trim(),
      'p_limite': 300,
    });
    _vales = [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];
    if (mounted) setState(() {});
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    final mudancas = <String, dynamic>{
      'checkin_marco_ativo': _ativo,
      'checkin_marco_tecto_ativo': _tetoAtivo,
      'checkin_marco_exige_pedido_pago': _exigePedido,
      'checkin_marco_tecto_mensal': int.tryParse(_teto.text.trim()) ?? 10,
      'checkin_marco_validade_dias': (int.tryParse(_validade.text.trim()) ?? 30).clamp(1, 365),
      'checkin_marco_ciclo_dias': (int.tryParse(_ciclo.text.trim()) ?? 30).clamp(1, 365),
      'checkin_marco_pedido_pago_dias': (int.tryParse(_pedidoDias.text.trim()) ?? 30).clamp(1, 365),
      'checkin_marco_lembrete_dias': (int.tryParse(_lembreteDias.text.trim()) ?? 3).clamp(0, 30),
    };
    for (final c in _chavesMarcos) {
      final atual = _v('checkin_marco_$c');
      final campos = _marcoCampos[c];
      if (atual is! Map || campos == null) continue;
      final novo = Map<String, dynamic>.from(atual)
        ..['ativo'] = _marcoAtivo[c] ?? true
        ..['dia'] = int.tryParse(campos['dia']!.text.trim()) ?? atual['dia']
        ..['titulo'] = campos['titulo']!.text.trim()
        ..['descricao'] = campos['descricao']!.text.trim();
      if (atual['tipo'] == 'produto') {
        novo['valor_cents'] = int.tryParse(campos['valor_cents']!.text.trim()) ?? atual['valor_cents'];
        novo['custo_cents'] = int.tryParse(campos['custo_cents']!.text.trim()) ?? atual['custo_cents'];
      }
      mudancas['checkin_marco_$c'] = novo;
    }
    final messenger = ScaffoldMessenger.of(context);
    var n = 0;
    try {
      for (final e in mudancas.entries) {
        if ('${_defs[e.key]}' == '${e.value}') continue;
        await _db.rpc('admin_update_setting', params: {'p_key': e.key, 'p_value': e.value});
        n++;
      }
      messenger.showSnackBar(SnackBar(content: Text(n == 0 ? 'Nada mudou.' : 'Salvo ($n alterações, ficam no registro).')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<String?> _pedirMotivo(String titulo) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Motivo (fica no registro)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Confirmar')),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _acao(String rpc, Map<String, dynamic> params, String ok) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _db.rpc(rpc, params: params);
      messenger.showSnackBar(SnackBar(content: Text(ok)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _anular(Map<String, dynamic> v) async {
    final m = await _pedirMotivo('Anular o vale de ${v['cliente_nome'] ?? v['cliente_email'] ?? ''}?');
    if (m == null) return;
    await _acao('admin_checkin_premio_anular', {'p_vale_id': v['id'], 'p_motivo': m}, 'Vale anulado.');
  }

  Future<void> _entregueMao(Map<String, dynamic> v) async {
    final m = await _pedirMotivo('Marcar como entregue à mão (fora do app)?');
    if (m == null) return;
    await _acao('admin_checkin_premio_marcar_usado', {'p_vale_id': v['id'], 'p_motivo': m}, 'Marcado como usado.');
  }

  Future<void> _pagarLoja(Map<String, dynamic> loja) async {
    final ids = (loja['ids'] as List? ?? const []).map((e) => '$e').toList();
    final nota = await _pedirMotivo('Marcar ${loja['vales']} prêmio(s) como pagos à ${loja['loja_nome'] ?? loja['loja_id']} (${_euros(loja['custo_cents'])})?');
    if (nota == null) return;
    await _acao('admin_checkin_premios_pagar_loja', {'p_vale_ids': ids, 'p_nota': nota}, 'Marcado como pago à loja.');
  }

  Future<void> _darVale() async {
    final quem = TextEditingController();
    final motivo = TextEditingController();
    String chave = 'salgados';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Dar um vale à mão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: quem, decoration: const InputDecoration(labelText: 'E-mail ou ID (user_id) do cliente')),
              DropdownButton<String>(
                value: chave,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'salgados', child: Text('10 dias — 2 salgados da Keli')),
                  DropdownMenuItem(value: 'acai', child: Text('15 dias — açaí do Goola')),
                  DropdownMenuItem(value: 'mes', child: Text('30 dias — limpeza ou lavagem')),
                ],
                onChanged: (v) => setD(() => chave = v ?? chave),
              ),
              TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (fica no registro)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dar')),
          ],
        ),
      ),
    );
    final q = quem.text.trim();
    final mot = motivo.text.trim();
    quem.dispose();
    motivo.dispose();
    if (ok != true || q.isEmpty || mot.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String? userId = q;
    if (q.contains('@')) {
      final r = await _db.from('users').select('id').eq('email', q.toLowerCase()).maybeSingle();
      userId = r?['id'] as String?;
    }
    if (userId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Cliente não encontrado.')));
      return;
    }
    await _acao('admin_checkin_premio_dar', {'p_user_id': userId, 'p_chave': chave, 'p_motivo': mot}, 'Vale dado (o cliente recebe o aviso).');
  }

  String _euros(dynamic cents) {
    final c = cents is num ? cents : num.tryParse('$cents') ?? 0;
    return '${(c / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String _dataCurta(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Prêmios dos marcos do check-in'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _secao('Interruptores e regras', [
                        SwitchListTile(
                          value: _ativo,
                          onChanged: (v) => setState(() => _ativo = v),
                          title: const Text('Marcos ligados (checkin_marco_ativo)'),
                          subtitle: const Text('Liga só depois de a versão com "Os meus prêmios" estar nas 3 lojas.'),
                        ),
                        SwitchListTile(
                          value: _tetoAtivo,
                          onChanged: (v) => setState(() => _tetoAtivo = v),
                          title: const Text('Teto mensal dos prêmios de 30 dias'),
                          subtitle: const Text('Quem chega depois do teto fica com o vale guardado para o mês seguinte.'),
                        ),
                        _numero(_teto, 'Teto: vales de 30 dias por mês'),
                        SwitchListTile(
                          value: _exigePedido,
                          onChanged: (v) => setState(() => _exigePedido = v),
                          title: const Text('Vale de 30 dias exige 1 pedido pago'),
                          subtitle: const Text('Sem pedido, o app mostra "falta 1 pedido para desbloquear o prêmio".'),
                        ),
                        _numero(_pedidoDias, 'Janela do pedido pago (dias)'),
                        _numero(_validade, 'Validade de cada vale (dias)'),
                        _numero(_ciclo, 'Ciclo dos marcos (dias; depois recomeça no 1)'),
                        _numero(_lembreteDias, 'Lembretes 11h/20h falam do marco quando faltam até (dias)'),
                      ]),
                      _secao('Marcos', [
                        for (final c in _chavesMarcos)
                          if (_marcoCampos[c] != null) _marcoEditor(c),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: FilledButton.icon(
                          onPressed: _salvando ? null : _salvar,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_salvando ? 'Salvando…' : 'Salvar regras e marcos'),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        ),
                      ),
                      _secao('Resumo', [_resumoView()]),
                      _secao('A pagar às lojas', [_lojasView()]),
                      _secao('Vales', [_valesView()]),
                    ],
                  ),
                ),
    );
  }

  Widget _secao(String titulo, List<Widget> filhos) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _numero(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label)),
      );

  Widget _marcoEditor(String chave) {
    final m = _v('checkin_marco_$chave') as Map;
    final campos = _marcoCampos[chave]!;
    final produto = m['tipo'] == 'produto';
    return ExpansionTile(
      title: Text('Dia ${m['dia']} — ${m['titulo']}'),
      subtitle: Text('tipo: ${m['tipo']}${produto ? ' · loja ${m['loja_id']} · artigo ${m['produto_id']}' : ''}'),
      children: [
        SwitchListTile(
          value: _marcoAtivo[chave] ?? true,
          onChanged: (v) => setState(() => _marcoAtivo[chave] = v),
          title: const Text('Este marco está ligado'),
        ),
        _numero(campos['dia']!, 'Dia do marco'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(controller: campos['titulo'], decoration: const InputDecoration(labelText: 'Título (o que o cliente lê)')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(controller: campos['descricao'], maxLines: 2, decoration: const InputDecoration(labelText: 'Descrição (vista do mês)')),
        ),
        if (produto) ...[
          _numero(campos['valor_cents']!, 'Valor para o cliente (cêntimos, preço no app)'),
          _numero(campos['custo_cents']!, 'Custo para a Bora (cêntimos, o que a loja recebe)'),
        ],
        if (m['tipo'] == 'servico')
          const ListTile(
            dense: true,
            title: Text('Limpeza 2 h ou lavagem exterior: o valor e o ganho do prestador saem da tabela normal na hora de marcar.'),
          ),
      ],
    );
  }

  Widget _resumoView() {
    final r = _resumo ?? const {};
    final estados = (r['por_estado'] as Map?) ?? const {};
    final marcos = (r['por_marco'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in _estados.entries.where((e) => e.key.isNotEmpty))
              Chip(label: Text('${e.value}: ${estados[e.key] ?? 0}')),
          ],
        ),
        const SizedBox(height: 6),
        Text('Custo dos prêmios usados — este mês: ${_euros(r['custo_mes_cents'])} · total: ${_euros(r['custo_total_cents'])}'),
        Text('Teto mensal dos vales de 30 dias: ${r['tecto_mensal'] ?? '—'}'),
        const SizedBox(height: 6),
        for (final m in marcos.whereType<Map>())
          Text('Dia ${m['marco']} (${m['chave']}): emitidos ${m['emitidos']} · usados ${m['usados']} · '
              'custo ${_euros(m['custo_usados_cents'])} · este mês ${m['emitidos_mes']} emitidos / ${m['ativados_mes']} liberados'),
      ],
    );
  }

  Widget _lojasView() {
    final lojas = ((_resumo?['a_pagar_lojas'] as List?) ?? const []).whereType<Map>().toList();
    if (lojas.isEmpty) return const Text('Nada a pagar às lojas.');
    return Column(
      children: [
        const Text(
          'Enquanto o acerto semanal da loja não inclui o prêmio sozinho (proposta à espera do "vai"), '
          'a Bora paga daqui o preço de balcão de cada prêmio usado (venda normal).',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        for (final l in lojas)
          ListTile(
            title: Text('${l['loja_nome'] ?? l['loja_id']}'),
            subtitle: Text('${l['vales']} prêmio(s) usados'),
            trailing: FilledButton(
              onPressed: () => _pagarLoja(Map<String, dynamic>.from(l)),
              child: Text('Pago ${_euros(l['custo_cents'])}'),
            ),
          ),
      ],
    );
  }

  Widget _valesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final e in _estados.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _filtro == e.key,
                onSelected: (_) async {
                  setState(() => _filtro = e.key);
                  await _loadVales();
                },
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _busca,
                decoration: const InputDecoration(labelText: 'Buscar (nome, e-mail, id do vale ou do pedido)'),
                onSubmitted: (_) => _loadVales(),
              ),
            ),
            IconButton(onPressed: _loadVales, icon: const Icon(Icons.search)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(onPressed: _darVale, icon: const Icon(Icons.card_giftcard), label: const Text('Dar vale à mão')),
            const SizedBox(width: 8),
            AdminCsvButton(
              nome: 'checkin_premios_vales',
              colunas: const [
                ('id', 'id'),
                ('cliente_nome', 'cliente'),
                ('cliente_email', 'email'),
                ('marco', 'marco'),
                ('titulo', 'prêmio'),
                ('estado', 'estado'),
                ('loja_nome', 'loja'),
                ('valor_cents', 'valor_cents'),
                ('custo_cents', 'custo_cents'),
                ('emitido_em', 'emitido_em'),
                ('valido_ate', 'valido_ate'),
                ('usado_em', 'usado_em'),
                ('pedido_id', 'pedido_id'),
                ('marcacao_tipo', 'marcacao'),
                ('pago_loja_em', 'pago_loja_em'),
                ('origem', 'origem'),
                ('motivo', 'motivo'),
              ],
              linhas: () => _vales,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_vales.isEmpty) const Text('Nenhum vale com este filtro.'),
        for (final v in _vales)
          ListTile(
            dense: true,
            title: Text('${v['cliente_nome'] ?? v['cliente_email'] ?? v['user_id']} — dia ${v['marco']}: ${v['titulo']}'),
            subtitle: Text('${_estados[v['estado']] ?? v['estado']} · emitido ${_dataCurta(v['emitido_em'])}'
                '${v['valido_ate'] != null ? ' · vale até ${_dataCurta(v['valido_ate'])}' : ''}'
                '${v['pedido_id'] != null ? ' · pedido ${'${v['pedido_id']}'.substring(0, 8)}' : ''}'
                '${v['marcacao_tipo'] != null ? ' · ${v['marcacao_tipo']}' : ''}'
                ' · custo ${_euros(v['custo_cents'])}'
                '${v['origem'] == 'admin' ? ' · dado à mão' : ''}'),
            trailing: PopupMenuButton<String>(
              onSelected: (a) {
                if (a == 'anular') _anular(v);
                if (a == 'mao') _entregueMao(v);
              },
              itemBuilder: (_) => [
                if (['por_usar', 'reservado', 'guardado', 'a_espera_pedido'].contains(v['estado']))
                  const PopupMenuItem(value: 'anular', child: Text('Anular')),
                if (['por_usar', 'reservado'].contains(v['estado']))
                  const PopupMenuItem(value: 'mao', child: Text('Entregue à mão')),
              ],
            ),
          ),
      ],
    );
  }
}
