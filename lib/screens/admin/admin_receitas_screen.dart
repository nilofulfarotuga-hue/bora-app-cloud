// lib/screens/admin/admin_receitas_screen.dart
//
// Painel admin (PT-BR) da Receita do Dia — Bora Todo Dia, 15/10/2026.
// Ligar/desligar o cartão e o aviso diário, mudar a hora do aviso, ver os
// números (quem pediu o aviso, enviados hoje e na semana) e criar, editar,
// agendar e desativar receitas. Receita nunca é apagada: desativa-se.
// Tabela `receitas_do_dia` (RLS: só admin escreve); definições
// `receita_do_dia_*` por `admin_update_setting`; resumo por
// `admin_receita_resumo()`.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

const _kLigada = 'receita_do_dia_enabled';
const _kAviso = 'receita_do_dia_push_enabled';
const _kHora = 'receita_do_dia_push_hour';
const _kAlargado = 'receita_do_dia_push_alargado';

Future<void> _logReceita(
    String acao, String id, Map<String, dynamic> detalhes) async {
  try {
    await Supabase.instance.client.rpc('log_admin_action', params: {
      'p_action': acao,
      'p_entity_type': 'receita_do_dia',
      'p_entity_id': id,
      'p_details': detalhes,
    });
  } catch (e) {
    debugPrint('[AdminReceitas] log: $e');
  }
}

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class AdminReceitasScreen extends StatefulWidget {
  const AdminReceitasScreen({super.key});

  @override
  State<AdminReceitasScreen> createState() => _AdminReceitasScreenState();
}

class _AdminReceitasScreenState extends State<AdminReceitasScreen> {
  bool _loading = true;
  bool _salvando = false;
  String? _error;
  Map<String, dynamic>? _resumo;
  List<Map<String, dynamic>> _receitas = const [];

