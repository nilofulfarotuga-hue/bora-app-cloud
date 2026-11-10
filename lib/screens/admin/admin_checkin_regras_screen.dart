// Regras do check-in (Bloco G da missão fechar-tudo-2026-11-10). PT-BR.
// Paridade admin das regras novas do check-in diário. Aqui o Danilo:
//  - vê o CUSTO DO MÊS dos prêmios contra o TETO, com aviso aos 80% (R6);
//  - liga/desliga cada regra, com a explicação de uma linha (R2 a R8);
//  - vê quem está em que dia da escada (só sequências a correr);
//  - vê os prêmios guardados / à espera de pedido / levantados / usados;
//  - edita a escada: dia, prêmio, loja, foto, valor e custo de cada degrau.
// Servidor: admin_checkin_regras_resumo, admin_checkin_regra_definir e
// admin_checkin_degrau_editar (guarda public.is_admin(); tudo fica no registro).
// Os degraus de DESCONTO (R7) ficam desligados: o servidor recusa ligá-los até o
// desconto entrar no pedido (proposta em docs/propostas/fechar-tudo-2026-11-10/).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/checkin_regras.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../widgets/checkin/premio_foto.dart';
import '_admin_rpc_errors.dart';

/// Uma regra no painel: a chave em platform_settings, o rótulo e a explicação.
class RegraCheckin {
  const RegraCheckin(this.chave, this.regra, this.titulo, this.explicacao, {this.numero = false, this.euros = false});

  final String chave;
  final String regra;
  final String titulo;
  final String explicacao;
  final bool numero;

  /// Número guardado em cêntimos e mostrado em euros.
  final bool euros;
}

/// As regras R2-R8, pela ordem do painel, com a explicação de uma linha.
const List<RegraCheckin> kRegrasCheckin = [
  RegraCheckin('checkin_marco_exige_pedido_pago', 'R2', 'Prêmio só com 1 pedido pago',
      'Sem pedido pago nos últimos 30 dias o prêmio fica guardado ("Falta 1 pedido") e desbloqueia sozinho quando a pessoa comprar.'),
  RegraCheckin('checkin_pedido_conta_tvde', 'R2', 'Corrida TVDE conta como pedido',
      'Desligado enquanto o Bora Motorista estiver fechado.'),
  RegraCheckin('checkin_marco_pedido_pago_dias', 'R2', 'Janela do pedido pago (dias)',
      'Quantos dias para trás conta um pedido pago.', numero: true),
  RegraCheckin('checkin_marco_espera_pedido_dias', 'R2', 'Prêmio espera o pedido até (dias)',
      'Passado este prazo sem pedido, o prêmio guardado expira.', numero: true),
  RegraCheckin('checkin_escada_ativa', 'R3', 'Escada de prêmios',
      'Um prêmio por sequência. "Quero este" leva o prêmio e a escada volta ao dia 1; "Continuar" troca por um maior.'),
  RegraCheckin('checkin_quero_este_recomeca_semana', 'R3', '"Quero este" recomeça também os tokens',
      'Desligado: os tokens diários (5,5,10,10,15,15,40) seguem o seu ciclo de 7 dias.'),
  RegraCheckin('checkin_sugestao_ativa', 'R4', 'A melhor sugestão',
      'Guarda sempre o prêmio mais valioso a que a pessoa chegou; entre iguais, o da loja onde ela mais pediu.'),
  RegraCheckin('checkin_perdao_ativo', 'R5', 'Perdão de 1 dia por mês',
      'Perdoa sozinho um dia falhado (gelo no calendário), só a quem tem pedido pago nos últimos 30 dias.'),
  RegraCheckin('checkin_perdao_por_mes', 'R5', 'Perdões por mês', 'Quantos dias falhados se perdoam por mês.',
      numero: true),
  RegraCheckin('checkin_premios_tecto_custo_ativo', 'R6', 'Teto de custo mensal',
      'Passando o teto, o prêmio fica guardado para o mês seguinte.'),
  RegraCheckin('checkin_premios_tecto_custo_cents', 'R6', 'Teto do mês (€)',
      'O que a Bora paga às lojas pelos prêmios num mês.', numero: true, euros: true),
  RegraCheckin('checkin_premios_tecto_aviso_pct', 'R6', 'Aviso ao chegar a (%)',
      'Aviso no painel quando o custo do mês chega a esta percentagem do teto.', numero: true),
  RegraCheckin('checkin_lembrete_hora_habitual', 'R8', 'Lembrete à hora habitual',
      'Um lembrete por dia, à hora a que a pessoa costuma fazer o check-in. Desligado: 11h e 20h só a quem fez ontem.'),
  RegraCheckin('checkin_lembrete_max_falhas', 'R8', 'Para depois de falhar (dias seguidos)',
      'O lembrete para quando a pessoa falha este número de dias seguidos (1 = regra de 18/10).', numero: true),
];

