// Missão agentes-email-2026-10-21 — E-MAIL DOS AGENTES (painel admin, PT-BR).
//
// Cada agente tem e-mail próprio em boraguarda.com (emerson@, suporte@, parceiros@, vendas@,
// redes@, radar@, assinaturas@). O que chega de fora passa pela Cloudflare (Email Routing →
// Worker agentes-email) e pela Edge Function agentes-email-receber, e fica na tabela
// `agentes_email` (RLS: só admin). As respostas saem pela Edge Function agentes-email-enviar
// (Resend), que também regista o envio.
//
// Este ecrã mostra: o interruptor da caixa e o limite diário (platform_settings), a caixa de
// entrada e os enviados de cada agente, o e-mail inteiro, os anexos (link assinado do bucket
// privado), e deixa marcar lido / não lido / arquivar, responder, reenviar e escrever um novo.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

const List<String> kAgentesEmail = [
  'emerson',
  'suporte',
  'parceiros',
  'vendas',
  'redes',
  'radar',
  'assinaturas',
];

const String kDominioAgentes = 'boraguarda.com';

/// Texto curto do estado de um e-mail, em PT-BR.
String rotuloEstadoEmail(String? estado) {
  switch (estado) {
    case 'novo':
      return 'novo';
    case 'lido':
      return 'lido';
    case 'tratado':
      return 'respondido';
    case 'arquivado':
      return 'arquivado';
    case 'enviado':
      return 'enviado';
    case 'falhou':
      return 'falhou';
    default:
      return estado ?? '—';
  }
}

/// Data/hora local curta (dd/mm HH:mm) a partir do ISO do banco.
String dataCurtaEmail(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '—';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)}';
}

class AdminAgentesEmailScreen extends StatefulWidget {
  const AdminAgentesEmailScreen({super.key});

  @override
  State<AdminAgentesEmailScreen> createState() => _AdminAgentesEmailScreenState();
}