  bool _ligada = true;
  bool _aviso = true;
  bool _alargado = true;
  int _hora = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final supa = Supabase.instance.client;
    try {
      final defs =
          await supa.rpc('admin_list_settings', params: {'p_category': null});
      final mapa = <String, dynamic>{};
      for (final r in (defs as List)) {
        final m = (r as Map).cast<String, dynamic>();
        mapa['${m['key']}'] = m['value'];
      }
      final resumo = Map<String, dynamic>.from(
          await supa.rpc('admin_receita_resumo') as Map);
      final lista = await supa
          .from('receitas_do_dia')
          .select()
          .order('ordem')
          .order('criado_em');
      if (!mounted) return;
      setState(() {
        _ligada = mapa[_kLigada] != false && '${mapa[_kLigada]}' != 'false';
        _aviso = mapa[_kAviso] != false && '${mapa[_kAviso]}' != 'false';
        _alargado =
            mapa[_kAlargado] != false && '${mapa[_kAlargado]}' != 'false';
        _hora = (int.tryParse('${mapa[_kHora] ?? 10}') ?? 10).clamp(0, 23);
        _resumo = resumo;
        _receitas = (lista as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminReceitas] load: $e');
      if (!mounted) return;
      setState(() {
        _error = humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _salvarDefinicoes() async {
    setState(() => _salvando = true);
    final supa = Supabase.instance.client;
    try {
      await supa.rpc('admin_update_setting',
          params: {'p_key': _kLigada, 'p_value': _ligada});
      await supa.rpc('admin_update_setting',
          params: {'p_key': _kAviso, 'p_value': _aviso});
      await supa.rpc('admin_update_setting',
          params: {'p_key': _kAlargado, 'p_value': _alargado});
      await supa.rpc('admin_update_setting',
          params: {'p_key': _kHora, 'p_value': _hora});
      _msg('Gravado.');
      await _load();
    } catch (e) {
      debugPrint('[AdminReceitas] salvar: $e');
      _msg(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _alternarAtiva(Map<String, dynamic> r, bool ativa) async {
    try {
      await Supabase.instance.client
          .from('receitas_do_dia')
          .update({'ativa': ativa}).eq('id', r['id']);
      await _logReceita(ativa ? 'receita_ativar' : 'receita_desativar',
          '${r['id']}', {'titulo': r['titulo']});
      await _load();
    } catch (e) {
      _msg(humanizeAdminRpcError(e));
    }
  }

  Future<void> _editar([Map<String, dynamic>? r]) async {
    final gravou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditorReceitaScreen(receita: r)),
    );
    if (gravou == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Receita do dia'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nova receita'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _load,
                            child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      _cartaoResumo(),
                      const SizedBox(height: 12),
                      _cartaoDefinicoes(),
                      const SizedBox(height: 16),
                      const Text('Receitas',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text(
                        'Sem data agendada, entram na rotação pela ordem. Com data, aparecem nesse dia.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      for (final r in _receitas) _linhaReceita(r),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoResumo() {
    final s = _resumo ?? const {};
    Widget numero(String rotulo, Object? v) => Expanded(
          child: Column(
            children: [
              Text('${v ?? 0}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(rotulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoje: ${s['receita_hoje'] ?? '— nenhuma receita ativa'}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                numero('pediram o aviso', s['avisos_ligados']),
                numero('avisos hoje', s['enviados_hoje']),
                numero('avisos 7 dias', s['enviados_7_dias']),
                numero('receitas ativas', s['receitas_ativas']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoDefinicoes() {
    final s = _resumo ?? const {};
    return AdminReceitaAvisoCard(
      ligada: _ligada,
      aviso: _aviso,
      alargado: _alargado,
      hora: _hora,
      salvando: _salvando,
      destinatarios: int.tryParse('${s['destinatarios_hoje'] ?? ''}'),
      avisoTitulo: s['aviso_titulo'] as String?,
      avisoCorpo: s['aviso_corpo'] as String?,
      onLigada: (v) => setState(() => _ligada = v),
      onAviso: (v) => setState(() => _aviso = v),
      onAlargado: (v) => setState(() => _alargado = v),
      onHora: (v) => setState(() => _hora = v),
      onSalvar: _salvarDefinicoes,
    );
  }

  Widget _linhaReceita(Map<String, dynamic> r) {
    final ativa = r['ativa'] == true;
    final agendada = DateTime.tryParse('${r['data_agendada'] ?? ''}');
    final nIng = (r['ingredientes'] is List) ? (r['ingredientes'] as List).length : 0;
    final quando = agendada != null
        ? 'agendada para ${_data(agendada)}'
        : 'na rotação (ordem ${r['ordem']})';
    return Card(
      child: ListTile(
        onTap: () => _editar(r),
        title: Text('${r['titulo']}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ativa ? null : AppColors.textSecondary)),
        subtitle: Text('$quando · $nIng ingredientes'),
        trailing: Switch(
          value: ativa,
          onChanged: (v) => _alternarAtiva(r, v),
        ),
      ),
    );
  }
}

/// Criar/editar uma receita. Ingredientes: uma linha por ingrediente, no
/// formato "Nome | quantidade | termo de pesquisa" (o termo é o que se procura
/// no supermercado; se faltar, usa-se o nome) | unidades no carrinho (1 se
/// faltar). Passos: um por linha.
class _EditorReceitaScreen extends StatefulWidget {
  const _EditorReceitaScreen({this.receita});
  final Map<String, dynamic>? receita;

  @override
  State<_EditorReceitaScreen> createState() => _EditorReceitaScreenState();
}

class _EditorReceitaScreenState extends State<_EditorReceitaScreen> {
  final _titulo = TextEditingController();
  final _resumo = TextEditingController();
  final _tempo = TextEditingController();
  final _doses = TextEditingController();
  final _foto = TextEditingController();
  final _ordem = TextEditingController();
  final _ingredientes = TextEditingController();
  final _passos = TextEditingController();
  DateTime? _agendada;
  bool _ativa = true;
  bool _salvando = false;

  bool get _nova => widget.receita == null;

  @override
  void initState() {
    super.initState();
    final r = widget.receita;
    if (r == null) {
      _ordem.text = '999';
      return;
    }
    _titulo.text = '${r['titulo'] ?? ''}';
    _resumo.text = '${r['resumo'] ?? ''}';
    _tempo.text = r['tempo_min'] == null ? '' : '${r['tempo_min']}';
    _doses.text = r['doses'] == null ? '' : '${r['doses']}';
    _foto.text = '${r['foto_url'] ?? ''}';
    _ordem.text = '${r['ordem'] ?? 0}';
    _agendada = DateTime.tryParse('${r['data_agendada'] ?? ''}');
    _ativa = r['ativa'] != false;
    _ingredientes.text = [
      for (final i in (r['ingredientes'] as List? ?? const []))
        if (i is Map)
          '${i['nome'] ?? ''} | ${i['quantidade'] ?? ''} | ${i['pesquisa'] ?? ''} | ${i['unidades'] ?? 1}',
    ].join('\n');
    _passos.text = [
      for (final p in (r['passos'] as List? ?? const [])) '$p',
    ].join('\n');
  }

  @override
  void dispose() {
    for (final c in [
      _titulo, _resumo, _tempo, _doses, _foto, _ordem, _ingredientes, _passos,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _agendada ?? hoje,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _agendada = d);
  }

  Future<void> _salvar() async {
    final titulo = _titulo.text.trim();
    final ingredientes = <Map<String, dynamic>>[];
    for (final linha in _ingredientes.text.split('\n')) {
      final partes = linha.split('|').map((e) => e.trim()).toList();
      if (partes.isEmpty || partes[0].isEmpty) continue;
      ingredientes.add({
        'nome': partes[0],
        'quantidade': partes.length > 1 ? partes[1] : '',
        'pesquisa': partes.length > 2 && partes[2].isNotEmpty
            ? partes[2]
            : partes[0].toLowerCase(),
        'unidades': (partes.length > 3 ? int.tryParse(partes[3]) ?? 1 : 1)
            .clamp(1, 20),
      });
    }
    final passos = _passos.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tempo = int.tryParse(_tempo.text.trim());
    final doses = int.tryParse(_doses.text.trim());
    if (titulo.length < 3 || titulo.length > 80) {
      return _msg('O título precisa ter entre 3 e 80 letras.');
    }
    if (ingredientes.isEmpty) return _msg('Coloque pelo menos 1 ingrediente.');
    if (passos.isEmpty) return _msg('Coloque pelo menos 1 passo.');
    if (tempo != null && (tempo < 1 || tempo > 600)) {
      return _msg('O tempo vai de 1 a 600 minutos.');
    }
    if (doses != null && (doses < 1 || doses > 20)) {
      return _msg('Pessoas vai de 1 a 20.');
    }

    final dados = <String, dynamic>{
      'titulo': titulo,
      'resumo': _resumo.text.trim().isEmpty ? null : _resumo.text.trim(),
      'tempo_min': tempo,
      'doses': doses,
      'foto_url': _foto.text.trim().isEmpty ? null : _foto.text.trim(),
      'ordem': int.tryParse(_ordem.text.trim()) ?? 0,
      'data_agendada': _agendada == null
          ? null
          : '${_agendada!.year.toString().padLeft(4, '0')}-${_agendada!.month.toString().padLeft(2, '0')}-${_agendada!.day.toString().padLeft(2, '0')}',
      'ativa': _ativa,
      'ingredientes': ingredientes,
      'passos': passos,
    };

    setState(() => _salvando = true);
    final supa = Supabase.instance.client;
    try {
      String id;
      if (_nova) {
        final row = await supa
            .from('receitas_do_dia')
            .insert(dados)
            .select('id')
            .single();
        id = '${row['id']}';
      } else {
        id = '${widget.receita!['id']}';
        await supa.from('receitas_do_dia').update(dados).eq('id', id);
      }
      await _logReceita(_nova ? 'receita_criar' : 'receita_editar', id,
          {'titulo': titulo, 'data_agendada': dados['data_agendada']});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[AdminReceitas] gravar: $e');
      final t = '$e';
      _msg(t.contains('data_agendada')
          ? 'Já existe uma receita agendada para esse dia.'
          : humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration dec(String rotulo, [String? ajuda]) => InputDecoration(
          labelText: rotulo,
          helperText: ajuda,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: _nova ? 'Nova receita' : 'Editar receita'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _titulo, decoration: dec('Título')),
          const SizedBox(height: 12),
          TextField(
              controller: _resumo,
              decoration: dec('Resumo (1 frase, opcional)')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                    controller: _tempo,
                    keyboardType: TextInputType.number,
                    decoration: dec('Tempo (min)')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: _doses,
                    keyboardType: TextInputType.number,
                    decoration: dec('Pessoas')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: _ordem,
                    keyboardType: TextInputType.number,
                    decoration: dec('Ordem')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _foto,
              decoration: dec('Foto (endereço da imagem, opcional)')),
          const SizedBox(height: 12),
          TextField(
            controller: _ingredientes,
            minLines: 5,
            maxLines: 12,
            decoration: dec('Ingredientes',
                'Um por linha: Nome | quantidade | termo de pesquisa | unidades no carrinho. Ex.: Atum em lata | 3 latas | atum em óleo | 3. '
                'Use termos específicos ("azeite virgem extra", não "azeite"): termos genéricos trazem produtos errados.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passos,
            minLines: 4,
            maxLines: 12,
            decoration: dec('Modo de preparo', 'Um passo por linha.'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_agendada == null
                ? 'Sem data — entra na rotação'
                : 'Agendada para ${_data(_agendada!)}'),
            trailing: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                    onPressed: _escolherData, child: const Text('Agendar')),
                if (_agendada != null)
                  TextButton(
                      onPressed: () => setState(() => _agendada = null),
                      child: const Text('Tirar data')),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ativa,
            onChanged: (v) => setState(() => _ativa = v),
            title: const Text('Ativa'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando…' : 'Salvar receita'),
          ),
        ],
      ),
    );
  }
}

/// Definições do aviso diário + pré-visualização do que vai sair (Bora Todo Dia,
/// 29/10/2026). Sem rede: recebe os valores e devolve as mudanças, por isso
/// testa-se sozinho. O texto do aviso vem do servidor (`_receita_aviso_corpo`),
/// nunca é reescrito aqui.
class AdminReceitaAvisoCard extends StatelessWidget {
  const AdminReceitaAvisoCard({
    super.key,
    required this.ligada,
    required this.aviso,
    required this.alargado,
    required this.hora,
    required this.salvando,
    required this.onLigada,
    required this.onAviso,
    required this.onAlargado,
    required this.onHora,
    required this.onSalvar,
    this.destinatarios,
    this.avisoTitulo,
    this.avisoCorpo,
  });

  final bool ligada;
  final bool aviso;
  final bool alargado;
  final int hora;
  final bool salvando;

  /// Quantas pessoas o aviso de hoje alcança (do servidor); `null` = desconhecido.
  final int? destinatarios;

  /// Título e texto exatos do aviso de hoje (do servidor); `null` = sem receita.
  final String? avisoTitulo;
  final String? avisoCorpo;

  final ValueChanged<bool> onLigada;
  final ValueChanged<bool> onAviso;
  final ValueChanged<bool> onAlargado;
  final ValueChanged<int> onHora;
  final VoidCallback onSalvar;

  String get _horaTexto => '${hora.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final temTexto = avisoCorpo != null && avisoCorpo!.isNotEmpty;
    final n = destinatarios;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('receita_admin_ligada'),
              value: ligada,
              onChanged: onLigada,
              title: const Text('Receita do dia ligada'),
              subtitle: const Text('Mostra o cartão na home do cliente.'),
            ),
            SwitchListTile(
              key: const Key('receita_admin_aviso'),
              value: aviso,
              onChanged: onAviso,
              title: const Text('Aviso diário ligado'),
              subtitle: Text(alargado
                  ? 'Chega a quem pediu, a quem tem sequência de check-in ativa e a quem aceitou promoções. Quem desligar no ecrã da receita nunca recebe.'
                  : 'Só chega a quem pediu o aviso no ecrã da receita (opt-in).'),
            ),
            SwitchListTile(
              key: const Key('receita_admin_alargado'),
              value: alargado,
              onChanged: aviso ? onAlargado : null,
              title: const Text('Alargar a quem tem sequência ou aceitou promoções'),
              subtitle: const Text(
                  'Desligado: só recebe quem ligou o aviso. Contas demo e de teste nunca recebem.'),
            ),
            ListTile(
              title: const Text('Hora do aviso (Lisboa)'),
              subtitle: const Text(
                  'O check-in avisa às 11:00: manter a receita noutra hora evita duas notificações seguidas.'),
              trailing: DropdownButton<int>(
                key: const Key('receita_admin_hora'),
                value: hora,
                items: [
                  for (var h = 0; h < 24; h++)
                    DropdownMenuItem(
                        value: h,
                        child: Text('${h.toString().padLeft(2, '0')}:00')),
                ],
                onChanged: (v) => onHora(v ?? hora),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                key: const Key('receita_admin_previa'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pré-visualização do aviso de hoje',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    if (temTexto) ...[
                      Text(avisoTitulo ?? 'Receita do dia',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(avisoCorpo!, style: const TextStyle(fontSize: 13)),
                    ] else
                      const Text(
                          'Não há receita ativa para hoje: o aviso não sai.',
                          style: TextStyle(fontSize: 13)),
                    if (n != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        !ligada || !aviso
                            ? 'O aviso está desligado: não sai a ninguém.'
                            : 'Chega a $n ${n == 1 ? 'pessoa' : 'pessoas'} às $_horaTexto (os valores gravados; carrega em Salvar para aplicar mudanças).',
                        key: const Key('receita_admin_destinatarios'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  key: const Key('receita_admin_salvar'),
                  onPressed: salvando ? null : onSalvar,
                  child: Text(salvando ? 'Salvando…' : 'Salvar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