class AdminCheckinRegrasScreen extends StatefulWidget {
  const AdminCheckinRegrasScreen({super.key, this.carregar, this.definir, this.editarDegrau});

  /// Por omissão, `admin_checkin_regras_resumo()`.
  final Future<Map<String, dynamic>> Function()? carregar;

  /// Por omissão, `admin_checkin_regra_definir(key, valor)`.
  final Future<void> Function(String chave, Object valor)? definir;

  /// Por omissão, `admin_checkin_degrau_editar(chave, campos)`.
  final Future<void> Function(String chave, Map<String, dynamic> campos)? editarDegrau;

  @override
  State<AdminCheckinRegrasScreen> createState() => _AdminCheckinRegrasScreenState();
}

class _AdminCheckinRegrasScreenState extends State<AdminCheckinRegrasScreen> {
  Map<String, dynamic>? _r;
  String? _erro;
  bool _carregando = true;
  final Map<String, TextEditingController> _numeros = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _numeros.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _doServidor() async {
    final r = await Supabase.instance.client.rpc('admin_checkin_regras_resumo');
    return (r as Map).cast<String, dynamic>();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await (widget.carregar ?? _doServidor)();
      if (!mounted) return;
      setState(() {
        _r = r;
        _carregando = false;
        for (final regra in kRegrasCheckin.where((x) => x.numero)) {
          final v = _valor(regra.chave);
          final texto = v == null
              ? ''
              : regra.euros
                  ? ((num.tryParse('$v') ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')
                  : '$v';
          (_numeros[regra.chave] ??= TextEditingController()).text = texto;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  Map<String, dynamic> get _defs => ((_r?['definicoes'] as Map?) ?? const {}).cast<String, dynamic>();

  Object? _valor(String chave) => (_defs[chave] as Map?)?['valor'];

  /// A explicação de uma linha (PT-BR, do painel). A do servidor fica para a
  /// lista geral de definições.
  String _explicacao(RegraCheckin r) => r.explicacao;

  Future<void> _gravar(String chave, Object valor) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (widget.definir ??
          (k, v) => Supabase.instance.client.rpc('admin_checkin_regra_definir', params: {'p_key': k, 'p_valor': v}))(
        chave,
        valor,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Salvo (fica no registro).')));
      await _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e)), backgroundColor: Colors.red));
    }
  }

  void _gravarNumero(RegraCheckin r) {
    final t = (_numeros[r.chave]?.text ?? '').trim().replaceAll(',', '.');
    final n = num.tryParse(t);
    if (n == null || n < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escreve um número.')));
      return;
    }
    _gravar(r.chave, r.euros ? (n * 100).round() : n.round());
  }

  int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Regras do check-in'),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    key: const Key('admin_checkin_regras_lista'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _secao('Custo do mês × teto (R6)', [_custoView()]),
                      _secao('Regras (R2 a R8)', [
                        for (final r in kRegrasCheckin) _regraView(r),
                        _r7View(),
                      ]),
                      _secao('Quem está em que dia', [_porDiaView()]),
                      _secao('Prêmios', [_premiosView()]),
                      _secao('Escada (toque para editar)', [_escadaView()]),
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

  Widget _custoView() {
    final r = _r!;
    final custo = _int(r['custo_mes_cents']);
    final tecto = _int(r['tecto_cents']);
    final aviso = _int(r['aviso_pct']) == 0 ? 80 : _int(r['aviso_pct']);
    final n = nivelTecto(custoCents: custo, tectoCents: tecto, avisoPct: aviso, ativo: r['tecto_ativo'] != false);
    final cor = switch (n.nivel) {
      NivelTecto.esgotado => AppColors.error,
      NivelTecto.aviso => AppColors.warning,
      _ => AppColors.primary,
    };
    return Column(
      key: const Key('admin_checkin_custo'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tecto > 0 ? '${valorEmEuros(custo).isEmpty ? '0,00 €' : valorEmEuros(custo)} de ${valorEmEuros(tecto)}' : '${valorEmEuros(custo).isEmpty ? '0,00 €' : valorEmEuros(custo)} (sem teto)',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor),
        ),
        const SizedBox(height: 6),
        if (n.pct != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (n.pct! / 100).clamp(0.0, 1.0),
              minHeight: 10,
              color: cor,
              backgroundColor: const Color(0xFFE5E7EB),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Mês ${r['mes'] ?? ''}: prêmios ativados e usados neste mês (o que a Bora paga às lojas). '
          'Guardados, à espera de pedido e expirados não contam.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (n.nivel == NivelTecto.aviso || n.nivel == NivelTecto.esgotado) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('admin_checkin_tecto_aviso'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: n.nivel == NivelTecto.esgotado ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              n.nivel == NivelTecto.esgotado
                  ? 'Teto atingido: os prêmios novos ficam guardados para o mês seguinte.'
                  : 'Atenção: o custo dos prêmios já está em ${n.pct}% do teto.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _regraView(RegraCheckin r) {
    final v = _valor(r.chave);
    final etiqueta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
      child: Text(r.regra, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
    );
    if (!r.numero) {
      return SwitchListTile(
        key: Key('admin_regra_${r.chave}'),
        contentPadding: EdgeInsets.zero,
        value: v == true,
        activeThumbColor: AppColors.primary,
        onChanged: v == null ? null : (x) => _gravar(r.chave, x),
        title: Row(children: [etiqueta, Expanded(child: Text(r.titulo))]),
        subtitle: Text(v == null ? 'Definição ainda não existe no servidor.' : _explicacao(r)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [etiqueta, Expanded(child: Text(r.titulo))]),
                const SizedBox(height: 2),
                Text(_explicacao(r), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 86,
            child: TextField(
              key: Key('admin_regra_${r.chave}'),
              controller: _numeros[r.chave] ??= TextEditingController(),
              enabled: v != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(isDense: true, suffixText: r.euros ? '€' : null),
              onSubmitted: (_) => _gravarNumero(r),
            ),
          ),
          IconButton(
            tooltip: 'Salvar',
            icon: const Icon(Icons.save_outlined),
            onPressed: v == null ? null : () => _gravarNumero(r),
          ),
        ],
      ),
    );
  }

  Widget _r7View() {
    final d = ((_r?['descontos'] as Map?) ?? const {}).cast<String, dynamic>();
    return ListTile(
      key: const Key('admin_regra_r7'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline),
      title: const Text('R7 · Degraus de desconto (Continente, Mercadona)'),
      subtitle: Text(
        '${_int(d['ligados'])} de ${_int(d['total'])} ligados. Ficam desligados até o pedido levar o vale de desconto '
        '(proposta pronta em docs/propostas/fechar-tudo-2026-11-10). Liga quando o Danilo disser.',
      ),
    );
  }

  Widget _porDiaView() {
    final lista = ((_r?['por_dia'] as List?) ?? const []).whereType<Map>().toList();
    if (lista.isEmpty) return const Text('Ninguém com sequência a correr (fez hoje ou ontem).');
    final maximo = lista.fold<int>(1, (m, x) => _int(x['pessoas']) > m ? _int(x['pessoas']) : m);
    return Column(
      key: const Key('admin_checkin_por_dia'),
      children: [
        for (final x in lista)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 56, child: Text('Dia ${x['dia']}', style: const TextStyle(fontSize: 12.5))),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (_int(x['pessoas']) / maximo).clamp(0.05, 1.0),
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 28, child: Text('${x['pessoas']}', textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _premiosView() {
    final p = ((_r?['premios'] as Map?) ?? const {}).cast<String, dynamic>();
    Widget item(String rotulo, Object? n, {Key? key}) => Chip(
          key: key,
          label: Text('$rotulo: ${_int(n)}'),
          backgroundColor: const Color(0xFFF0FDF4),
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        item('Guardados na escada', p['guardados_escada'], key: const Key('admin_premios_guardados')),
        item('À espera de pedido', p['a_espera_pedido'], key: const Key('admin_premios_espera')),
        item('Guardados pelo teto', p['guardados_teto']),
        item('Por usar', p['por_usar']),
        item('Levantados no mês', p['levantados_mes'], key: const Key('admin_premios_levantados')),
        item('Usados no mês', p['usados_mes']),
        item('Perdões no mês', _r?['perdoes_mes']),
        item('Lembretes hoje', _r?['lembretes_hoje']),
        item('Lembretes desligados', _r?['lembretes_desligados']),
      ],
    );
  }

  Widget _escadaView() {
    final degraus = ((_r?['degraus'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (degraus.isEmpty) return const Text('Sem degraus.');
    return Column(
      key: const Key('admin_checkin_escada'),
      children: [
        for (final d in degraus)
          ListTile(
            key: Key('admin_degrau_${d['chave']}'),
            contentPadding: EdgeInsets.zero,
            leading: PremioFoto(url: d['foto_url'] as String?, tipo: '${d['tipo'] ?? 'produto'}', tamanho: 44, redonda: false),
            title: Text('Dia ${d['dia']} — ${d['titulo'] ?? ''}'),
            subtitle: Text([
              if (d['loja_nome'] != null) '${d['loja_nome']}',
              if (valorEmEuros(_int(d['valor_cents'])).isNotEmpty) 'valor ${valorEmEuros(_int(d['valor_cents']))}',
              if (valorEmEuros(_int(d['custo_cents'])).isNotEmpty) 'custo ${valorEmEuros(_int(d['custo_cents']))}',
              if (d['ativo'] == false) 'DESLIGADO',
            ].join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editarDegrau(d),
          ),
      ],
    );
  }

  Future<void> _editarDegrau(Map<String, dynamic> d) async {
    final dia = TextEditingController(text: '${d['dia'] ?? ''}');
    final titulo = TextEditingController(text: '${d['titulo'] ?? ''}');
    final loja = TextEditingController(text: '${d['loja_id'] ?? ''}');
    final produto = TextEditingController(text: '${d['produto_id'] ?? ''}');
    final foto = TextEditingController(text: '${d['foto_escolhida'] ?? ''}');
    String eur(Object? c) => c == null ? '' : ((num.tryParse('$c') ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',');
    final valor = TextEditingController(text: eur(d['valor_cents']));
    final custo = TextEditingController(text: eur(d['custo_cents']));
    var ativo = d['ativo'] != false;
    final desconto = d['tipo'] == 'desconto';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Degrau ${d['chave']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: dia, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dia')),
                TextField(controller: titulo, decoration: const InputDecoration(labelText: 'Prêmio (o que o cliente lê, PT-PT)')),
                TextField(controller: loja, decoration: const InputDecoration(labelText: 'Loja (id)')),
                if (d['tipo'] == 'produto')
                  TextField(controller: produto, decoration: const InputDecoration(labelText: 'Produto-prêmio (id)')),
                TextField(
                  controller: foto,
                  decoration: const InputDecoration(
                    labelText: 'Foto (https://, opcional)',
                    helperText: 'Vazio = foto do produto; sem produto, a foto da loja. Só fotos reais.',
                  ),
                ),
                TextField(controller: valor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor para o cliente (€)')),
                TextField(controller: custo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Custo para a Bora (€)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ativo,
                  onChanged: desconto ? null : (v) => setD(() => ativo = v),
                  title: const Text('Ligado'),
                  subtitle: desconto ? const Text('Desconto: fica desligado (R7).') : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    int? cents(TextEditingController c) {
      final n = num.tryParse(c.text.trim().replaceAll(',', '.'));
      return n == null ? null : (n * 100).round();
    }

    final campos = <String, dynamic>{
      if (int.tryParse(dia.text.trim()) != null) 'dia': int.parse(dia.text.trim()),
      if (titulo.text.trim().isNotEmpty) 'titulo': titulo.text.trim(),
      if (loja.text.trim().isNotEmpty && loja.text.trim() != '${d['loja_id'] ?? ''}') 'loja_id': loja.text.trim(),
      if (produto.text.trim().isNotEmpty && produto.text.trim() != '${d['produto_id'] ?? ''}') 'produto_id': produto.text.trim(),
      'foto_url': foto.text.trim(),
      if (cents(valor) != null) 'valor_cents': cents(valor),
      if (cents(custo) != null) 'custo_cents': cents(custo),
      if (!desconto) 'ativo': ativo,
    };
    for (final c in [dia, titulo, loja, produto, foto, valor, custo]) {
      c.dispose();
    }
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (widget.editarDegrau ??
          (k, c) => Supabase.instance.client.rpc('admin_checkin_degrau_editar', params: {'p_chave': k, 'p_campos': c}))(
        '${d['chave']}',
        campos,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Degrau salvo (fica no registro).')));
      await _carregar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e)), backgroundColor: Colors.red));
    }
  }
}