class _AdminAgentesEmailScreenState extends State<AdminAgentesEmailScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  String _agente = 'emerson';
  bool _verEnviados = false;
  bool _carregando = true;
  String? _erro;
  Map<String, Map<String, dynamic>> _resumo = {};
  List<Map<String, dynamic>> _emails = [];
  bool _ativo = true;
  int _limiteDia = 80;
  bool _gravandoSetting = false;

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
      final resumo = await _sb.rpc('agentes_email_resumo');
      final settings = await _sb
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', ['agentes_email_ativo', 'agentes_email_limite_dia']);
      final linhas = await _sb
          .from('agentes_email')
          .select('id, direcao, agente, de, para, assunto, estado, anexos, erro, criado_em')
          .eq('agente', _agente)
          .eq('direcao', _verEnviados ? 'saida' : 'entrada')
          .order('criado_em', ascending: false)
          .limit(100);
      if (!mounted) return;
      final porAgente = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(resumo as List? ?? const [])) {
        porAgente['${r['agente']}'] = r;
      }
      var ativo = true;
      var limite = 80;
      for (final s in List<Map<String, dynamic>>.from(settings)) {
        if (s['key'] == 'agentes_email_ativo') ativo = s['value'] != false && s['value'] != 'false';
        if (s['key'] == 'agentes_email_limite_dia') limite = int.tryParse('${s['value']}') ?? 80;
      }
      setState(() {
        _resumo = porAgente;
        _emails = List<Map<String, dynamic>>.from(linhas);
        _ativo = ativo;
        _limiteDia = limite;
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

  void _snack(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _gravarSetting(String chave, Object valor, String ok) async {
    setState(() => _gravandoSetting = true);
    try {
      await _sb.rpc('admin_update_setting', params: {'p_key': chave, 'p_value': valor});
      _snack(ok);
      await _carregar();
    } catch (e) {
      _snack('Não foi possível gravar: $e');
    } finally {
      if (mounted) setState(() => _gravandoSetting = false);
    }
  }

  Future<void> _editarLimite() async {
    final ctrl = TextEditingController(text: '$_limiteDia');
    final novo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limite diário de envios'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            helperText: 'Todas as caixas juntas, desde a meia-noite de Lisboa (agentes_email_limite_dia)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (novo == null) return;
    if (novo < 1 || novo > 1000) {
      _snack('Use um número entre 1 e 1000.');
      return;
    }
    await _gravarSetting('agentes_email_limite_dia', novo, 'Limite diário: $novo envios.');
  }

  /// Chama a Edge Function de envio; devolve null quando correu bem, ou o motivo do erro.
  Future<String?> _chamarEnviar(Map<String, dynamic> corpo) async {
    try {
      final res = await _sb.functions.invoke('agentes-email-enviar', body: corpo);
      final data = res.data;
      if (data is Map && data['ok'] == true) return null;
      return '${data is Map ? (data['error'] ?? data) : data}';
    } on FunctionException catch (e) {
      final d = e.details;
      return '${d is Map ? (d['error'] ?? d) : d ?? e.status}';
    } catch (e) {
      return '$e';
    }
  }

  Future<void> _novoEmail() async {
    final para = TextEditingController();
    final assunto = TextEditingController();
    final texto = TextEditingController();
    var de = _agente;
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Novo e-mail'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: de,
                  decoration: const InputDecoration(labelText: 'De (agente)'),
                  items: [
                    for (final a in kAgentesEmail)
                      DropdownMenuItem(value: a, child: Text('$a@$kDominioAgentes')),
                  ],
                  onChanged: (v) => setD(() => de = v ?? de),
                ),
                TextField(
                  controller: para,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Para (separe vários por vírgula)'),
                ),
                TextField(controller: assunto, decoration: const InputDecoration(labelText: 'Assunto')),
                TextField(
                  controller: texto,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: 'Mensagem'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    final corpo = {'agente': de, 'para': para.text.trim(), 'assunto': assunto.text.trim(), 'texto': texto.text};
    para.dispose();
    assunto.dispose();
    texto.dispose();
    if (enviar != true) return;
    final erro = await _chamarEnviar(corpo);
    _snack(erro == null ? 'E-mail enviado.' : 'Não foi enviado: $erro');
    await _carregar();
  }

  Future<void> _abrir(Map<String, dynamic> resumoLinha) async {
    final mudou = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _DetalheEmail(
        id: '${resumoLinha['id']}',
        chamarEnviar: _chamarEnviar,
      ),
    ));
    if (mudou == true || resumoLinha['estado'] == 'novo') await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'E-mail dos agentes',
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ativo ? _novoEmail : null,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Novo e-mail'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      _cartaoInterruptor(),
                      const SizedBox(height: 8),
                      _seletorAgentes(),
                      const SizedBox(height: 8),
                      _seletorDirecao(),
                      const SizedBox(height: 4),
                      if (_emails.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _verEnviados
                                ? '$_agente@ ainda não enviou nada.'
                                : 'Nenhum e-mail na caixa de $_agente@.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      for (final e in _emails) _linhaEmail(e),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoInterruptor() {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Caixa dos agentes ligada'),
            subtitle: Text(
              _ativo
                  ? 'Recebe e envia normalmente (agentes_email_ativo)'
                  : 'DESLIGADA: e-mails de fora são devolvidos para tentar mais tarde, e nada é enviado',
            ),
            value: _ativo,
            onChanged: _gravandoSetting
                ? null
                : (v) => _gravarSetting('agentes_email_ativo', v, v ? 'Caixa ligada.' : 'Caixa desligada.'),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.speed_outlined),
            title: Text('Limite: $_limiteDia envios por dia'),
            subtitle: const Text('Todas as caixas juntas (o plano grátis do Resend aguenta 100/dia)'),
            trailing: IconButton(
              onPressed: _gravandoSetting ? null : _editarLimite,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Mudar limite',
            ),
          ),
        ],
      ),
    );
  }

  Widget _seletorAgentes() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in kAgentesEmail)
          ChoiceChip(
            selected: a == _agente,
            label: Text(_rotuloAgente(a)),
            onSelected: (_) {
              setState(() => _agente = a);
              _carregar();
            },
          ),
      ],
    );
  }

  String _rotuloAgente(String a) {
    final r = _resumo[a];
    final novos = (r?['nao_lidos'] as num?)?.toInt() ?? 0;
    return novos > 0 ? '$a@ · $novos novos' : '$a@';
  }

  Widget _seletorDirecao() {
    return Row(
      children: [
        ChoiceChip(
          selected: !_verEnviados,
          label: const Text('Caixa de entrada'),
          onSelected: (_) {
            setState(() => _verEnviados = false);
            _carregar();
          },
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          selected: _verEnviados,
          label: const Text('Enviados'),
          onSelected: (_) {
            setState(() => _verEnviados = true);
            _carregar();
          },
        ),
      ],
    );
  }

  Widget _linhaEmail(Map<String, dynamic> e) {
    final novo = e['estado'] == 'novo';
    final falhou = e['estado'] == 'falhou';
    final anexos = List<Map<String, dynamic>>.from((e['anexos'] as List?) ?? const []);
    final quem = _verEnviados ? 'para ${e['para'] ?? '—'}' : '${e['de'] ?? '—'}';
    return Card(
      child: ListTile(
        leading: Icon(
          _verEnviados ? Icons.outbox_outlined : (novo ? Icons.mark_email_unread_outlined : Icons.drafts_outlined),
          color: falhou ? AppColors.error : (novo ? AppColors.primary : AppColors.textSecondary),
        ),
        title: Text(
          '${e['assunto'] ?? '(sem assunto)'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: novo ? FontWeight.w700 : FontWeight.w500),
        ),
        subtitle: Text(
          '$quem\n${dataCurtaEmail('${e['criado_em']}')} · ${rotuloEstadoEmail('${e['estado']}')}'
          '${falhou && e['erro'] != null ? ' · ${e['erro']}' : ''}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: anexos.isEmpty ? null : const Icon(Icons.attach_file, size: 18),
        onTap: () => _abrir(e),
      ),
    );
  }
}

