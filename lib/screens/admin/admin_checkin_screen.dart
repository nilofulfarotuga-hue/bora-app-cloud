// Check-in diário (Bora Todo Dia, novidade n.º 1 — 13/10/2026). PT-BR.
// O cliente abre o app todo dia e ganha tokens numa sequência de 7 dias
// (Dia 1..7 = 5,5,10,10,15,15,40). Aqui o Danilo:
//  - liga/desliga o check-in e os dois lembretes (11h e 20h de Lisboa);
//  - muda os 7 valores e a validade dos tokens (com motivo, fica no registro);
//  - vê quem está em que dia e quanto custou por dia/semana/mês (em €);
//  - dá ou tira tokens de um cliente (admin_grant_tokens / admin_revoke_token_grant,
//    ambos gravam em admin_audit_log);
//  - exporta CSV (planilha).
// Servidor: admin_checkin_resumo, admin_checkin_clientes, admin_list_settings,
// admin_update_setting e admin_update_money_setting (valores de dinheiro, com motivo).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import 'admin_checkin_premios_screen.dart';

class AdminCheckinScreen extends StatefulWidget {
  const AdminCheckinScreen({super.key});

  @override
  State<AdminCheckinScreen> createState() => _AdminCheckinScreenState();
}

enum _Periodo { dia, semana, mes }

class _AdminCheckinScreenState extends State<AdminCheckinScreen> {
  static const _kPremios = 'checkin_rewards';
  static const _kValidade = 'checkin_token_expiry_days';
  static const _premiosDoDanilo = [5, 5, 10, 10, 15, 15, 40];

  bool _loading = true;
  bool _salvando = false;
  String? _error;
  bool _faltaServidor = false;

  Map<String, dynamic> _defs = {};
  Map<String, dynamic>? _resumo;
  List<Map<String, dynamic>> _clientes = [];
  _Periodo _periodo = _Periodo.dia;

