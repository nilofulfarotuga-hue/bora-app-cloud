import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart';

/// PAINEL ADMIN (PT-BR) — "Chamada de reforço (estafetas desligados que
/// aceitaram)", dentro das Configurações de Despacho.
///
/// Se nenhum estafeta online aceitar, o sistema pode chamar, um de cada vez,
/// quem está DESLIGADO mas ligou no telemóvel "Aceito chamadas de reforço
/// quando estou desligado". Nasce desligado (decisão do Danilo de 10/10).
///
/// Lê/grava `platform_settings` pelas RPCs de sempre (`admin_list_settings` /
/// `admin_update_setting` — esta já regista no log de auditoria) e a lista de
/// quem consentiu por `admin_reforco_lista`. Se a migração 20261010063000
/// ainda não estiver aplicada, mostra "Ainda não ativo no servidor" e desliga
/// os controles.
class AdminReforcoSection extends StatefulWidget {
  const AdminReforcoSection({
    super.key,
    this.listarDefinicoes,
    this.listarPessoas,
    this.gravar,
  });

  /// Só para testes: substituem as chamadas ao servidor.
  final Future<List<Map<String, dynamic>>> Function()? listarDefinicoes;
  final Future<Object?> Function()? listarPessoas;
  final Future<void> Function(String chave, Object valor)? gravar;

  @override
  State<AdminReforcoSection> createState() => _AdminReforcoSectionState();
}

class _NumSpec {
  const _NumSpec(this.chave, this.rotulo, this.unidade, this.explicacao,
      this.min, this.max, this.padrao);
  final String chave;
  final String rotulo;
  final String unidade;
  final String explicacao;
  final int min;
  final int max;
  final int padrao;
}

class _AdminReforcoSectionState extends State<AdminReforcoSection> {
  bool _loading = true;
  String? _erro;
  final Map<String, dynamic> _valores = {};
  List<String> _faltamEntregas = const [];
  List<String> _faltamTvde = const [];

  bool _listaSemServidor = false;
  String? _listaErro;
  List<Map<String, dynamic>> _pessoas = const [];
  List<String> _ordem = const [];
  List<String> _ordemOriginal = const [];
  bool _gravandoOrdem = false;