/// O e-mail inteiro + ações.
class _DetalheEmail extends StatefulWidget {
  const _DetalheEmail({required this.id, required this.chamarEnviar});

  final String id;
  final Future<String?> Function(Map<String, dynamic> corpo) chamarEnviar;

  @override
  State<_DetalheEmail> createState() => _DetalheEmailState();
}

class _DetalheEmailState extends State<_DetalheEmail> {
  SupabaseClient get _sb => Supabase.instance.client;

  Map<String, dynamic>? _e;
  String? _erro;
  bool _mudou = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar(marcarLido: true);
  }

  Future<void> _carregar({bool marcarLido = false}) async {
    try {
      final r = await _sb.from('agentes_email').select('*').eq('id', widget.id).single();
      if (marcarLido && r['direcao'] == 'entrada' && r['estado'] == 'novo') {
        await _sb.from('agentes_email').update({'estado': 'lido'}).eq('id', widget.id);
        r['estado'] = 'lido';
        _mudou = true;
      }
      if (!mounted) return;
      setState(() => _e = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString());
    }
  }

  void _snack(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _estado(String estado) async {
    setState(() => _ocupado = true);
    try {
      await _sb.from('agentes_email').update({'estado': estado}).eq('id', widget.id);
      _mudou = true;
      _snack('Marcado como ${rotuloEstadoEmail(estado)}.');
      await _carregar();
    } catch (e) {
      _snack('Não foi possível mudar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _abrirAnexo(Map<String, dynamic> a) async {
    final caminho = '${a['caminho'] ?? ''}';
    if (caminho.isEmpty) return;
    try {
      final url = await _sb.storage.from('agentes-email').createSignedUrl(caminho, 600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('Não foi possível abrir o anexo: $e');
    }
  }

  Future<void> _responder() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Responder como ${_e?['agente']}@'),
        content: TextField(
          controller: ctrl,
          minLines: 4,
          maxLines: 10,
          autofocus: true,
          decoration: InputDecoration(helperText: 'Vai para ${_e?['de']}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar resposta')),
        ],
      ),
    );
    final texto = ctrl.text;
    ctrl.dispose();
    if (ok != true || texto.trim().isEmpty) return;
    setState(() => _ocupado = true);
    final erro = await widget.chamarEnviar({'responder_a': widget.id, 'texto': texto});
    if (!mounted) return;
    setState(() => _ocupado = false);
    _snack(erro == null ? 'Resposta enviada.' : 'Não foi enviada: $erro');
    if (erro == null) {
      _mudou = true;
      await _carregar();
    }
  }

  Future<void> _reenviar() async {
    setState(() => _ocupado = true);
    final erro = await widget.chamarEnviar({'reenviar': widget.id});
    if (!mounted) return;
    setState(() => _ocupado = false);
    _snack(erro == null ? 'Reenviado.' : 'Não foi reenviado: $erro');
    if (erro == null) _mudou = true;
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_mudou);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: e == null ? 'E-mail' : '${e['assunto'] ?? '(sem assunto)'}'),
        body: _erro != null
            ? Center(child: Text('Erro: $_erro', style: const TextStyle(color: AppColors.error)))
            : e == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _cabecalho(e),
                      const SizedBox(height: 8),
                      _acoes(e),
                      const SizedBox(height: 8),
                      ..._anexos(e),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            ('${e['texto'] ?? ''}').trim().isEmpty ? '(sem texto)' : '${e['texto']}',
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _cabecalho(Map<String, dynamic> e) {
    Widget l(String k, String? v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 70, child: Text(k, style: const TextStyle(color: AppColors.textSubtle, fontSize: 12))),
              Expanded(child: SelectableText(v ?? '—')),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            l('De', '${e['de']}'),
            l('Para', '${e['para']}'),
            l('Assunto', '${e['assunto'] ?? '(sem assunto)'}'),
            l('Data', dataCurtaEmail('${e['criado_em']}')),
            l('Caixa', '${e['agente']}@$kDominioAgentes · ${e['direcao'] == 'saida' ? 'enviado' : 'recebido'}'),
            l('Estado', rotuloEstadoEmail('${e['estado']}')),
            if (e['erro'] != null) l('Erro', '${e['erro']}'),
          ],
        ),
      ),
    );
  }

  Widget _acoes(Map<String, dynamic> e) {
    final entrada = e['direcao'] == 'entrada';
    final estado = '${e['estado']}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (entrada)
          FilledButton.icon(
            onPressed: _ocupado ? null : _responder,
            icon: const Icon(Icons.reply),
            label: const Text('Responder'),
          ),
        if (!entrada)
          FilledButton.icon(
            onPressed: _ocupado ? null : _reenviar,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Reenviar'),
          ),
        if (entrada && estado != 'novo')
          OutlinedButton(
            onPressed: _ocupado ? null : () => _estado('novo'),
            child: const Text('Marcar como não lido'),
          ),
        if (entrada && estado == 'novo')
          OutlinedButton(
            onPressed: _ocupado ? null : () => _estado('lido'),
            child: const Text('Marcar como lido'),
          ),
        if (entrada && estado != 'arquivado')
          OutlinedButton(
            onPressed: _ocupado ? null : () => _estado('arquivado'),
            child: const Text('Arquivar'),
          ),
      ],
    );
  }

  List<Widget> _anexos(Map<String, dynamic> e) {
    final anexos = List<Map<String, dynamic>>.from((e['anexos'] as List?) ?? const []);
    if (anexos.isEmpty) return const [];
    return [
      Card(
        child: Column(
          children: [
            for (final a in anexos)
              ListTile(
                dense: true,
                leading: const Icon(Icons.attach_file),
                title: Text('${a['nome']}'),
                subtitle: Text(a['guardado'] == true
                    ? '${a['tipo']} · ${a['bytes']} bytes'
                    : 'Não guardado (${a['motivo'] ?? 'motivo desconhecido'}) · ${a['bytes']} bytes'),
                trailing: a['guardado'] == true
                    ? IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Abrir (link assinado, 10 min)',
                        onPressed: () => _abrirAnexo(a),
                      )
                    : null,
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}