  bool _ligado = true;
  bool _exigeTel = true;
  bool _manhaOn = true;
  bool _noiteOn = true;
  bool _soOptIn = true;
  final _premios = List.generate(7, (_) => TextEditingController());
  final _validade = TextEditingController();
  final _horaManha = TextEditingController();
  final _horaNoite = TextEditingController();
  final _busca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _premios) {
      c.dispose();
    }
    _validade.dispose();
    _horaManha.dispose();
    _horaNoite.dispose();
    _busca.dispose();
    super.dispose();
  }

  bool get _temValoresDeDinheiro =>
      _defs.containsKey(_kPremios) && _defs.containsKey(_kValidade);

  /// Valor de 1 token em euros, lido das definições (token_value_cents_x100).
  double get _euroPorToken {
    final v = _defs['token_value_cents_x100'];
    final x100 = v is num ? v.toDouble() : double.tryParse('$v') ?? 50;
    return x100 / 10000;
  }

  String _euros(num tokens) =>
      '${(tokens * _euroPorToken).toStringAsFixed(2).replaceAll('.', ',')} €';

  static bool _semFuncao(Object e) =>
      e is PostgrestException &&
      (e.code == 'PGRST202' || e.message.contains('Could not find the function'));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _faltaServidor = false;
    });
    final supa = Supabase.instance.client;
    try {
      final defs = await supa.rpc('admin_list_settings', params: {'p_category': null});
      final mapa = <String, dynamic>{};
      for (final r in (defs as List)) {
        final m = (r as Map).cast<String, dynamic>();
        mapa['${m['key']}'] = m['value'];
      }
      Map<String, dynamic>? resumo;
      var clientes = <Map<String, dynamic>>[];
      var falta = false;
      try {
        resumo = Map<String, dynamic>.from(
            await supa.rpc('admin_checkin_resumo', params: {'p_dias': 400}) as Map);
        final busca = _busca.text.trim();
        final lista = await supa.rpc('admin_checkin_clientes',
            params: {'p_busca': busca.isEmpty ? null : busca, 'p_limite': 500});
        clientes = (lista as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (e) {
        if (!_semFuncao(e)) rethrow;
        falta = true;
      }
      if (!mounted) return;
      setState(() {
        _defs = mapa;
        _resumo = resumo;
        _clientes = clientes;
        _faltaServidor = falta;
        _preencher();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminCheckin] $e');
      if (!mounted) return;
      setState(() {
        _error = humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  bool _bool(String k, bool d) {
    final v = _defs[k];
    return v is bool ? v : d;
  }

  int _int(String k, int d) {
    final v = _defs[k];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
  }

  List<int> get _premiosAtuais {
    final v = _defs[_kPremios];
    if (v is List && v.length == 7 && v.every((e) => e is num)) {
      return v.map((e) => (e as num).toInt()).toList();
    }
    return _premiosDoDanilo;
  }

  void _preencher() {
    _ligado = _bool('checkin_enabled', true);
    _exigeTel = _bool('checkin_require_phone', true);
    _manhaOn = _bool('checkin_push_morning_enabled', true);
    _noiteOn = _bool('checkin_push_evening_enabled', true);
    _soOptIn = _bool('checkin_push_so_opt_in', true);
    final p = _premiosAtuais;
    for (var i = 0; i < 7; i++) {
      _premios[i].text = '${p[i]}';
    }
    _validade.text = '${_int(_kValidade, 60)}';
    _horaManha.text = '${_int('checkin_push_morning_hour', 11)}';
    _horaNoite.text = '${_int('checkin_push_evening_hour', 20)}';
  }

  Future<String?> _pedirMotivo(String titulo, String texto) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(texto),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Motivo (fica no registro de auditoria)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Confirmar')),
        ],
      ),
    );
    c.dispose();
    if (r == null || r.length < 3) return null;
    return r;
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    final messenger = ScaffoldMessenger.of(context);
    void aviso(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));

    final hm = int.tryParse(_horaManha.text.trim());
    final hn = int.tryParse(_horaNoite.text.trim());
    if (hm == null || hm < 0 || hm > 23 || hn == null || hn < 0 || hn > 23) {
      aviso('As horas têm de ser números de 0 a 23 (hora de Lisboa).');
      return;
    }
    if (_manhaOn && _noiteOn && hm == hn) {
      aviso('A hora da manhã e a da noite não podem ser iguais.');
      return;
    }

    // Definições simples (sem dinheiro).
    final simples = <String, Object>{
      'checkin_enabled': _ligado,
      'checkin_require_phone': _exigeTel,
      'checkin_push_morning_enabled': _manhaOn,
      'checkin_push_morning_hour': hm,
      'checkin_push_evening_enabled': _noiteOn,
      'checkin_push_evening_hour': hn,
      'checkin_push_so_opt_in': _soOptIn,
    }..removeWhere((k, v) => _defs[k] == v || !_defs.containsKey(k));

    // Valores de dinheiro (prémios e validade) — só se já existirem no servidor.
    final dinheiro = <String, Object>{};
    if (_temValoresDeDinheiro) {
      final premios = _premios.map((c) => int.tryParse(c.text.trim())).toList();
      if (premios.any((p) => p == null || p < 0 || p > 1000)) {
        aviso('Cada dia tem de ter um número inteiro de 0 a 1000 tokens.');
        return;
      }
      final validade = int.tryParse(_validade.text.trim());
      if (validade == null || validade < 1 || validade > 365) {
        aviso('A validade tem de ser de 1 a 365 dias.');
        return;
      }
      final lista = premios.cast<int>();
      if (lista.join(',') != _premiosAtuais.join(',')) dinheiro[_kPremios] = lista;
      if (validade != _int(_kValidade, 60)) dinheiro[_kValidade] = validade;
    }

    if (simples.isEmpty && dinheiro.isEmpty) {
      aviso('Nada mudou.');
      return;
    }

    String? motivo;
    if (dinheiro.isNotEmpty) {
      motivo = await _pedirMotivo(
        'Mudar valores em tokens?',
        'Isto muda quanto cada cliente ganha no check-in (dinheiro da Bora). '
            'Escreve o motivo.',
      );
      if (motivo == null) {
        aviso('Sem motivo (mínimo 3 letras) não gravo os valores.');
        return;
      }
    }

    setState(() => _salvando = true);
    final supa = Supabase.instance.client;
    try {
      for (final e in simples.entries) {
        await supa.rpc('admin_update_setting',
            params: {'p_key': e.key, 'p_value': e.value});
      }
      for (final e in dinheiro.entries) {
        await supa.rpc('admin_update_money_setting',
            params: {'p_key': e.key, 'p_value': e.value, 'p_reason': motivo});
      }
      aviso('Gravado.');
      await _load();
    } catch (e) {
      debugPrint('[AdminCheckin] salvar: $e');
      aviso(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _darTokens(Map<String, dynamic> c) async {
    final qtd = TextEditingController();
    final motivo = TextEditingController();
    final validade = TextEditingController(text: '60');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dar tokens a ${c['nome'] ?? c['email'] ?? 'cliente'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qtd,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Quantidade de tokens',
                helperText: '100 tokens = ${_euros(100)}'),
          ),
          TextField(
            controller: validade,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Validade (dias, 1 a 365)'),
          ),
          TextField(
            controller: motivo,
            decoration: const InputDecoration(
                labelText: 'Motivo (fica no registro de auditoria)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Dar')),
        ],
      ),
    );
    final n = int.tryParse(qtd.text.trim());
    final dias = int.tryParse(validade.text.trim());
    final m = motivo.text.trim();
    qtd.dispose();
    motivo.dispose();
    validade.dispose();
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (n == null || n < 1 || dias == null || m.length < 3) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Quantidade, validade e motivo (3+ letras) são obrigatórios.')));
      return;
    }
    try {
      await Supabase.instance.client.rpc('admin_grant_tokens', params: {
        'p_user_id': c['user_id'],
        'p_role': 'client',
        'p_amount': n,
        'p_reason': m,
        'p_validity_days': dias,
      });
      messenger.showSnackBar(SnackBar(content: Text('$n tokens dados. Ficou no registro.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e))));
    }
  }

  Future<void> _tirarTokens(Map<String, dynamic> c) async {
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> ativos;
    try {
      final r = await Supabase.instance.client.rpc('admin_get_user_tokens',
          params: {'p_user_id': c['user_id'], 'p_role': 'client', 'p_limit': 100});
      ativos = (((r as Map)['grants'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((g) => g['is_active'] == true)
          .toList();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e))));
      return;
    }
    if (!mounted) return;
    if (ativos.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Este cliente não tem tokens ativos.')));
      return;
    }
    final escolhido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Que lote de tokens tirar?'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Os tokens entram em lotes (um por pedido, check-in ou bônus). '
              'Tirar um lote anula-o inteiro.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          for (final g in ativos)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text('${g['amount']} tokens · ${g['source_order_id'] ?? 'dado pelo admin'}'
                  ' · vence ${'${g['expires_at'] ?? ''}'.split('T').first}'),
            ),
        ],
      ),
    );
    if (escolhido == null || !mounted) return;
    final motivo = await _pedirMotivo('Tirar ${escolhido['amount']} tokens?',
        'O lote deixa de contar para o saldo do cliente.');
    if (motivo == null) return;
    try {
      await Supabase.instance.client.rpc('admin_revoke_token_grant',
          params: {'p_token_id': escolhido['id'], 'p_reason': motivo});
      messenger.showSnackBar(SnackBar(
          content: Text('${escolhido['amount']} tokens tirados. Ficou no registro.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e))));
    }
  }

  // ── desenho ──────────────────────────────────────────────────────────────

  Widget _numero(String rotulo, String valor) => Expanded(
        child: Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Text(valor,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(rotulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      );

  List<Map<String, dynamic>> _linhas(String chave) =>
      (((_resumo?[chave]) as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  ({int checkins, int tokens}) _soma(Iterable<Map<String, dynamic>> l) {
    var c = 0, t = 0;
    for (final r in l) {
      c += (r['checkins'] as num?)?.toInt() ?? 0;
      t += (r['tokens'] as num?)?.toInt() ?? 0;
    }
    return (checkins: c, tokens: t);
  }

  static String _ddmm(Object? iso) {
    final p = '${iso ?? ''}'.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : '${iso ?? ''}';
  }

  Widget _estadoDoServidor() {
    final credito = _resumo?['funcao_de_credito_existe'] == true;
    final (cor, icone, texto) = _faltaServidor
        ? (
            Colors.red.shade50,
            Icons.cloud_off,
            'As funções do check-in ainda não estão no servidor (migração '
                '20261013060000_checkin_diario_base à espera de aplicação). '
                'O cartão não aparece no app e nenhum lembrete sai.'
          )
        : !credito
            ? (
                Colors.red.shade50,
                Icons.lock_clock,
                'Falta aplicar o crédito dos tokens (função client_daily_checkin — '
                    'mexe em dinheiro, espera o teu "vai"). Até lá o cartão NÃO '
                    'aparece no app e nenhum lembrete (push) sai, mesmo ligado aqui.'
              )
            : _ligado
                ? (
                    Colors.green.shade50,
                    Icons.check_circle,
                    'Ligado: o cartão aparece na home dos clientes com telemóvel válido.'
                  )
                : (
                    Colors.grey.shade200,
                    Icons.pause_circle,
                    'Desligado: o cartão não aparece e não sai nenhum lembrete.'
                  );
    return Card(
      color: cor,
      child: ListTile(leading: Icon(icone), title: Text(texto, style: const TextStyle(fontSize: 13))),
    );
  }

  Widget _configuracoes() {
    final premiosEditaveis = _temValoresDeDinheiro;
    final soma = _premios.fold<int>(0, (s, c) => s + (int.tryParse(c.text.trim()) ?? 0));
    InputDecoration dec(String l, [String? h]) =>
        InputDecoration(labelText: l, helperText: h, isDense: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Configurações', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Check-in ligado'),
        subtitle: const Text('Mostra o cartão "Check-in diário" na home do app do cliente.'),
        value: _ligado,
        onChanged: (v) => setState(() => _ligado = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Exigir telemóvel (celular) válido'),
        subtitle: const Text(
            'Sem SMS de confirmação no app: vale o número português gravado no perfil (9 dígitos começando por 9).'),
        value: _exigeTel,
        onChanged: (v) => setState(() => _exigeTel = v),
      ),
      const SizedBox(height: 8),
      Text(
        premiosEditaveis
            ? 'Tokens de cada dia (sequência = dias seguidos; falhou um dia volta ao Dia 1)'
            : 'Tokens de cada dia — bloqueado até aplicar o crédito (espera o "vai")',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < 7; i++)
          SizedBox(
            width: 78,
            child: TextField(
              key: Key('admin_checkin_premio_${i + 1}'),
              controller: _premios[i],
              enabled: premiosEditaveis,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: dec('Dia ${i + 1}'),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      Text('Semana completa: $soma tokens = ${_euros(soma)} por cliente.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      SizedBox(
        width: 220,
        child: TextField(
          controller: _validade,
          enabled: premiosEditaveis,
          keyboardType: TextInputType.number,
          decoration: dec('Validade dos tokens (dias)', '1 a 365'),
        ),
      ),
      const Divider(height: 24),
      const Text('Lembretes (push — notificação no celular)',
          style: TextStyle(fontWeight: FontWeight.w600)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Lembrete da manhã'),
        subtitle: const Text('"O teu check-in de hoje vale X tokens" — a quem ainda não fez hoje.'),
        value: _manhaOn,
        onChanged: (v) => setState(() => _manhaOn = v),
      ),
      SizedBox(
        width: 220,
        child: TextField(
          controller: _horaManha,
          keyboardType: TextInputType.number,
          decoration: dec('Hora da manhã (Lisboa, 0-23)'),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Lembrete da noite'),
        subtitle: const Text(
            '"Não percas a tua sequência de X dias!" — só a quem fez ontem e ainda não fez hoje.'),
        value: _noiteOn,
        onChanged: (v) => setState(() => _noiteOn = v),
      ),
      SizedBox(
        width: 220,
        child: TextField(
          controller: _horaNoite,
          keyboardType: TextInputType.number,
          decoration: dec('Hora da noite (Lisboa, 0-23)'),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Só quem aceitou promoções'),
        subtitle: const Text(
            'Opt-in de marketing (o cliente marcou no perfil que aceita promoções) — regra RGPD de 23/09. '
            'Desligar é decisão sua.'),
        value: _soOptIn,
        onChanged: (v) => setState(() => _soOptIn = v),
      ),
      const Text('No máximo 2 lembretes de check-in por pessoa por dia. '
          'Quem desligou as notificações no celular não recebe.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      FilledButton.icon(
        key: const Key('admin_checkin_salvar'),
        onPressed: _salvando ? null : _salvar,
        icon: _salvando
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save),
        label: const Text('Salvar'),
      ),
    ]);
  }

  Widget _totais() {
    final chave = switch (_periodo) {
      _Periodo.dia => 'por_dia',
      _Periodo.semana => 'por_semana',
      _Periodo.mes => 'por_mes',
    };
    final campo = switch (_periodo) {
      _Periodo.dia => 'dia',
      _Periodo.semana => 'semana',
      _Periodo.mes => 'mes',
    };
    final linhas = _linhas(chave);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tokens dados no check-in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 6),
      SegmentedButton<_Periodo>(
        segments: const [
          ButtonSegment(value: _Periodo.dia, label: Text('Por dia')),
          ButtonSegment(value: _Periodo.semana, label: Text('Por semana')),
          ButtonSegment(value: _Periodo.mes, label: Text('Por mês')),
        ],
        selected: {_periodo},
        onSelectionChanged: (s) => setState(() => _periodo = s.first),
      ),
      if (linhas.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Ainda ninguém fez check-in.'),
        ),
      for (final r in linhas.take(60))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
              '${_periodo == _Periodo.semana ? 'Semana de ' : ''}${_ddmm(r[campo])}'),
          trailing: Text(
              '${r['checkins']} check-ins · ${r['tokens']} tokens · ${_euros((r['tokens'] as num?) ?? 0)}'),
        ),
    ]);
  }

  Widget _listaClientes() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Clientes e dia da sequência',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 6),
      TextField(
        controller: _busca,
        decoration: InputDecoration(
          labelText: 'Procurar cliente (nome, email ou telefone)',
          helperText: 'Vazio = só quem já fez check-in. Com texto = qualquer cliente, para dar ou tirar tokens.',
          suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _load),
        ),
        onSubmitted: (_) => _load(),
      ),
      if (_clientes.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('Ninguém nesta lista.')),
      for (final c in _clientes)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: c['fez_hoje'] == true ? AppColors.success : Colors.grey.shade300,
            foregroundColor: c['fez_hoje'] == true ? Colors.white : Colors.black87,
            child: Text(c['dia_sequencia'] == null ? '–' : '${c['dia_sequencia']}'),
          ),
          title: Text('${c['nome'] ?? '—'}'),
          subtitle: Text([
            '${c['email'] ?? ''} · ${c['telefone'] ?? 'sem telefone'}'
                '${c['telemovel_confirmado'] == true ? '' : ' (inválido)'}',
            c['ultimo_checkin'] == null
                ? 'Nunca fez check-in'
                : 'Último: ${_ddmm(c['ultimo_checkin'])} · '
                    '${c['fez_hoje'] == true ? 'fez hoje' : (c['em_sequencia'] == true ? 'em sequência' : 'sequência perdida')}'
                    ' · ${c['total_checkins']} check-ins · ${c['total_tokens_checkin']} tokens ganhos',
            'Saldo agora: ${c['saldo_tokens'] ?? 0} tokens (${_euros((c['saldo_tokens'] as num?) ?? 0)})',
          ].join('\n')),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            tooltip: 'Dar ou tirar tokens',
            onSelected: (v) => v == 'dar' ? _darTokens(c) : _tirarTokens(c),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dar', child: Text('Dar tokens')),
              PopupMenuItem(value: 'tirar', child: Text('Tirar tokens')),
            ],
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final porDia = _linhas('por_dia');
    final hoje = '${_resumo?['hoje'] ?? ''}';
    // Datas do servidor (AAAA-MM-DD, dia de Lisboa) em UTC: a conta de dias não
    // pode passar pela hora local do aparelho (a mudança de hora comia um dia).
    final hojeData = DateTime.tryParse('${hoje}T00:00:00Z');
    final deHoje = _soma(porDia.where((r) => '${r['dia']}' == hoje));
    // Pelo calendário (não "os 7 dias com check-ins"): de hoje-6 a hoje.
    final desde = hojeData
        ?.subtract(const Duration(days: 6))
        .toIso8601String()
        .substring(0, 10);
    final ultimos7 = _soma(porDia.where(
        (r) => desde != null && '${r['dia']}'.compareTo(desde) >= 0));
    final mesAtual = hojeData == null
        ? ''
        : '${hojeData.year}-${hojeData.month.toString().padLeft(2, '0')}-01';
    final esteMes = _soma(_linhas('por_mes').where((r) => '${r['mes']}' == mesAtual));
    final comPromocoes = (_resumo?['clientes_com_promocoes_aceites'] as num?)?.toInt();
    final porDiaSeq = (_resumo?['pessoas_por_dia_da_sequencia'] as Map?) ?? const {};
    final lembretes = (_resumo?['lembretes_hoje'] as Map?) ?? const {};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Check-in diário',
        actions: [
          AdminCsvButton(
            nome: 'checkin_clientes',
            colunas: const [
              ('nome', 'cliente'),
              ('email', 'email'),
              ('telefone', 'telefone'),
              ('telemovel_confirmado', 'telefone válido'),
              ('ultimo_checkin', 'último check-in'),
              ('dia_sequencia', 'dia da sequência'),
              ('em_sequencia', 'em sequência'),
              ('fez_hoje', 'fez hoje'),
              ('total_checkins', 'check-ins'),
              ('total_tokens_checkin', 'tokens ganhos no check-in'),
              ('saldo_tokens', 'saldo de tokens'),
            ],
            linhas: () => [
              for (final c in _clientes)
                {
                  ...c,
                  for (final k in const ['telemovel_confirmado', 'em_sequencia', 'fez_hoje'])
                    k: c[k] == true ? 'sim' : 'não',
                },
            ],
          ),
          AdminCsvButton(
            nome: 'checkin_tokens_por_dia',
            colunas: const [
              ('dia', 'dia'),
              ('checkins', 'check-ins'),
              ('tokens', 'tokens'),
              ('euros', 'custo (€)'),
            ],
            linhas: () => [
              for (final r in porDia)
                {
                  ...r,
                  'euros': (((r['tokens'] as num?) ?? 0) * _euroPorToken)
                      .toStringAsFixed(2)
                      .replaceAll('.', ','),
                },
            ],
          ),
          IconButton(
            tooltip: 'Prêmios dos marcos (10, 15 e 30 dias)',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminCheckinPremiosScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _estadoDoServidor(),
                    if (!_faltaServidor) ...[
                      Row(children: [
                        _numero('hoje\n${deHoje.checkins} check-ins', _euros(deHoje.tokens)),
                        _numero('últimos 7 dias\n${ultimos7.checkins} check-ins', _euros(ultimos7.tokens)),
                        _numero('este mês\n${esteMes.checkins} check-ins', _euros(esteMes.tokens)),
                      ]),
                      Text(
                        'Pessoas em sequência por dia: '
                        '${[for (var d = 1; d <= 7; d++) 'Dia $d: ${porDiaSeq['$d'] ?? 0}'].join(' · ')}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        'Lembretes registados hoje (pedidos ao serviço de push; não confirma a entrega): '
                        'manhã ${lembretes['manha'] ?? 0} · noite ${lembretes['noite'] ?? 0}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (_soOptIn && comPromocoes == 0)
                        Card(
                          key: const Key('admin_checkin_aviso_opt_in'),
                          color: Colors.red.shade50,
                          child: const ListTile(
                            leading: Icon(Icons.notifications_off),
                            title: Text(
                              'Nenhum cliente aceitou promoções (opt-in de marketing). Com "Só quem aceitou '
                              'promoções" ligado, os lembretes das 11h e das 20h não chegam a ninguém.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _configuracoes(),
                      const Divider(height: 32),
                      _totais(),
                      const Divider(height: 32),
                      _listaClientes(),
                    ],
                  ],
                ),
    );
  }
}