  static const List<_NumSpec> _numeros = [
    _NumSpec(
        'dispatch_voltas_online_antes_forcado',
        'Voltas aos online antes do reforço',
        'voltas',
        'Quantas voltas completas aos estafetas online antes de chamar quem '
            'está desligado.',
        1,
        10,
        2),
    _NumSpec(
        'dispatch_forcado_tentativas',
        'Desligados chamados por pedido (entregas e Favores)',
        'pessoas',
        'Quantos estafetas desligados (que consentiram) são chamados, um de '
            'cada vez, antes de voltar aos online.',
        0,
        10,
        2),
    _NumSpec(
        'tvde_forcado_tentativas',
        'Desligados chamados por corrida (TVDE)',
        'pessoas',
        'Quantos motoristas desligados (que consentiram) são chamados antes '
            'de a corrida ficar "sem motorista".',
        0,
        10,
        2),
    _NumSpec(
        'dispatch_forcado_max_por_dia',
        'Máximo de reforços por pessoa por dia',
        'chamadas',
        'Teto de chamadas de reforço a uma mesma pessoa num dia (Lisboa). '
            'Vale para entregas, Favores e TVDE.',
        1,
        10,
        3),
    _NumSpec(
        'dispatch_voltas_online_depois_forcado',
        'Voltas aos online depois do reforço',
        'voltas',
        'Depois do reforço, quantas voltas aos online antes de dizer "não há '
            'estafeta".',
        0,
        10,
        1),
    _NumSpec(
        'dispatch_forcado_visto_horas',
        'Só quem abriu o app nas últimas',
        'horas',
        'Só entra no reforço quem tem aparelho registrado e abriu o app neste '
            'prazo (168 h = 7 dias). Vale também para o TVDE.',
        1,
        720,
        168),
    _NumSpec(
        'dispatch_cancelar_limite_absoluto_segundos',
        'Limite absoluto para cancelar',
        'segundos',
        'Passado este tempo à procura, o pedido pode ser cancelado mesmo a '
            'meio das fases (3600 s = 1 hora).',
        600,
        7200,
        3600),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _listarDefinicoes() async {
    final res = await Supabase.instance.client
        .rpc('admin_list_settings', params: {'p_category': null});
    return (res as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<Object?> _listarPessoas() =>
      Supabase.instance.client.rpc('admin_reforco_lista');

  Future<void> _gravar(String chave, Object valor) async {
    await Supabase.instance.client
        .rpc('admin_update_setting', params: {'p_key': chave, 'p_value': valor});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
      _listaErro = null;
      _listaSemServidor = false;
    });
    try {
      final linhas = await (widget.listarDefinicoes ?? _listarDefinicoes)();
      _valores.clear();
      for (final r in linhas) {
        final k = r['key']?.toString();
        if (k == null) continue;
        if (kChavesReforcoEntregas.contains(k) || kChavesReforcoTvde.contains(k)) {
          _valores[k] = r['value'];
        }
      }
      _faltamEntregas = chavesEmFalta(kChavesReforcoEntregas, _valores.keys);
      _faltamTvde = chavesEmFalta(kChavesReforcoTvde, _valores.keys);
    } catch (e) {
      _erro = servidorAindaSemIsto(e) ? null : e.toString();
      _faltamEntregas = List.of(kChavesReforcoEntregas);
      _faltamTvde = List.of(kChavesReforcoTvde);
    }

    try {
      final res = await (widget.listarPessoas ?? _listarPessoas)();
      final m = (res as Map).cast<String, dynamic>();
      if (m['ok'] != true) {
        throw Exception(m['erro'] ?? m['error'] ?? 'resposta inesperada');
      }
      _pessoas = ((m['itens'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      _ordem = ordemInicialConsentidos(_pessoas);
      _ordemOriginal = List.of(_ordem);
    } catch (e) {
      _pessoas = const [];
      _ordem = const [];
      _ordemOriginal = const [];
      _listaSemServidor = servidorAindaSemIsto(e);
      _listaErro = _listaSemServidor ? null : e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _ativoEntregas => _faltamEntregas.isEmpty;
  bool get _ativoTvde => _faltamTvde.isEmpty;

  bool _bool(String k) {
    final v = _valores[k];
    return v == true || '$v' == 'true';
  }

  int? _num(String k) {
    final v = _valores[k];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : AppColors.success,
    ));
  }

  Future<bool> _gravarUm(String chave, Object valor, String feito) async {
    try {
      await (widget.gravar ?? _gravar)(chave, valor);
      _aviso(feito);
      return true;
    } catch (e) {
      _aviso(
          servidorAindaSemIsto(e)
              ? '$kAindaNaoAtivo ($chave).'
              : 'Erro ao salvar: $e',
          erro: true);
      return false;
    }
  }

  Future<void> _alternar(String chave, bool novo, String oQue) async {
    if (novo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Ligar a chamada de reforço — $oQue?'),
          content: const Text(
            'A partir de agora, se nenhum estafeta online aceitar, o sistema '
            'chama, um de cada vez, quem está desligado MAS ligou o interruptor '
            'no telemóvel. Quem não ligou nunca é chamado. Recusar nunca '
            'penaliza. Muda em tempo real.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Ligar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (await _gravarUm(chave, novo,
        novo ? 'Chamada de reforço ligada ($oQue).' : 'Chamada de reforço desligada ($oQue).')) {
      await _load();
    }
  }

  Future<void> _editarNumero(_NumSpec s) async {
    final atual = _num(s.chave) ?? s.padrao;
    final ctrl = TextEditingController(text: '$atual');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.rotulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.explicacao, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Valor (${s.unidade})',
                helperText:
                    'Mín: ${s.min} · Máx: ${s.max} · Padrão: ${s.padrao}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final v = int.tryParse(ctrl.text.trim());
    if (v == null || v < s.min || v > s.max) {
      _aviso('Valor fora do intervalo (${s.min}..${s.max}).', erro: true);
      return;
    }
    if (await _gravarUm(s.chave, v, '${s.rotulo}: $v ${s.unidade}.')) {
      await _load();
    }
  }

  Future<void> _editarHora(String chave, String rotulo, String padrao) async {
    final atual = horaHhMm(_valores[chave]) ?? padrao;
    final partes = atual.split(':');
    final escolhida = await showTimePicker(
      context: context,
      helpText: '$rotulo (hora de Lisboa)',
      initialTime: TimeOfDay(
          hour: int.parse(partes[0]), minute: int.parse(partes[1])),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (escolhida == null) return;
    final hhmm = '${escolhida.hour.toString().padLeft(2, '0')}:'
        '${escolhida.minute.toString().padLeft(2, '0')}';
    if (await _gravarUm(chave, hhmm, '$rotulo: $hhmm.')) await _load();
  }

  Future<void> _salvarOrdem() async {
    setState(() => _gravandoOrdem = true);
    var tudoBem = true;
    final alvos = <String>[
      if (_valores.containsKey('dispatch_forcado_prioridade'))
        'dispatch_forcado_prioridade',
      if (_valores.containsKey('tvde_forcado_prioridade'))
        'tvde_forcado_prioridade',
    ];
    for (final chave in alvos) {
      final nova = novaPrioridade(_ordem, listaDeIds(_valores[chave]));
      try {
        await (widget.gravar ?? _gravar)(chave, nova);
      } catch (e) {
        tudoBem = false;
        _aviso('Erro ao salvar a ordem ($chave): $e', erro: true);
      }
    }
    if (tudoBem) _aviso('Ordem salva (entregas, Favores e TVDE).');
    if (mounted) setState(() => _gravandoOrdem = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final semNada = !_ativoEntregas && !_ativoTvde;
    final ordemMudou = _ordem.join(',') != _ordemOriginal.join(',');
    final podeOrdenar = _valores.containsKey('dispatch_forcado_prioridade') ||
        _valores.containsKey('tvde_forcado_prioridade');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryWash,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.campaign_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chamada de reforço (estafetas desligados que aceitaram)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ]),
              SizedBox(height: 6),
              Text(
                'Se nenhum estafeta online aceitar, o sistema chama, um de cada '
                'vez, quem está DESLIGADO mas ligou no telemóvel o interruptor '
                '"Aceito chamadas de reforço quando estou desligado". Nasce '
                'DESLIGADO aqui e no telemóvel de cada um: só é chamado quem '
                'ligou. Recusar nunca penaliza.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (_erro != null) ...[
          const SizedBox(height: 8),
          Text('Não deu para ler as definições: $_erro',
              style: const TextStyle(fontSize: 12, color: AppColors.error)),
        ] else if (semNada || !_ativoEntregas || !_ativoTvde) ...[
          const SizedBox(height: 8),
          _AvisoServidor(
            texto: semNada
                ? kAindaNaoAtivo
                : '$kAindaNaoAtivo: ${!_ativoEntregas ? 'parte das definições de entregas/Favores' : 'definições do TVDE'}',
          ),
        ],
        const SizedBox(height: 8),
        _cartao([
          SwitchListTile(
            secondary: const Icon(Icons.delivery_dining),
            title: const Text('Ligado para entregas e Favores'),
            subtitle: const Text(
                'Nasce desligado. Só chama quem ligou o interruptor no '
                'telemóvel (definição dispatch_forcado_ligado).'),
            value: _bool('dispatch_forcado_ligado'),
            onChanged: _ativoEntregas
                ? (v) => _alternar('dispatch_forcado_ligado', v,
                    'entregas e Favores')
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_taxi_outlined),
            title: const Text('Ligado para TVDE'),
            subtitle: const Text(
                'Antes de a corrida ficar "sem motorista", chama motoristas '
                'desligados que consentiram (definição tvde_forcado_ligado).'),
            value: _bool('tvde_forcado_ligado'),
            onChanged: _ativoTvde
                ? (v) => _alternar('tvde_forcado_ligado', v, 'TVDE')
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timer_off_outlined),
            title: const Text('Cancelar só depois de todas as fases'),
            subtitle: const Text(
                'O cancelamento automático por tempo espera o reforço acabar '
                '(só vale com a chamada de reforço ligada).'),
            value: _bool('dispatch_cancelar_so_no_fim'),
            onChanged: _ativoEntregas
                ? (v) async {
                    if (await _gravarUm('dispatch_cancelar_so_no_fim', v,
                        'Cancelar só no fim: ${v ? 'sim' : 'não'}.')) {
                      await _load();
                    }
                  }
                : null,
          ),
        ]),
        const SizedBox(height: 8),
        _cartao([
          for (final s in _numeros)
            ListTile(
              enabled: (kChavesReforcoTvde.contains(s.chave)
                  ? _ativoTvde
                  : _ativoEntregas),
              title: Text(s.rotulo,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle:
                  Text(s.explicacao, style: const TextStyle(fontSize: 12)),
              trailing: Text(
                '${_num(s.chave) ?? s.padrao} ${s.unidade}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => _editarNumero(s),
            ),
          ListTile(
            enabled: _ativoEntregas,
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Começa às (hora de Lisboa)'),
            subtitle: const Text('Antes desta hora ninguém desligado é chamado.'),
            trailing: Text(
                horaHhMm(_valores['dispatch_forcado_horario_inicio']) ?? '08:00',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _editarHora(
                'dispatch_forcado_horario_inicio', 'Começa às', '08:00'),
          ),
          ListTile(
            enabled: _ativoEntregas,
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Termina às (hora de Lisboa)'),
            subtitle: const Text('A partir desta hora já não se chama ninguém desligado.'),
            trailing: Text(
                horaHhMm(_valores['dispatch_forcado_horario_fim']) ?? '23:00',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () =>
                _editarHora('dispatch_forcado_horario_fim', 'Termina às', '23:00'),
          ),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text('Quem pode ser chamado (ordem)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (ordemMudou)
              FilledButton.icon(
                onPressed: (_gravandoOrdem || !podeOrdenar) ? null : _salvarOrdem,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_gravandoOrdem ? 'Salvando…' : 'Salvar ordem'),
              ),
          ],
        ),
        const Text(
          'Só quem ligou o interruptor (verde) entra no reforço, pela ordem '
          'abaixo. A mesma ordem é gravada para entregas/Favores e para o TVDE.',
          style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
        ),
        const SizedBox(height: 8),
        if (_listaSemServidor)
          const _AvisoServidor(texto: kAindaNaoAtivo)
        else if (_listaErro != null)
          Text('Não deu para carregar a lista: $_listaErro',
              style: const TextStyle(fontSize: 12, color: AppColors.error))
        else if (_pessoas.isEmpty)
          const Text('Nenhum estafeta aprovado.',
              style: TextStyle(color: AppColors.textSubtle))
        else
          _cartao([
            for (var i = 0; i < _ordem.length; i++)
              _linhaPessoa(_pessoa(_ordem[i]), posicao: i, podeOrdenar: podeOrdenar),
            for (final p in _pessoas)
              if (p['consentiu'] != true) _linhaPessoa(p),
          ]),
      ],
    );
  }

  Map<String, dynamic> _pessoa(String userId) => _pessoas.firstWhere(
      (p) => '${p['user_id']}' == userId,
      orElse: () => {'user_id': userId, 'nome': '(sem nome)'});

  Widget _linhaPessoa(Map<String, dynamic> p,
      {int? posicao, bool podeOrdenar = false}) {
    final consentiu = p['consentiu'] == true;
    final hoje = (p['reforcos_hoje'] as num?)?.toInt() ?? 0;
    final online = p['online'] == true;
    final visto = p['visto_em'] == null ? null : dataHoraLisboa(p['visto_em']);
    final partes = <String>[
      if ('${p['veiculo'] ?? ''}'.isNotEmpty) '${p['veiculo']}',
      online ? 'online agora' : 'desligado',
      if (visto != null) 'visto $visto',
      'reforços hoje: $hoje',
      if (!consentiu) 'não ligou o interruptor',
    ];
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: consentiu
            ? AppColors.primary
            : AppColors.textSubtle.withValues(alpha: .25),
        child: Text(
          posicao == null ? '–' : '${posicao + 1}º',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: consentiu ? Colors.white : AppColors.textSecondary),
        ),
      ),
      title: Text('${p['nome'] ?? '(sem nome)'}',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: consentiu ? AppColors.textPrimary : AppColors.textSubtle)),
      subtitle: Text(partes.join(' · '), style: const TextStyle(fontSize: 12)),
      trailing: posicao == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Subir',
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: (!podeOrdenar || posicao == 0)
                      ? null
                      : () => setState(
                          () => _ordem = moverNaLista(_ordem, posicao, -1)),
                ),
                IconButton(
                  tooltip: 'Descer',
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  onPressed: (!podeOrdenar || posicao == _ordem.length - 1)
                      ? null
                      : () => setState(
                          () => _ordem = moverNaLista(_ordem, posicao, 1)),
                ),
              ],
            ),
    );
  }

  // Material (e não Container com cor): o ListTile pinta o fundo e o toque
  // no Material mais próximo — com um DecoratedBox pelo meio, o Flutter
  // assinala que o toque fica invisível.
  Widget _cartao(List<Widget> filhos) => Material(
        color: AppColors.card,
        elevation: 1,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(children: filhos),
      );
}

class _AvisoServidor extends StatelessWidget {
  const _AvisoServidor({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.textSubtle.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
